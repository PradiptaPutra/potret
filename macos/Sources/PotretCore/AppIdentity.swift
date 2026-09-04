import Foundation

/// Identity constants that must stay in lockstep with the bundle we ship.
///
/// The bundle identifier is load-bearing: macOS keys the Screen Recording TCC grant on
/// (bundle id, code-signing identity). Keeping `com.potret.app` — and signing with the same
/// `Potret Self-Signed` certificate as the Tauri build — is what lets an existing user upgrade
/// to the native app without being asked for the permission again.
public enum AppIdentity: Sendable {
    /// Shipping bundle identifier. Development builds append `.dev` so they can coexist with,
    /// and never disturb, the released app's permission grant.
    public static let releaseBundleID = "com.potret.app"
    public static let developmentBundleID = "com.potret.app.dev"

    /// Directory the Tauri app already uses, and which the native app reads so existing
    /// history and settings survive the rewrite.
    public static func applicationSupportDirectory(
        bundleID: String = releaseBundleID
    ) -> URL {
        URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
    }

    public static func historyDirectory(bundleID: String = releaseBundleID) -> URL {
        applicationSupportDirectory(bundleID: bundleID)
            .appending(path: "history", directoryHint: .isDirectory)
    }

    public static func configFile(bundleID: String = releaseBundleID) -> URL {
        applicationSupportDirectory(bundleID: bundleID).appending(path: "config.json")
    }
}
