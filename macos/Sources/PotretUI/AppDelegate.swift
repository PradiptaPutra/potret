import AppKit
import PotretCore

/// Phase 0 shell: a menu-bar-only app with a status item and a working Quit.
///
/// The app runs as an accessory (`LSUIElement`), so it owns no Dock tile and no menu bar of its
/// own. Every overlay it will grow — selector, capture popup, history, pinned windows — is a
/// non-activating `NSPanel`, which is why showing one never steals focus and there is nothing to
/// hand back afterwards. `NSApp.activate()` is confined to the one controller that presents the
/// main window; nothing else in the app may call it.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = TrayIcon.image()
        item.button?.toolTip = "Potret"
        item.menu = makeMenu()
        statusItem = item
    }

    /// Menu-bar app: closing a window is not a reason to quit.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        let title = "Potret \(version as? String ?? "dev")"
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }
}
