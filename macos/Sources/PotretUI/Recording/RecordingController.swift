import AppKit
import Observation
import PotretCapture
import PotretCore
import PotretRecord
import ScreenCaptureKit
import SwiftUI

/// Runs a recording and its HUD.
///
/// The most important property here is that a recording can always be stopped. A recording you
/// cannot stop is this feature's version of a stuck fullscreen overlay: it keeps writing to disk,
/// keeps the screen-capture indicator lit, and leaves the user with no recourse. So there are
/// three independent stops — the HUD button, the menu-bar item, and a hard duration cap that
/// finalises the file rather than discarding it.
@MainActor
@Observable
public final class RecordingController {
    /// Beyond this a recording is almost certainly forgotten. The file is finalised, not dropped.
    private static let maximumDuration: TimeInterval = 60 * 60

    public private(set) var isRecording = false
    public private(set) var isPaused = false
    public private(set) var elapsed: TimeInterval = 0

    private var session: RecordingSession?
    private var hud: OverlayPanel?
    /// Hosted once; the HUD observes it. Rebuilding the hosting view on every tick meant the
    /// Stop button was destroyed and recreated four times a second, so a click could land on a
    /// view that no longer existed.
    private let hudState = HUDState()
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?

    private let onFinished: (Recording) -> Void
    private let onError: (any Error) -> Void

    public init(
        onFinished: @escaping (Recording) -> Void,
        onError: @escaping (any Error) -> Void
    ) {
        self.onFinished = onFinished
        self.onError = onError
    }

    // MARK: Control

    public func start(target: CaptureTarget, settings: RecordingSettings) async {
        guard !isRecording else { return }
        let session = RecordingSession(settings: settings)
        do {
            try await session.start(target: target)
        } catch {
            onError(error)
            return
        }

        self.session = session
        isRecording = true
        isPaused = false
        elapsed = 0
        pausedTotal = 0
        startedAt = Date()
        showHUD()
        startTicking()
    }

    public func togglePause() {
        guard let session, isRecording else { return }
        if isPaused {
            session.resume()
            if let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
            pausedAt = nil
            isPaused = false
        } else {
            session.pause()
            pausedAt = Date()
            isPaused = true
        }
        hudState.isPaused = isPaused
    }

    public func stop() {
        guard let session, isRecording else { return }
        isRecording = false
        isPaused = false
        ticker?.cancel()
        ticker = nil
        hideHUD()

        Task { [weak self] in
            guard let self else { return }
            do {
                let recording = try await session.stop()
                self.onFinished(recording)
            } catch {
                self.onError(error)
            }
            self.session = nil
        }
    }

    // MARK: HUD

    private func showHUD() {
        let size = CGSize(width: 220, height: 44)
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: .statusBar
        )
        panel.isMovableByWindowBackground = true
        // Top-centre of the active screen: out of the way of most content, and not on top of the
        // bottom-left corner where the capture popup and corner stack live.
        let area = PanelPlacement.activeScreen.visibleFrame
        panel.setFrame(
            NSRect(
                x: area.midX - size.width / 2,
                y: area.maxY - size.height - Space.s,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        hud = panel
        hudState.elapsed = 0
        hudState.isPaused = false
        hudState.onTogglePause = { [weak self] in self?.togglePause() }
        hudState.onStop = { [weak self] in self?.stop() }
        panel.host(RecordingHUDHost(state: hudState))
        panel.present()
    }

    private func hideHUD() {
        hud?.orderOut(nil)
        hud = nil
    }

    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.isRecording else { return }
                if !self.isPaused, let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt) - self.pausedTotal
                    self.hudState.elapsed = self.elapsed
                }
                // A forgotten recording is finalised rather than left running forever.
                if self.elapsed >= Self.maximumDuration {
                    Log.capture.error("recording hit the duration cap — stopping")
                    self.stop()
                    return
                }
            }
        }
    }
}

/// Observable HUD state, so the view is hosted once and updated in place.
@MainActor
@Observable
final class HUDState {
    var elapsed: TimeInterval = 0
    var isPaused = false
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
}

struct RecordingHUDHost: View {
    @Bindable var state: HUDState

    var body: some View {
        RecordingHUD(
            elapsed: state.elapsed,
            isPaused: state.isPaused,
            onTogglePause: state.onTogglePause,
            onStop: state.onStop
        )
    }
}

/// Elapsed time, pause and stop. Small, draggable, always reachable.
struct RecordingHUD: View {
    let elapsed: TimeInterval
    let isPaused: Bool
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Circle()
                .fill(isPaused ? Color.secondary : Color.red)
                .frame(width: Space.s, height: Space.s)
                .opacity(isPaused ? 0.5 : 1)

            Text(DurationFormat.clock(elapsed))
                .font(TypeRamp.mono)

            Spacer(minLength: 0)

            Button(action: onTogglePause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .help(isPaused ? "Resume" : "Pause")

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .tint(.red)
            .help("Stop recording")
        }
        .padding(.horizontal, Space.m)
        .frame(height: 44)
        .potretSurface(.hud, radius: Radius.md)
    }
}
