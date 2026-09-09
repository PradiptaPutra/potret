import AppKit
import Observation
import PotretCore
import SwiftUI

/// The self-timer: a big number in the middle of the screen counting down to the capture.
///
/// A non-activating panel like every other overlay, so the countdown never takes focus from
/// the thing being captured — the whole point of a timer is to get a menu or hover state into
/// the shot, and activating would dismiss it.
@MainActor
public final class CountdownController {
    private var panel: OverlayPanel?
    private let state = CountdownState()

    public init() {}

    /// Show `seconds`, `seconds - 1`, … `1`, one per second, then return.
    public func run(seconds: Int, centredOn frame: CGRect) async {
        guard seconds > 0 else { return }
        let size = CGSize(width: 140, height: 140)
        let panel = existingPanel(size: size)
        panel.setFrame(
            NSRect(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        Log.ui.info("countdown: \(seconds)s")
        state.remaining = seconds
        panel.present()
        for remaining in stride(from: seconds, through: 1, by: -1) {
            state.remaining = remaining
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
    }

    private func existingPanel(size: CGSize) -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: .statusBar
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.host(CountdownView(state: state))
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
final class CountdownState {
    var remaining = 0
}

struct CountdownView: View {
    @Bindable var state: CountdownState

    var body: some View {
        Text("\(state.remaining)")
            .font(TypeRamp.countdown)
            .foregroundStyle(.white)
            .contentTransition(.numericText(countsDown: true))
            .animation(Motion.standard, value: state.remaining)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .potretSurface(.hud, radius: Radius.lg)
    }
}
