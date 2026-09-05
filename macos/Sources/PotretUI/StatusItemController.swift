import AppKit
import PotretCore

/// The menu-bar item.
///
/// The menu triggers captures directly on the coordinator. The Tauri tray instead emitted an event
/// that the *frontend webview* had to receive and act on, which meant tray captures only worked
/// while the main window's webview was alive — a UI dependency in a path that should have none.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = TrayIcon.image()
        statusItem.button?.toolTip = "Potret"
        statusItem.menu = buildMenu()
        // The history panel anchors under the menu-bar item, so it opens where it was asked for.
        coordinator.statusButton = statusItem.button
    }

    /// Rebuilt on demand so the shortcut labels and any failure warning stay current.
    public func refresh() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        add(menu, "Capture Area", #selector(captureArea))
        add(menu, "Capture Window", #selector(captureWindow))
        add(menu, "Capture Screen", #selector(captureFullscreen))
        menu.addItem(.separator())
        add(menu, "Recent Captures", #selector(showHistory))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(showSettings))
        menu.addItem(.separator())

        // A dead hotkey is otherwise invisible until the user presses it and nothing happens.
        let failures = coordinator.shortcutFailures
        if !failures.isEmpty {
            let names = failures.keys.map(\.label).sorted().joined(separator: ", ")
            let warning = NSMenuItem(
                title: "⚠︎ Shortcut unavailable: \(names)",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(
            title: "Quit Potret",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        return menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func captureArea() {
        Log.ui.info("menu: Capture Area")
        coordinator.capture(.area)
    }

    @objc private func captureWindow() {
        Log.ui.info("menu: Capture Window")
        coordinator.capture(.window)
    }

    @objc private func captureFullscreen() {
        Log.ui.info("menu: Capture Screen")
        coordinator.capture(.fullscreen)
    }

    @objc private func showSettings() {
        Log.ui.info("menu: Settings")
        coordinator.showSettings()
    }

    @objc private func showHistory() {
        Log.ui.info("menu: Recent Captures")
        coordinator.toggleHistory()
    }
}
