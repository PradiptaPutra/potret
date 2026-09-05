import AppKit
import PotretCore
import SwiftUI

/// The menu-bar "Recent Captures" panel.
///
/// Anchored under the status item rather than at a fixed screen position, so it appears where the
/// user clicked — including on a second display. The Tauri version placed it a fixed distance from
/// the top-right of a monitor, which put it nowhere near the menu bar item that opened it.
@MainActor
public final class HistoryPanelController {
    private var panel: OverlayPanel?
    private let model: HistoryModel
    private var actions: HistoryActions
    private var captureHint: String?

    public init(model: HistoryModel, actions: HistoryActions) {
        self.model = model
        self.actions = actions
    }

    public func setCaptureHint(_ hint: String?) {
        captureHint = hint
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    /// Toggle, anchored to a status-item button when one is given.
    public func toggle(relativeTo button: NSStatusBarButton?) {
        if isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    public func show(relativeTo button: NSStatusBarButton?) {
        model.load()
        let panel = existingPanel()
        panel.setContentSize(NSSize(width: 340, height: 420))
        let size = panel.frame.size
        panel.setFrameOrigin(origin(relativeTo: button, size: size))
        render()
        panel.present()
        Log.ui.info(
            "history panel frame=\(NSStringFromRect(panel.frame), privacy: .public) visible=\(panel.isVisible) screens=\(NSScreen.screens.count)"
        )
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    // MARK: Internals

    private func origin(relativeTo button: NSStatusBarButton?, size: CGSize) -> NSPoint {
        // The status item's window reports a zero frame until the menu bar has laid it out, which
        // yields an anchor near the origin and a panel placed off the bottom of the screen. Treat
        // an anchor that is not actually up in the menu bar as unusable.
        let anchor: NSRect? = button.flatMap { button in
            guard let window = button.window else { return nil }
            let onScreen = window.convertToScreen(button.bounds)
            let menuBarTop = (NSScreen.screens.first { $0.frame.contains(onScreen.origin) }
                ?? PanelPlacement.activeScreen).frame.maxY
            return onScreen.maxY > menuBarTop - 40 ? onScreen : nil
        }

        guard let anchor else {
            return PanelPlacement.topTrailing(size: size).origin
        }

        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) }
            ?? PanelPlacement.activeScreen
        // Centred under the item, then clamped so a status item near an edge cannot push half the
        // panel off the display.
        let proposed = NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - Space.xs,
            width: size.width,
            height: size.height
        )
        return PanelPlacement.clamped(proposed, on: screen).origin
    }

    private func existingPanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            // .popUpMenu so it sits above ordinary windows and other panels, like a real menu.
            level: .popUpMenu
        )
        self.panel = panel
        return panel
    }

    private func render() {
        existingPanel().host(
            HistoryPanelView(model: model, actions: actions, captureHint: captureHint)
        )
    }
}
