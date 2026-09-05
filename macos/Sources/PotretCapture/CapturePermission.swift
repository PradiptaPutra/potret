import CoreGraphics
import Foundation

/// Screen Recording permission.
///
/// `SCShareableContent` throws `userDeclined` rather than prompting, so the check has to happen
/// before any ScreenCaptureKit call — otherwise the first capture after a fresh install fails with
/// an opaque error instead of a permission dialog.
public enum CapturePermission: Sendable {
    /// Silent check. Does not prompt, so it is safe to call on every launch and on app activation.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt. macOS only shows it once per app identity — after the user has
    /// answered, this returns the stored answer and shows nothing, which is why the UI also needs
    /// a path to System Settings.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Deep link to the exact pane, so the user is not asked to go hunting.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
}
