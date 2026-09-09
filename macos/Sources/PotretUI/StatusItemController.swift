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

        if coordinator.isRecording {
            // While recording, that is the only thing the menu should be about.
            let stop = item(
                "Stop Recording",
                symbol: "stop.circle.fill",
                action: #selector(stopRecording)
            )
            stop.attributedTitle = NSAttributedString(
                string: "Stop Recording",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(stop)
            menu.addItem(.separator())
        }

        menu.addItem(header("Capture"))
        menu.addItem(item("Area", symbol: "viewfinder", action: #selector(captureArea),
                          shortcut: shortcuts[.captureArea]))
        menu.addItem(item("Window", symbol: "macwindow", action: #selector(captureWindow),
                          shortcut: shortcuts[.captureWindow]))
        menu.addItem(item("Screen", symbol: "display", action: #selector(captureFullscreen),
                          shortcut: shortcuts[.captureFullscreen]))

        if !coordinator.isRecording {
            menu.addItem(.separator())
            menu.addItem(header("Record"))
            menu.addItem(item("Area", symbol: "record.circle", action: #selector(recordArea)))
            menu.addItem(item("Window", symbol: "macwindow.on.rectangle",
                              action: #selector(recordWindow)))
            menu.addItem(item("Screen", symbol: "rectangle.dashed.badge.record",
                              action: #selector(recordFullscreen)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Recent Captures", symbol: "clock.arrow.circlepath",
                          action: #selector(showHistory), shortcut: shortcuts[.recentCaptures]))
        menu.addItem(item("Open Potret", symbol: "square.grid.2x2", action: #selector(showHome)))
        menu.addItem(item("Settings…", symbol: "gearshape", action: #selector(showSettings)))

        // A dead hotkey is otherwise invisible until you press it and nothing happens.
        let failures = coordinator.shortcutFailures
        if !failures.isEmpty {
            menu.addItem(.separator())
            let names = failures.keys.map(\.label).sorted().joined(separator: ", ")
            let warning = item("Shortcut unavailable: \(names)",
                               symbol: "exclamationmark.triangle.fill", action: nil)
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Potret", symbol: "power",
                          action: #selector(NSApplication.terminate(_:)), target: nil))
        return menu
    }

    /// A small caps section label. NSMenu has no section header of its own, so this is a disabled
    /// item styled to read as one — the same shape System Settings and Finder use.
    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: TypeRamp.AppKit.menuSectionHeader,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        return item
    }

    /// One row: SF Symbol, title, and the real shortcut on the right.
    ///
    /// The shortcut is shown as a plain right-aligned string rather than as a keyEquivalent,
    /// because these are *global* hotkeys registered with Carbon — attaching them as menu
    /// equivalents would register a second, conflicting binding that only works while the menu is
    /// open.
    private func item(
        _ title: String,
        symbol: String,
        action: Selector?,
        shortcut: String? = nil,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target ?? self
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))

        if let shortcut {
            let attributed = NSMutableAttributedString(string: title)
            attributed.append(
                NSAttributedString(
                    string: "   \(shortcut)",
                    attributes: [
                        .font: TypeRamp.AppKit.menuShortcut,
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
            )
            item.attributedTitle = attributed
        }
        return item
    }

    /// Current shortcut glyphs, refreshed with the menu.
    private var shortcuts: [ShortcutID: String] {
        coordinator.shortcutLabels
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
