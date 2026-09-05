import AppKit
import CoreGraphics

/// Where a panel goes.
///
/// Everything is placed relative to the screen **under the pointer**, not the primary display.
/// The Tauri app anchored several of its windows to the primary monitor, so on a two-display setup
/// a capture taken on the external screen popped up on the laptop.
public enum PanelPlacement {
    /// The screen containing the pointer, falling back to the main screen.
    @MainActor
    public static var activeScreen: NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// Bottom-left corner of a screen, inset far enough to clear the Dock.
    ///
    /// `visibleFrame` already excludes the Dock and menu bar, so this follows the Dock rather than
    /// hiding behind it — the old app used a fixed 80pt offset from the screen bottom, which sat
    /// underneath a large Dock.
    @MainActor
    public static func bottomLeading(
        size: CGSize,
        on screen: NSScreen? = nil,
        inset: CGFloat = Space.l
    ) -> NSRect {
        let area = (screen ?? activeScreen).visibleFrame
        return NSRect(
            x: area.minX + inset,
            y: area.minY + inset,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    public static func topTrailing(
        size: CGSize,
        on screen: NSScreen? = nil,
        inset: CGFloat = Space.l
    ) -> NSRect {
        let area = (screen ?? activeScreen).visibleFrame
        return NSRect(
            x: area.maxX - size.width - inset,
            y: area.maxY - size.height - inset,
            width: size.width,
            height: size.height
        )
    }
}
