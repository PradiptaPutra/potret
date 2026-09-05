import AppKit
import PotretCore
import SwiftUI

/// The app's only real window, and the only place `NSApp.activate()` is allowed.
///
/// Potret runs as an accessory: no Dock tile, no menu bar of its own, and every overlay is a
/// non-activating panel that never takes focus. A settings window is the one surface that genuinely
/// needs to be frontmost and accept typing, so it — and only it — flips the activation policy to
/// `.regular` while open and back to `.accessory` when it closes. That flip is what gives the
/// window a Dock tile and a menu bar for as long as it is up.
///
/// `scripts/lint-design.sh` fails the build on `NSApp.activate` in any other file. That rule is
/// what keeps the Spaces and focus-stealing bugs from creeping back: the moment some overlay
/// "just needs" to activate, the whole class of problem returns.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    public private(set) var window: NSWindow?
    /// Asked before the window closes from the close button or Cmd-W. Return false to keep it
    /// open — the editor uses this to offer Save / Don't Save when there are annotations.
    public var shouldClose: (() -> Bool)?
    private var closingWithoutPrompt = false
    /// How many controller-owned windows are on screen. The policy flips back to accessory only
    /// when the LAST one closes — closing the editor used to flip it while the home window was
    /// still open, and an accessory app hides its regular windows, so the home window vanished
    /// along with the editor.
    private static var visibleWindows = 0
    private var counted = false
    private let title: String
    private let defaultSize: NSSize
    private let resizable: Bool
    private let content: () -> AnyView

    /// - Parameters:
    ///   - defaultSize: initial content size. Settings is a fixed form; the editor needs room for
    ///     a full-resolution capture, and one hardcoded size cannot serve both — the editor was
    ///     opening at Settings' 460pt width, ignoring its own 720pt minimum.
    ///   - resizable: an editor must be; a settings form need not be.
    public init(
        title: String,
        defaultSize: NSSize = NSSize(width: 460, height: 560),
        resizable: Bool = false,
        content: @escaping () -> some View
    ) {
        self.title = title
        self.defaultSize = defaultSize
        self.resizable = resizable
        self.content = { AnyView(content()) }
        super.init()
    }

    public func show() {
        let window = existingWindow()
        // Regular for as long as a real window is open, so it can be Cmd-Tabbed to and typed in.
        NSApp.setActivationPolicy(.regular)
        if !counted {
            counted = true
            Self.visibleWindows += 1
        }
        window.center()
        // Two things conspired to put every window behind whatever the user was looking at.
        // The policy change from accessory to regular takes effect a runloop turn later, so an
        // activate() issued in the same turn applied to an app that was still an accessory. And
        // on macOS 14 plain activate() is cooperative — it will not bring an app forward unless
        // it is already the front app — which is precisely the state a menu-bar app is never in.
        // So: order the window front regardless, then on the next turn activate ignoring others.
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        Log.ui.info(
            "window '\(self.title, privacy: .public)' frame=\(NSStringFromRect(window.frame), privacy: .public) visible=\(window.isVisible)"
        )
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func close() {
        window?.close()
    }

    /// Close without consulting `shouldClose` — after a save, or when discarding on purpose.
    public func closeWithoutPrompt() {
        closingWithoutPrompt = true
        window?.close()
        closingWithoutPrompt = false
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingWithoutPrompt { return true }
        return shouldClose?() ?? true
    }

    private func existingWindow() -> NSWindow {
        if let window { return window }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.delegate = self
        // Present on whatever Space the user is on rather than dragging them to another one.
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        self.window = window
        return window
    }

    public func windowWillClose(_ notification: Notification) {
        if counted {
            counted = false
            Self.visibleWindows = max(0, Self.visibleWindows - 1)
        }
        // Back to an accessory only when the last real window goes away — otherwise the app
        // keeps a Dock tile and a menu bar it has no use for.
        if Self.visibleWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
