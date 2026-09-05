import AVFoundation
import AVKit
import Observation
import PotretCore
import PotretRecord
import SwiftUI

/// State for trimming a finished recording.
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

    let player: AVPlayer

    public init(recording: Recording) {
        url = recording.url
        // A zero duration would make every slider range invalid; treat it as a minimum.
        duration = max(recording.duration, 0.1)
        pixelSize = recording.pixelSize
        end = max(recording.duration, 0.1)
        player = AVPlayer(url: recording.url)
    }

    public var trimmedDuration: TimeInterval { max(0, end - start) }

    /// Whether trimming would actually change anything, so Save can say what it will do.
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

    public func preview(_ time: TimeInterval) {
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    public func playTrimmed() {
        preview(start)
        player.play()
    }
}

/// AVKit's player, wrapped directly.
///
/// Not SwiftUI's `VideoPlayer`: that type lives in the `_AVKit_SwiftUI` cross-import overlay, and
/// this project builds tests with `-disable-cross-import-overlays` (the only way to import Testing
/// and Foundation together on a toolchain without Xcode — see TESTING.md). Wrapping AVPlayerView
/// also gives the standard transport controls for free.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

/// Trim a recording, then save it or export a GIF.
///
/// Passthrough export, so trimming re-muxes rather than re-encodes: it is near-instant and loses
/// no quality. Cuts land on keyframes, which is why the recorder writes one every two seconds.
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
        VStack(spacing: 0) {
            PlayerView(player: model.player)
                .frame(minHeight: 280)

            Divider()

            VStack(alignment: .leading, spacing: Space.m) {
                handles
                footer
            }
            .padding(Space.m)
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { model.preview(0) }
    }

    private var handles: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Trim")
                    .font(TypeRamp.heading)
                Spacer()
                Text("\(DurationFormat.clock(model.trimmedDuration)) of \(DurationFormat.clock(model.duration))")
                    .font(TypeRamp.mono)
                    .foregroundStyle(.secondary)
            }

            labelled("Start", DurationFormat.clock(model.start)) {
                Slider(
                    value: Binding(
                        get: { model.start },
                        set: { value in
                            // Keep at least a quarter second between the handles, or the export
                            // produces a file with no frames.
                            model.start = min(value, model.end - 0.25)
                            model.preview(model.start)
                        }
                    ),
                    in: 0...model.duration
                )
            }

            labelled("End", DurationFormat.clock(model.end)) {
                Slider(
                    value: Binding(
                        get: { model.end },
                        set: { value in
                            model.end = max(value, model.start + 0.25)
                            model.preview(model.end)
                        }
                    ),
                    in: 0...model.duration
                )
            }
        }
    }

    private func labelled(
        _ title: String,
        _ value: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        HStack(spacing: Space.s) {
            Text(title)
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            content()
            Text(value)
                .font(TypeRamp.mono)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            Button("Play", systemImage: "play.fill") { model.playTrimmed() }
                .buttonStyle(.bordered)

            if let status = model.status {
                Text(status)
                    .font(TypeRamp.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Discard", role: .destructive) { onDiscard() }
                .buttonStyle(.bordered)

            // The estimate is shown before the click, because a GIF of a long recording can be
            // enormous and there is no way to find out afterwards except by writing it.
            Button("GIF · ~\(model.gifEstimate)") { exportGIF() }
                .buttonStyle(.bordered)
                .disabled(model.isExporting)

            Button(model.isTrimmed ? "Save Trimmed" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting)
        }
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
                try await VideoTools.exportGIF(
                    model.url, from: model.start, to: model.end, to: output
                )
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
