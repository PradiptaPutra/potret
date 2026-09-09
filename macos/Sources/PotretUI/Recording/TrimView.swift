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
    /// Thumbnails sampled evenly across the recording — the timeline is the recording itself.
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

    /// Whether trimming would change anything, so Export can say what it will do.
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

    /// "1920 × 1200 · 0:32", for the header.
    public var summary: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) · \(Clock.short(duration))"
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
        currentTime = min(max(time, 0), duration)
        player.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 600),
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

    /// Nudge the playhead, staying inside the selection — outside it is footage being discarded,
    /// so stepping there is never what was meant.
    public func step(by seconds: TimeInterval) {
        pause()
        seek(min(max(currentTime + seconds, start), end))
    }

    public func goToStart() {
        pause()
        seek(start)
    }

    public func goToEnd() {
        pause()
        seek(end)
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }

    /// Move a handle. Dragging pauses playback and previews the new edge, so the frame under the
    /// pointer is the frame that will be the cut.
    public func setStart(_ time: TimeInterval) {
        pause()
        start = min(max(0, time), end - 0.25)
        seek(start)
    }

    public func setEnd(_ time: TimeInterval) {
        pause()
        end = max(min(duration, time), start + 0.25)
        seek(end)
    }

    // MARK: Frames

    /// How many thumbnails the timeline is worth for this recording.
    ///
    /// A fixed 24 was fine for a ten-second clip and useless for a ten-minute one, where it left
    /// one frame every twenty-five seconds. Roughly one per second and a half, bounded at both
    /// ends: enough to see, few enough to generate quickly.
    public var frameCount: Int {
        min(max(Int(duration / 1.5), 12), 80)
    }

    public func loadFrames() {
        loadFrames(count: frameCount)
    }

    public func loadFrames(count: Int) {
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
/// timeline is the transport.
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

/// Review and trim a recording: header, player, timeline.
///
/// Laid out like an editing application rather than a viewer with a slider — the timeline is its
/// own surface, carrying a time ruler, the recording as a clip with grab handles at each end, and
/// a transport. Playback loops inside the selection, so what plays is what will be saved.
public struct TrimView: View {
    @Bindable var model: TrimModel
    /// The finished file, plus the trimmed length when the recording was actually cut. A
    /// non-nil duration tells the coordinator to fold the edit back into the library entry
    /// rather than only exporting a copy of it.
    let onSave: (URL, TimeInterval?) -> Void
    let onExportGIF: (URL) -> Void
    let onDiscard: () -> Void

    /// How far the timeline is stretched. A thirty-second clip needs none; a ten-minute one is
    /// unusable without it, because a tenth of a second is a fraction of a pixel.
    @State private var zoom: CGFloat = 1
    private static let zoomLevels: [CGFloat] = [1, 2, 4, 8]

    public init(
        model: TrimModel,
        onSave: @escaping (URL, TimeInterval?) -> Void,
        onExportGIF: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.model = model
        self.onSave = onSave
        self.onExportGIF = onExportGIF
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            PlayerView(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            timeline
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.loadFrames()
            model.startObserving()
            model.playTrimmed()
        }
        .onDisappear { model.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "scissors")
                .foregroundStyle(Brand.amber)
            Text("Recording").font(TypeRamp.heading)
            Text(model.summary)
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: Space.m)

            if let status = model.status {
                HStack(spacing: Space.xs) {
                    ProgressView().controlSize(.small)
                    Text(status).font(TypeRamp.caption).foregroundStyle(.secondary)
                }
            }

            // One action, with the format as a choice inside it rather than a second button.
            Menu {
                Button(model.isTrimmed ? "Export Trimmed Video" : "Export Video") { save() }
                Button("Export as GIF (~\(model.gifEstimate))") { exportGIF() }
            } label: {
                Label(
                    model.isTrimmed ? "Export Trimmed" : "Export",
                    systemImage: "square.and.arrow.up"
                )
            } primaryAction: {
                save()
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(model.isExporting)
            .keyboardShortcut(.defaultAction)

            Button {
                onDiscard()
            } label: {
                Image(systemName: "xmark").frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .help("Close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Space.l)
        // Clears the traffic lights, which sit on this material rather than on a strip above it.
        .padding(.top, MainWindowController.titleBarHeight - Space.xs)
        .padding(.bottom, Space.s)
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(spacing: Space.s) {
            transport
            TimelineTrack(model: model, zoom: zoom)
            edges
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(VisualEffect(.sidebar))
    }

    private var transport: some View {
        HStack(spacing: Space.m) {
            transportButton("backward.end.fill", "Go to start") { model.goToStart() }
            transportButton("gobackward.5", "Back 5 seconds") { model.step(by: -5) }

            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(TypeRamp.heading)
                    .frame(width: Space.xxl, height: Space.xxl)
                    .background(Color.primary.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause" : "Play selection")
            .keyboardShortcut(.space, modifiers: [])

            transportButton("goforward.5", "Forward 5 seconds") { model.step(by: 5) }
            transportButton("forward.end.fill", "Go to end") { model.goToEnd() }

            Spacer(minLength: Space.m)

            HStack(spacing: Space.xs) {
                Text(Clock.precise(model.currentTime)).font(TypeRamp.mono)
                Text("/").foregroundStyle(.tertiary)
                Text(Clock.precise(model.duration))
                    .font(TypeRamp.mono)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Space.m)

            HStack(spacing: Space.xs) {
                transportButton("minus.magnifyingglass", "Zoom out") { changeZoom(by: -1) }
                    .disabled(zoom <= (Self.zoomLevels.first ?? 1))
                transportButton("plus.magnifyingglass", "Zoom in") { changeZoom(by: 1) }
                    .disabled(zoom >= (Self.zoomLevels.last ?? 1))
            }
        }
    }

    private func transportButton(
        _ symbol: String, _ help: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .frame(width: Space.l, height: Space.l)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func changeZoom(by step: Int) {
        guard let index = Self.zoomLevels.firstIndex(of: zoom) else { return }
        let next = min(max(index + step, 0), Self.zoomLevels.count - 1)
        withAnimation(Motion.quick) { zoom = Self.zoomLevels[next] }
    }

    /// The two cut points, and what survives between them.
    private var edges: some View {
        HStack {
            Label(Clock.precise(model.start), systemImage: "arrow.right.to.line")
            Spacer(minLength: 0)
            Text("\(Clock.precise(model.trimmedDuration)) selected")
                .foregroundStyle(Brand.amber)
            Spacer(minLength: 0)
            Label(Clock.precise(model.end), systemImage: "arrow.left.to.line")
        }
        .font(TypeRamp.mono)
        .foregroundStyle(.secondary)
    }

    // MARK: Export

    private func save() {
        guard model.isTrimmed else {
            onSave(model.url, nil)
            return
        }
        let trimmed = model.trimmedDuration
        model.isExporting = true
        model.status = "Trimming…"
        Task {
            // Into a scratch directory, never beside the recording. Writing here used to drop a
            // full-size `trimmed-<uuid>.mp4` into the history folder that nothing could ever
            // remove: the store lists by sidecar, so delete, Clear All, the retention limit and
            // the size readout in Settings all walked straight past it.
            let output = TrimScratch.url(extension: "mp4")
            do {
                try await VideoTools.trim(model.url, from: model.start, to: model.end, to: output)
                model.isExporting = false
                model.status = nil
                onSave(output, trimmed)
            } catch {
                TrimScratch.discard(output)
                model.isExporting = false
                model.status = "Trim failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportGIF() {
        model.isExporting = true
        model.status = "Rendering GIF…"
        Task {
            // Unique per export. The old name was derived from the recording, so a second GIF
            // from a different range silently replaced the first.
            let output = TrimScratch.url(extension: "gif")
            do {
                try await VideoTools.exportGIF(
                    model.url, from: model.start, to: model.end, to: output
                )
                model.isExporting = false
                model.status = nil
                onExportGIF(output)
            } catch {
                TrimScratch.discard(output)
                model.isExporting = false
                model.status = "GIF failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Scratch space for files the trimmer produces before they are filed away.
///
/// Its own subdirectory under the system temp folder, so anything left behind by a crash is the
/// operating system's problem rather than something that silently grows inside the user's
/// history for the life of the install.
enum TrimScratch {
    static var directory: URL {
        let url = URL.temporaryDirectory.appending(path: "potret-trim", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(extension ext: String) -> URL {
        directory.appending(path: "\(UUID().uuidString).\(ext)")
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Ruler, clip and playhead: the recording as something with a length, rather than a slider with
/// a value.
///
/// Every gesture reads the pointer's ABSOLUTE position in the track's coordinate space. The first
/// version added the drag's translation to a handle position recomputed from the model on every
/// frame — so each frame re-added the whole distance moved so far, and a handle shot to the edge
/// the moment it was touched. Reading where the pointer actually is cannot compound, and it keeps
/// working when the track is wider than the window and scrolled.
private struct TimelineTrack: View {
    @Bindable var model: TrimModel
    let zoom: CGFloat

    private static let space = "timeline"
    private let stripHeight: CGFloat = 60
    private let handleWidth: CGFloat = Space.m
    @State private var hoveringHandle = false

    var body: some View {
        GeometryReader { outer in
            // The clip is inset by one handle width at each end so a selection that reaches the
            // very start or the very end still has somewhere to put its handle. Without the
            // inset the leading handle sits at a negative offset, where the scroll view clips it
            // and it cannot be grabbed at all — which is the state every recording opens in.
            let full = max(outer.size.width, 1) * zoom
            let width = max(full - handleWidth * 2, 1)
            ScrollView(.horizontal, showsIndicators: zoom > 1) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Ruler(duration: model.duration, width: width)
                        .padding(.leading, handleWidth)
                    track(width: width, full: full)
                }
                .frame(width: full)
                .coordinateSpace(name: Self.space)
            }
            .scrollDisabled(zoom == 1)
        }
        .frame(height: stripHeight + Space.xl + Space.xs)
    }

    /// The whole track, laid out at `full` width with the clip inset inside it.
    ///
    /// Everything is positioned in one container rather than padding the clip and letting the
    /// handles hang past its edge. A view offset outside its parent's bounds is drawn but is not
    /// reliably hit-tested, so the leading handle at a zero start looked present and could not be
    /// grabbed — a drag on it scrubbed the playhead instead.
    private func track(width: CGFloat, full: CGFloat) -> some View {
        let inset = handleWidth
        let startX = inset + width * CGFloat(model.start / model.duration)
        let endX = inset + width * CGFloat(model.end / model.duration)
        let playheadX = inset + width * CGFloat(
            min(max(model.currentTime, 0), model.duration) / model.duration
        )

        return ZStack(alignment: .leading) {
            strip(width: width)
                .offset(x: inset)
                .contentShape(Rectangle())
                // Click or drag anywhere on the track to scrub.
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            model.player.pause()
                            model.seek(time(at: value.location.x, width: width))
                        }
                )

            // What is cut, dimmed.
            Rectangle().fill(.black.opacity(0.62))
                .frame(width: max(0, startX - inset), height: stripHeight)
                .offset(x: inset)
                .allowsHitTesting(false)
            Rectangle().fill(.black.opacity(0.62))
                .frame(width: max(0, inset + width - endX), height: stripHeight)
                .offset(x: endX)
                .allowsHitTesting(false)

            // The kept range as a clip with ends, which is what an editor shows.
            Radius.shape(Radius.sm)
                .strokeBorder(Brand.amber, lineWidth: 2)
                .frame(width: max(0, endX - startX), height: stripHeight)
                .offset(x: startX)
                .allowsHitTesting(false)

            Capsule()
                .fill(.white)
                .frame(width: 2, height: stripHeight + Space.s)
                .offset(x: playheadX - 1)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.6), radius: 2)

            // Handles hang outside the selection, so they are easy to grab on a trackpad and
            // never cover the first or last frame being kept.
            handle(leading: true)
                .offset(x: startX - handleWidth)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { model.setStart(time(at: $0.location.x, width: width)) }
                )
                .help("Drag to set where the recording starts")

            handle(leading: false)
                .offset(x: endX)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { model.setEnd(time(at: $0.location.x, width: width)) }
                )
                .help("Drag to set where the recording ends")
        }
        .frame(width: full, alignment: .leading)
    }

    /// `x` arrives in the scroll content's space, which includes the leading inset — so the
    /// inset comes off before the position becomes a time.
    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        let local = min(max(x - handleWidth, 0), width)
        return TimeInterval(local / width) * model.duration
    }

    @ViewBuilder
    private func strip(width: CGFloat) -> some View {
        if model.frames.isEmpty {
            Radius.shape(Radius.sm).fill(.white.opacity(0.08))
                .frame(width: width, height: stripHeight)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(model.frames.enumerated()), id: \.offset) { _, frame in
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: width / CGFloat(model.frames.count), height: stripHeight)
                        .clipped()
                }
            }
            .clipShape(Radius.shape(Radius.sm))
        }
    }

    private func handle(leading: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: leading ? Radius.sm : 0,
            bottomLeadingRadius: leading ? Radius.sm : 0,
            bottomTrailingRadius: leading ? 0 : Radius.sm,
            topTrailingRadius: leading ? 0 : Radius.sm,
            style: .continuous
        )
        .fill(Brand.amber)
        .frame(width: handleWidth, height: stripHeight)
        .overlay(
            Capsule()
                .fill(.black.opacity(0.55))
                .frame(width: 2, height: stripHeight * 0.32)
        )
        .brightness(hoveringHandle ? 0.12 : 0)
        .contentShape(Rectangle())
        // The pointer says "this slides sideways" before you grab it.
        .onHover { inside in
            hoveringHandle = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
    }
}

/// Time ticks above the track. The single thing that most makes a filmstrip read as a timeline
/// rather than as a scrubber.
private struct Ruler: View {
    let duration: TimeInterval
    let width: CGFloat

    var body: some View {
        let interval = Self.tickInterval(for: duration, width: width)
        let count = max(1, Int(duration / interval))

        ZStack(alignment: .topLeading) {
            ForEach(0...count, id: \.self) { index in
                let seconds = Double(index) * interval
                let x = width * CGFloat(seconds / duration)
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 1, height: Space.s)
                    Text(Clock.short(seconds))
                        .font(TypeRamp.mono)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .offset(x: x)
            }
        }
        .frame(width: width, height: Space.l + Space.xs, alignment: .topLeading)
        .clipped()
    }

    /// A round number of seconds that leaves labels far enough apart to read.
    static func tickInterval(for duration: TimeInterval, width: CGFloat) -> TimeInterval {
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        // About 64 points between labels; below that they collide.
        let wanted = duration / Double(max(1, Int(width / 64)))
        return candidates.first { $0 >= wanted } ?? candidates[candidates.count - 1]
    }
}

/// Times for trimming, where whole seconds are too coarse to place a cut.
enum Clock {
    /// Tenths, for the readouts either side of a cut.
    static func precise(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let secs = clamped - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, secs)
    }

    /// Whole seconds, for ruler ticks and the header, where a tenth is noise.
    static func short(_ seconds: TimeInterval) -> String {
        let clamped = Int(max(0, seconds))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
