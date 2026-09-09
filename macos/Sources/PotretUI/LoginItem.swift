import AppKit
import Foundation
import PotretCore
import ServiceManagement

/// Launch at login, and cleanup of the mechanism it replaces.
///
/// `SMAppService` is the modern API: the app registers itself and appears under System Settings ›
/// General › Login Items, where the user can turn it off without opening Potret.
///
/// The Tauri build used `tauri-plugin-autostart`, which wrote a LaunchAgent plist at
/// ~/Library/LaunchAgents/Potret.plist pointing at the old bundle. Left alone after an upgrade,
/// that plist keeps launching a Potret that may no longer exist, and the user ends up with a login
/// item they cannot find in System Settings because it is not registered there.
public enum LoginItem {
    private static var legacyPlist: URL {
        URL.homeDirectory.appending(path: "Library/LaunchAgents/Potret.plist")
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Remove the Tauri-era LaunchAgent, carrying its setting over.
    ///
    /// Run once at startup. Returns true when a legacy agent was found and removed, so the caller
    /// can log it — a silent migration that goes wrong is very hard to diagnose later.
    @discardableResult
    public static func migrateLegacyLaunchAgent() -> Bool {
        let path = legacyPlist
        guard FileManager.default.fileExists(atPath: path.path) else { return false }

        // Unload it first; deleting the plist alone leaves the job registered until logout.
        let unload = Process()
        unload.executableURL = URL(filePath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())/Potret"]
        unload.standardError = FileHandle.nullDevice
        unload.standardOutput = FileHandle.nullDevice
        try? unload.run()
        unload.waitUntilExit()

        try? FileManager.default.removeItem(at: path)

        // The user had launch-at-login on, so preserve that intent through the new mechanism.
        try? setEnabled(true)
        return true
    }
}
