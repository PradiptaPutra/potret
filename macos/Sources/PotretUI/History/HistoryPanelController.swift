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
    /// The status item that opened the panel, if one did. A click on it must be left to the
    /// toggle: if the outside-click monitor hid the panel first, the toggle would find it hidden
    /// and show it straight back, and the menu bar item could never close what it opened.
    private weak var anchorButton: NSStatusBarButton?
    private var dismissMonitors: [Any] = []
    private var spaceObserver: (any NSObjectProtocol)?

    public init(model: HistoryModel, actions: HistoryActions) {
        self.model = model
        self.actions = actions
    }

    /// Replace the action set. Actions that need the coordinator itself are attached after
    /// initialisation, so this arrives once rather than being threaded through init.
    public func updateActions(_ actions: HistoryActions) {
        var actions = actions
        // Every action that takes the user somewhere else — the editor, the clipboard, Finder —
        // ends the panel's job. It used to stay open on top of the very window it had opened,
        // and the only way to close it was to go back up to the menu bar.
        let annotate = actions.annotate
        actions.annotate = { [weak self] item in
            self?.hide()
            annotate?(item)
        }
        let copy = actions.copy
        actions.copy = { [weak self] item in
            self?.hide()
            copy?(item)
        }
        let reveal = actions.reveal
        actions.reveal = { [weak self] item in
            self?.hide()
            reveal?(item)
        }
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
        anchorButton = button
        let panel = existingPanel()
        panel.setContentSize(NSSize(width: 340, height: 420))
        let size = panel.frame.size
        panel.setFrameOrigin(origin(relativeTo: button, size: size))
        render()
        panel.present()
        installDismissMonitors()
        Log.ui.info(
            "history panel frame=\(NSStringFromRect(panel.frame), privacy: .public) visible=\(panel.isVisible) screens=\(NSScreen.screens.count)"
        )
    }

    public func hide() {
        removeDismissMonitors()
        panel?.orderOut(nil)
    }

    // MARK: Dismissal

    /// Click anywhere else, or change Space, and the panel goes — the way a menu does.
    ///
    /// The toggle was the only way to close it. The panel is non-activating, so clicking another
    /// app never dismissed it, and there was no timer; it simply stayed until the user went back
    /// to the menu bar item that opened it.
    private func installDismissMonitors() {
        guard dismissMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Clicks in any other app.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }) {
            dismissMonitors.append(monitor)
        }

        // Clicks in our own app, except on the panel, on a sheet or alert attached to it (the
        // Delete and Clear All confirmations), or on the status item — that one is the toggle's.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let window = event.window
                let onPanel = window === self.panel
                    || window?.parent === self.panel
                    || window?.sheetParent === self.panel
                let onAnchor = window != nil && window === self.anchorButton?.window
                if !onPanel, !onAnchor { self.hide() }
            }
            return event
        }) {
            dismissMonitors.append(monitor)
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeDismissMonitors() {
        dismissMonitors.forEach(NSEvent.removeMonitor)
        dismissMonitors.removeAll()
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
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
