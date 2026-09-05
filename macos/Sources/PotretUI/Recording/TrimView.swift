import AVFoundation
import AVKit
import Observation
import PotretCore
import PotretRecord
import SwiftUI

/// State for reviewing and trimming a finished recording.
@MainActor
@Observable
public final class TrimModel {
    public let url: URL
    public let duration: TimeInterval
    public let pixelSize: CGSize
    public var start: TimeInterval = 0
    public var end: TimeInterval
    public var isExporting = false
    public var status: String?
    /// Thumbnails sampled evenly across the recording — the scrubber is the recording itself.
    public private(set) var frames: [NSImage] = []
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var isPlaying = false

    let player: AVPlayer
    private var timeObserver: Any?

    public init(recording: Recording) {
        url = recording.url
        // A zero duration would make every range invalid; treat it as a minimum.
        duration = max(recording.duration, 0.1)
        pixelSize = recording.pixelSize
        end = max(recording.duration, 0.1)
        player = AVPlayer(url: recording.url)
        player.actionAtItemEnd = .none
    }

    public var trimmedDuration: TimeInterval { max(0, end - start) }

    /// Whether trimming would change anything, so Save can say what it will do.
    public var isTrimmed: Bool {
        start > 0.05 || end < duration - 0.05
    }

    public var gifEstimate: String {
        let scale = min(1, 640 / max(pixelSize.width, 1))
        let bytes = VideoTools.estimatedGIFBytes(
            duration: trimmedDuration,
            frameRate: 15,
            width: pixelSize.width * scale,
            height: pixelSize.height * scale
        )
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: Playback

    /// Review loops inside the selection, so what plays is exactly what will be saved.
    public func startObserving() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying, time.seconds >= self.end - 0.02 {
                    self.seek(self.start)
                }
            }
        }
    }

    /// Explicit rather than deinit: a deinit on a @MainActor type cannot touch its state under
    /// strict concurrency, and the observer must be removed from the player it was added to.
    public func stop() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    public func seek(_ time: TimeInterval) {
        currentTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    public func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime < start || currentTime >= end - 0.02 { seek(start) }
            player.play()
            isPlaying = true
        }
    }

    public func playTrimmed() {
        seek(start)
        player.play()
        isPlaying = true
    }

    /// Move a handle. Dragging pauses playback and previews the new edge, so the frame under the
    /// pointer is the frame that will be the cut.
    public func setStart(_ time: TimeInterval) {
        player.pause()
        isPlaying = false
        start = min(max(0, time), end - 0.25)
        seek(start)
    }

    public func setEnd(_ time: TimeInterval) {
        player.pause()
        isPlaying = false
        end = max(min(duration, time), start + 0.25)
        seek(end)
    }

    // MARK: Frames

    public func loadFrames(count: Int = 24) {
        guard frames.isEmpty else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let times = (0..<count).map {
            CMTime(seconds: duration * Double($0) / Double(count), preferredTimescale: 600)
        }
        Task { [weak self] in
            var collected: [NSImage] = []
            for await result in generator.images(for: times) {
                if let cg = try? result.image {
                    collected.append(NSImage(cgImage: cg, size: .zero))
                }
            }
            self?.frames = collected
        }
    }
}

/// AVKit's player, wrapped directly.
///
/// Not SwiftUI's `VideoPlayer`: that type lives in the `_AVKit_SwiftUI` cross-import overlay, and
/// this project builds tests with `-disable-cross-import-overlays` (the only way to import Testing
/// and Foundation together on a toolchain without Xcode — see TESTING.md). Controls are off; the
/// HUD is the transport.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

/// Review and trim a recording.
///
/// The video fills the window; everything else floats over the bottom of it. The scrubber is a
/// filmstrip of the recording itself with drag handles at each end, QuickTime-style — you see
/// what you are cutting rather than reading a number. Playback loops inside the selection, so
/// what plays is what will be saved.
public struct TrimView: View {
    @Bindable var model: TrimModel
    let onSave: (URL) -> Void
    let onExportGIF: (URL) -> Void
    let onDiscard: () -> Void

