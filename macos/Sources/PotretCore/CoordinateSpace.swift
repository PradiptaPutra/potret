import CoreGraphics

/// Conversions between the three coordinate systems a screenshot has to cross.
///
/// This is the most bug-prone geometry in the app, so it lives here as pure functions with no
/// AppKit and no ScreenCaptureKit — testable headless, against fixtures, with no display attached.
///
/// The three spaces:
///
///   * **Global (AppKit / NSScreen).** Origin at the bottom-left of the primary display, y
///     increasing **upward**. Secondary displays sit at whatever offset the user arranged, so a
///     display above the primary one has a **positive** y origin and one below has a negative one.
///   * **Display-local (ScreenCaptureKit).** Origin at the **top-left** of a single display, y
///     increasing **downward**. This is what `SCStreamConfiguration.sourceRect` wants.
///   * **Pixels.** Display-local points multiplied by the display's backing scale factor. A 2×
///     Retina display reports 1512×982 points but captures 3024×1964 pixels.
///
/// Getting the y-flip wrong is invisible on a single centred display and obvious the moment there
/// are two, which is exactly the kind of bug that ships.
public enum CoordinateSpace {
    /// Convert a rect in global AppKit coordinates into one display's local, top-left space.
    ///
    /// - Parameters:
    ///   - globalRect: the rect in global (bottom-left origin, y-up) coordinates.
    ///   - displayFrame: that display's frame, also in global coordinates.
    public static func displayLocal(
        globalRect: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: globalRect.minX - displayFrame.minX,
            // Flip: distance from the display's TOP edge down to the rect's TOP edge, which in a
            // y-up space is its maxY.
            y: displayFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// Inverse of `displayLocal(globalRect:displayFrame:)`.
    public static func global(
        displayLocalRect: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: displayLocalRect.minX + displayFrame.minX,
            y: displayFrame.maxY - displayLocalRect.maxY,
            width: displayLocalRect.width,
            height: displayLocalRect.height
        )
    }

    /// ScreenCaptureKit and CGWindowList report window frames in **CG global** space: origin at
    /// the top-left of the primary display, y increasing downward. AppKit hit-testing works in
    /// **AppKit global** space: origin bottom-left of the primary display, y increasing upward.
    ///
    /// Both are called "global coordinates" and both are in points, which makes them easy to
    /// confuse — and a window picker that confuses them highlights the wrong window everywhere
    /// except the vertical centre of the primary display.
    ///
    /// - Parameter primaryHeight: height of the primary display, the axis both spaces hinge on.
    public static func appKitGlobal(cgGlobalRect rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Inverse of `appKitGlobal(cgGlobalRect:primaryHeight:)` — the transform is its own inverse.
    public static func cgGlobal(appKitRect rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        appKitGlobal(cgGlobalRect: rect, primaryHeight: primaryHeight)
    }

    /// Points to backing pixels. Rounded outward so a selection never loses an edge row to
    /// rounding — capturing one pixel too many is invisible, one too few crops the content.
    public static func pixels(from rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX * scale).rounded(.down),
            y: (rect.minY * scale).rounded(.down),
            width: (rect.width * scale).rounded(.up),
            height: (rect.height * scale).rounded(.up)
        )
    }

    /// Normalise a drag into a positive-sized rect. A drag up-and-left produces negative width
    /// and height otherwise, which every downstream consumer would have to special-case.
    public static func normalized(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Which of the given display frames contains most of `globalRect`.
    ///
    /// A selection dragged across two displays has to resolve to one of them; picking the display
    /// holding the largest share is the least surprising answer.
    public static func dominantDisplay(
        for globalRect: CGRect,
        among displayFrames: [CGRect]
    ) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in displayFrames.enumerated() {
            let overlap = frame.intersection(globalRect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }
}
