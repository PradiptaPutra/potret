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
        coordinator.onRecordingStateChanged = { [weak self] in self?.refresh() }
    }

    /// Rebuilt on demand so the shortcut labels and any failure warning stay current.
    public func refresh() {
        statusItem.menu = buildMenu()
        // Tint the menu-bar glyph red while recording. A template image cannot carry colour, so
        // this switches it off for the duration.
        if let button = statusItem.button {
            button.image?.isTemplate = !coordinator.isRecording
            button.contentTintColor = coordinator.isRecording ? .systemRed : nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        add(menu, "Capture Area", #selector(captureArea))
        add(menu, "Capture Window", #selector(captureWindow))
        add(menu, "Capture Screen", #selector(captureFullscreen))
        menu.addItem(.separator())

        // While recording, the menu bar is one of the three ways to stop — and the one that is
        // always reachable even if the HUD is behind something or on another Space.
        if coordinator.isRecording {
            let stop = NSMenuItem(
                title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""
            )
            stop.target = self
            menu.addItem(stop)
        } else {
            add(menu, "Record Area", #selector(recordArea))
            add(menu, "Record Window", #selector(recordWindow))
            add(menu, "Record Screen", #selector(recordFullscreen))
        }
        menu.addItem(.separator())
        add(menu, "Open Potret", #selector(showHome))
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

    @objc private func recordArea() { coordinator.record(.area) }
    @objc private func recordWindow() { coordinator.record(.window) }
    @objc private func recordFullscreen() { coordinator.record(.fullscreen) }

    @objc private func stopRecording() {
        Log.ui.info("menu: Stop Recording")
        coordinator.stopRecording()
        refresh()
    }

    @objc private func showHome() {
        Log.ui.info("menu: Open Potret")
        coordinator.showHome()
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