    public init(
        model: TrimModel,
        onSave: @escaping (URL) -> Void,
        onExportGIF: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.model = model
        self.onSave = onSave
        self.onExportGIF = onExportGIF
        self.onDiscard = onDiscard
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PlayerView(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            hud
                .padding(Space.m)
        }
        .background(.black)
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            model.loadFrames()
            model.startObserving()
            model.playTrimmed()
        }
        .onDisappear { model.stop() }
    }

    private var hud: some View {
        VStack(spacing: Space.s) {
            FilmstripScrubber(model: model)

            HStack(spacing: Space.m) {
                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: Space.l, height: Space.l)
                }
                .buttonStyle(.accessoryBar)
                .help(model.isPlaying ? "Pause" : "Play selection")
                .keyboardShortcut(.space, modifiers: [])

                Text("\(Clock.precise(model.start)) – \(Clock.precise(model.end))")
                    .font(TypeRamp.mono)
                Text("· \(Clock.precise(model.trimmedDuration))")
                    .font(TypeRamp.mono)
                    .foregroundStyle(.secondary)

                if let status = model.status {
                    Text(status)
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Close") { onDiscard() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                // The estimate is shown before the click: a GIF of a long recording can be
                // enormous, and there is no way to find out afterwards except by writing it.
                Button("GIF · ~\(model.gifEstimate)") { exportGIF() }
                    .buttonStyle(.bordered)
                    .disabled(model.isExporting)

                Button(model.isTrimmed ? "Save Trimmed" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.m)
        .potretSurface(.hud, radius: Radius.md)
    }

    private func save() {
        guard model.isTrimmed else {
            onSave(model.url)
            return
        }
        model.isExporting = true
        model.status = "Trimming…"
        Task {
            let output = model.url.deletingLastPathComponent()
                .appending(path: "trimmed-\(UUID().uuidString).mp4")
            do {
                try await VideoTools.trim(model.url, from: model.start, to: model.end, to: output)
                model.isExporting = false
                model.status = nil
                onSave(output)
            } catch {
                model.isExporting = false
                model.status = "Trim failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportGIF() {
        model.isExporting = true
        model.status = "Rendering GIF…"
        Task {
            let output = model.url.deletingLastPathComponent()
                .appending(path: "\(model.url.deletingPathExtension().lastPathComponent).gif")
            do {
                try await VideoTools.exportGIF(model.url, from: model.start, to: model.end, to: output)
                model.isExporting = false
                model.status = nil
                onExportGIF(output)
            } catch {
                model.isExporting = false
                model.status = "GIF failed: \(error.localizedDescription)"
            }
        }
    }
}

/// The recording as a strip of frames, with a draggable handle at each end and a playhead.
struct FilmstripScrubber: View {
    @Bindable var model: TrimModel
    private let height: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = width * CGFloat(model.start / model.duration)
            let endX = width * CGFloat(model.end / model.duration)
            let playheadX = width * CGFloat(min(max(model.currentTime, 0), model.duration) / model.duration)

            ZStack(alignment: .leading) {
                strip(width: width)
                    .contentShape(Rectangle())
                    // Click or drag anywhere on the strip to scrub.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.player.pause()
                                model.seek(time(at: value.location.x, width: width))
                            }
                    )

                // Dim what is cut.
                Rectangle().fill(.black.opacity(0.6))
                    .frame(width: max(0, startX), height: height)
                    .allowsHitTesting(false)
                Rectangle().fill(.black.opacity(0.6))
                    .frame(width: max(0, width - endX), height: height)
                    .offset(x: endX)
                    .allowsHitTesting(false)

                // Selection frame.
                Radius.shape(Radius.sm)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: max(0, endX - startX), height: height)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                // Playhead.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: height + Space.s)
                    .offset(x: playheadX - 1, y: 0)
                    .allowsHitTesting(false)

                handle
                    .offset(x: startX - Space.s / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.setStart(time(at: startX + value.translation.width, width: width))
                            }
                    )
                    .help("Drag to set where the recording starts")

                handle
                    .offset(x: endX - Space.s / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.setEnd(time(at: endX + value.translation.width, width: width))
                            }
                    )
                    .help("Drag to set where the recording ends")
            }
        }
        .frame(height: height)
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return TimeInterval(min(max(x, 0), width) / width) * model.duration
    }

    @ViewBuilder
    private func strip(width: CGFloat) -> some View {
        if model.frames.isEmpty {
            Radius.shape(Radius.sm).fill(.white.opacity(0.08))
                .frame(width: width, height: height)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(model.frames.enumerated()), id: \.offset) { _, frame in
                    Image(nsImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(model.frames.count), height: height)
                        .clipped()
                }
            }
            .clipShape(Radius.shape(Radius.sm))
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: Space.s, height: height + Space.s)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: Space.l))
            .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

/// Tenth-of-a-second times for trimming, where whole seconds are too coarse to place a cut.
enum Clock {
    static func precise(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let secs = clamped - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, secs)
    }
}
