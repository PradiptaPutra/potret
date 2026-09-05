import AppKit
import PotretCore

/// Menu-bar-only app.
///
/// It runs as an accessory (`LSUIElement`), so it owns no Dock tile and no menu bar of its own.
/// Every overlay is a non-activating `NSPanel` — see `OverlayPanel` — which is why showing one
/// never steals focus and why none of the Tauri app's Spaces workarounds are ported.
/// `NSApp.activate()` belongs in exactly one place, the controller that presents the main window,
/// and `scripts/lint-design.sh` enforces that.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItem: StatusItemController?

    /// Development builds run under com.potret.app.dev so they cannot disturb the released app's
    /// settings, history or Screen Recording grant.
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? AppIdentity.developmentBundleID
    }

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(bundleID: bundleID)
        self.coordinator = coordinator
        statusItem = StatusItemController(coordinator: coordinator)

        Task { [weak self] in
            await coordinator.start()
            self?.statusItem?.refresh() // surface any shortcut that failed to register
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Hotkeys are a process-global resource and settings may have an unflushed edit.
        coordinator?.shutdown()
    }

    /// Closing a window is not a reason to quit a menu-bar app.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
