import AppKit
import PotretCapture
import SwiftUI

/// Owns the Quick Access panel: placement, the auto-dismiss countdown, and hover pausing.
///
/// The panel is created once and reused. The Tauri app pre-created hidden webview windows at
/// launch because building one cost ~200ms and flashed black; an NSPanel with a SwiftUI content
/// view costs a millisecond or two, so it is built lazily on first capture instead.
/// Observable state for the popup.
///
/// The view is hosted once and observes this. It used to be rebuilt on every countdown tick —
/// `panel.host(...)` assigns a brand-new NSHostingView — which destroyed and recreated the entire
/// view four times a second. Any gesture in progress died with it, which is why dragging the
/// preview out never started: the drag source was replaced before the gesture could be recognised.
@MainActor
@Observable
final class PopupState {
    var preview: PopupPreview?
    var actions = CapturePopupActions()
}

@MainActor
public final class CapturePopupController {
    /// Matches the Tauri popup's 5s, which was tuned against real use — long enough to reach for
    /// Copy, short enough not to linger.
    public static let lifetime: Duration = .seconds(5)
    private static let tick: Duration = .milliseconds(50)

    private var panel: OverlayPanel?
    private var countdown: Task<Void, Never>?
    private let state = PopupState()
    private var hovering = false
    /// True while a drag started from the preview is still in flight.
    private var dragging = false
    private var remaining: Duration = CapturePopupController.lifetime

    public init() {}

    /// Show a freshly captured image.
    public func present(
        image: NSImage,
        pixelSize: CGSize,
        actions: CapturePopupActions
    ) {
        var actions = actions
        actions.dismiss = { [weak self] in self?.dismiss() }
        actions.dragBegan = { [weak self] in self?.holdForDrag() }
        // Dropped somewhere: the capture has gone where it was going, so the popup is done. Not
        // dropped: release the hold and let the countdown resume.
        actions.dragEnded = { [weak self] accepted in
            self?.dragging = false
            if accepted { self?.dismiss() }
        }
        state.actions = actions
        state.preview = PopupPreview(image: image, pixelSize: pixelSize, progress: 1)
        remaining = Self.lifetime

        let panel = existingPanel()
        panel.setFrame(
            PanelPlacement.bottomLeading(
                size: CGSize(width: CapturePopupView.width, height: CapturePopupView.height)
            ),
            display: false
        )
        installContent()
        panel.present()
        startCountdown()
    }

    /// Replace the action bar with a short confirmation, then dismiss.
    public func flash(_ message: String, thenDismissAfter delay: Duration = .milliseconds(700)) {
        state.preview?.flash = message
        countdown?.cancel()
        countdown = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    public func dismiss() {
        countdown?.cancel()
        countdown = nil
        panel?.orderOut(nil)
        state.preview = nil
    }

    /// Hold the popup open for a drag, and release once no button is down.
    ///
    /// The SwiftUI drag path reports no completion, so the end of the gesture is detected by
    /// polling the pressed buttons — the same approach the corner stack uses.
    private func holdForDrag() {
        dragging = true
        Task { [weak self] in
            while self?.dragging == true {
                try? await Task.sleep(for: .milliseconds(150))
                if NSEvent.pressedMouseButtons == 0 {
                    self?.dragging = false
                    return
                }
            }
        }
    }

    // MARK: Internals

    private func existingPanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(
            contentRect: NSRect(
                origin: .zero,
                size: CGSize(width: CapturePopupView.width, height: CapturePopupView.height)
            ),
            // .statusBar keeps it above ordinary windows without covering the menu bar.
            level: .statusBar
        )
        self.panel = panel
        return panel
    }

    /// Host the view once. Everything after this is a property change the view observes.
    private func installContent() {
        guard existingPanel().contentView is NSHostingView<AnyView> == false else { return }
        existingPanel().host(
            PopupHost(state: state)
                .onHover { [weak self] isInside in self?.hovering = isInside }
        )
    }

    /// Drive the countdown from a task rather than a display-link.
    ///
    /// Hovering pauses rather than restarts: the user is reading or aiming for a button, and
    /// resetting the clock on every pointer entry means a popup that never goes away.
    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard !Task.isCancelled else { return }
                // Hovering pauses; a drag holds indefinitely until the mouse comes back up.
                if self.hovering || self.dragging { continue }

                self.remaining -= Self.tick
                if self.remaining <= .zero {
                    self.dismiss()
                    return
                }
                self.state.preview?.progress = self.remaining.seconds / Self.lifetime.seconds
            }
        }
    }
}


/// Thin wrapper so the hosted view observes the state object rather than being replaced.
private struct PopupHost: View {
    @Bindable var state: PopupState

    var body: some View {
        if let preview = state.preview {
            CapturePopupView(preview: preview, actions: state.actions)
        }
    }
}

extension Duration {
    /// Seconds as a Double, for progress maths.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
