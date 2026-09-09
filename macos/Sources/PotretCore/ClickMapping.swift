import CoreGraphics

/// Where a click on screen lands inside a recorded frame.
///
/// A recording covers some rectangle of the screen — a whole display, a chosen region, or one
/// window — and produces pixels with a top-left origin. Screen positions arrive from AppKit in
/// global coordinates with a bottom-left origin. Putting a ring under the pointer means crossing
/// both differences at once, which is the same flip that is invisible on a single display and
/// wrong on every other arrangement.
///
/// Pure functions, so the arithmetic is testable without a display, a stream or a click.
public enum ClickMapping {
    /// Convert a point in global AppKit coordinates to pixel coordinates inside a frame.
    ///
    /// - Parameters:
    ///   - point: the click, in global AppKit space (bottom-left origin, y up, points).
    ///   - rect: the screen rectangle the frame covers, in the same space.
    ///   - scale: backing scale of the display the frame came from.
    /// - Returns: the position in frame pixels (top-left origin, y down), or nil when the click
    ///   was outside the recorded area and has nothing to mark.
    public static func framePoint(
        of point: CGPoint,
        covering rect: CGRect,
        scale: CGFloat
    ) -> CGPoint? {
        guard rect.width > 0, rect.height > 0, scale > 0 else { return nil }
        // Inclusive of the far edges, unlike CGRect.contains. A click on the top row of a
        // display sits exactly on maxY, and contains() would reject it — dropping the ring for
        // every click on a menu bar or a window's title bar, which is most of them in a demo.
        guard
            point.x >= rect.minX, point.x <= rect.maxX,
            point.y >= rect.minY, point.y <= rect.maxY
        else { return nil }
        return CGPoint(
            x: (point.x - rect.minX) * scale,
            // Flip: distance down from the rect's TOP edge, which in a y-up space is its maxY.
            y: (rect.maxY - point.y) * scale
        )
    }

    /// How far through its animation a ripple started at `start` is by `now`, from 0 to 1, or
    /// nil once it is over and should stop being drawn.
    public static func progress(
        start: Double,
        now: Double,
        duration: Double
    ) -> Double? {
        guard duration > 0 else { return nil }
        let elapsed = now - start
        guard elapsed >= 0, elapsed < duration else { return nil }
        return elapsed / duration
    }

    /// Radius and opacity for a ripple at `progress`.
    ///
    /// The ring expands and fades at once — the shape a viewer reads as "a click happened here"
    /// rather than "something is highlighted here". Opacity falls off faster than linearly, so
    /// the ring is unmistakable at the moment of the click and gone before it can be confused
    /// with the next one.
    public static func ripple(
        progress: Double,
        maximumRadius: CGFloat
    ) -> (radius: CGFloat, opacity: Double) {
        let eased = 1 - pow(1 - progress, 3)
        return (
            radius: maximumRadius * (0.25 + 0.75 * eased),
            opacity: pow(1 - progress, 1.6)
        )
    }
}
