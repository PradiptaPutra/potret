import AppKit
import Observation
import PotretCore
import SwiftUI

/// Transient messages, in a panel rather than an alert.
///
/// `NSAlert.runModal()` from a menu-bar accessory that is not the active app can end up behind
/// whatever the user is looking at, or not draw at all — so errors were being reported into the
/// void. A non-activating panel at status-bar level is always visible, never steals focus, and
/// cannot block the app waiting for a click that may never come.
@MainActor
@Observable
final class ToastState {
    var message: String?
    var isError = false
}

@MainActor
public final class ToastController {
    private var panel: OverlayPanel?
    private let state = ToastState()
    private var dismissal: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, isError: Bool = false, for duration: Duration = .seconds(4)) {
        Log.ui.info("toast: \(message, privacy: .public)")
        state.message = message
        state.isError = isError

        let size = CGSize(width: 340, height: 56)
        let panel = existingPanel(size: size)
        let area = PanelPlacement.activeScreen.visibleFrame
        panel.setFrame(
            NSRect(
                x: area.midX - size.width / 2,
                y: area.minY + Space.xxl,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        panel.present()

        dismissal?.cancel()
        // Errors linger; confirmations do not. A message you cannot read is the same as none.
        let visibleFor = isError ? duration + .seconds(4) : duration
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: visibleFor)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    public func hide() {
        panel?.orderOut(nil)
        state.message = nil
    }

    private func existingPanel(size: CGSize) -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: .statusBar
        )
        panel.host(ToastView(state: state))
        self.panel = panel
        return panel
    }
}

struct ToastView: View {
    @Bindable var state: ToastState

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: state.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(state.isError ? .orange : .green)
            Text(state.message ?? "")
                .font(TypeRamp.body)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .potretSurface(.hud, radius: Radius.md)
    }
}
