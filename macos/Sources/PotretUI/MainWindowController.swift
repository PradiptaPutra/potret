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
    private var window: NSWindow?
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.center()
        Log.ui.info(
            "window '\(self.title, privacy: .public)' frame=\(NSStringFromRect(window.frame), privacy: .public) visible=\(window.isVisible)"
        )
    }

    public func close() {
        window?.close()
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
        // Back to an accessory the moment the last real window goes away, or the app keeps a Dock
        // tile and a menu bar it has no use for.
        NSApp.setActivationPolicy(.accessory)
    }
}
