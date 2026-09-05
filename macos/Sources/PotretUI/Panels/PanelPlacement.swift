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

    /// Force a frame to sit fully inside a screen's visible area.
    ///
    /// Anchoring maths can produce an off-screen origin whenever its inputs are not ready — a
    /// status-item button reports a zero-origin window frame until the menu bar has laid it out,
    /// which silently placed the history panel at y = -424 where it was invisible but "shown".
    /// A panel that is off-screen is always a bug, so this is a floor rather than a nicety.
    @MainActor
    public static func clamped(_ frame: NSRect, on screen: NSScreen? = nil) -> NSRect {
        let area = (screen ?? activeScreen).visibleFrame
        var result = frame
        result.origin.x = min(max(frame.minX, area.minX), max(area.minX, area.maxX - frame.width))
        result.origin.y = min(max(frame.minY, area.minY), max(area.minY, area.maxY - frame.height))
        return result
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
