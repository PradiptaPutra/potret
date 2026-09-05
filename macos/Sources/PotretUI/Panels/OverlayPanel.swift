import AppKit
import SwiftUI

/// Base class for every floating surface: the Quick Access popup, the selector, the history
/// panels, pinned captures.
///
/// This class is where the Tauri app's entire Spaces-and-focus bug class disappears. That app
/// carried `pin_to_all_spaces` (raw objc `msg_send` to set `collectionBehavior`, dispatched to the
/// main thread to avoid a SIGTRAP), `remember_front_app` and `restore_prev_front_app` (NSWorkspace
/// plus NSRunningApplication, to hand activation back to whatever app was frontmost), and a 40ms
/// sleep to let the show settle before undoing it. Seven consecutive releases, v0.2.16 through
/// v0.2.22, were attempts to fix the same symptom.
///
/// The cause was never Spaces. It was that showing a webview window activated the app, and macOS
/// follows the frontmost app across Space switches. Three properties, set once here, remove the
/// need for all of it:
///
///   * `.nonactivatingPanel` — the panel takes mouse and key events **without** the app becoming
///     frontmost. Nothing is stolen, so nothing has to be handed back.
///   * `.canJoinAllSpaces` — the panel is already on whatever Space you are on, so macOS never
///     needs to switch to reach it. Never `.moveToActiveSpace`, which only relocates on explicit
///     activation and is what produced the v0.2.17 regression.
///   * `.fullScreenAuxiliary` — it can float over another app's fullscreen window. The Tauri app
///     had no equivalent and was simply broken there.
public class OverlayPanel: NSPanel {
    private let acceptsKeyboard: Bool

    /// - Parameter level: `.statusBar` for popups, `.floating` for pinned windows,
    ///   `CGShieldingWindowLevel()` for the selector, which must cover the menu bar and Dock.
    public init(
        contentRect: NSRect,
        level: NSWindow.Level,
        acceptsKeyboard: Bool = false
    ) {
        self.acceptsKeyboard = acceptsKeyboard
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = level
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary, // don't animate along with a Space switch
            .ignoresCycle, // never a Cmd-` destination
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        // Overlays must survive another app becoming active — that is their normal state.
        hidesOnDeactivate = false
        // These panels are reused, not rebuilt; releasing on close would leave a dangling pointer.
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
    }

    /// Only the selector needs keys (Esc to cancel). Everything else stays unfocusable, so a
    /// capture never interrupts what the user was typing.
    public override var canBecomeKey: Bool { acceptsKeyboard }
    public override var canBecomeMain: Bool { false }

    /// Show without activating the app. `orderFrontRegardless` is the load-bearing call: plain
    /// `orderFront(_:)` is ignored while the app is inactive, which is precisely when a capture
    /// popup needs to appear.
    public func present() {
        orderFrontRegardless()
    }

    /// Install a SwiftUI view as the panel's content.
    public func host(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }
}
