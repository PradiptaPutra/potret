import CoreGraphics

/// Geometry for an adjustable area selection: handles, hit-testing, constrained resizing, and
/// where the options bar goes. Pure functions so the interaction can be tested without a view.
///
/// All rects are in the selector view's own space: bottom-left origin, y up, points.
public enum SelectionGeometry {
    /// One of the eight resize handles, named by the edge(s) it moves.
    public enum Handle: CaseIterable, Sendable, Equatable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        public var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
        public var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
        public var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
        public var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
        public var isCorner: Bool { movesLeft != movesRight && movesTop != movesBottom }

        /// Where this handle sits on a rect.
        public func point(in rect: CGRect) -> CGPoint {
            let x = movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX
            let y = movesTop ? rect.maxY : movesBottom ? rect.minY : rect.midY
            return CGPoint(x: x, y: y)
        }
    }

    public enum Hit: Equatable, Sendable {
        case handle(Handle)
        case inside
        case outside
    }

    /// What a point over a finished selection is on. Handles win over the interior so a
    /// selection can still be resized from its edge.
    public static func hitTest(
        _ point: CGPoint,
        in rect: CGRect,
        tolerance: CGFloat
    ) -> Hit {
        for handle in Handle.allCases {
            let at = handle.point(in: rect)
            if abs(point.x - at.x) <= tolerance, abs(point.y - at.y) <= tolerance {
                return .handle(handle)
            }
        }
        return rect.contains(point) ? .inside : .outside
    }

    /// Move one handle to `point`, keeping the opposite edge(s) fixed.
    ///
    /// With `aspect` (width ÷ height) set, corners keep the ratio by deriving the height from
    /// the dragged width, and edges keep it by adjusting the perpendicular dimension around the
    /// rect's centre — the way every Mac image editor behaves. The result is never smaller
    /// than `minimum` on either side and never inverted: dragging past the opposite edge stops
    /// there rather than flipping the rect, which would swap which handle the user holds.
    public static func resize(
        _ rect: CGRect,
        handle: Handle,
        to point: CGPoint,
        aspect: CGFloat? = nil,
        minimum: CGFloat = 1
    ) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        if handle.movesLeft { minX = min(point.x, maxX - minimum) }
        if handle.movesRight { maxX = max(point.x, minX + minimum) }
        if handle.movesBottom { minY = min(point.y, maxY - minimum) }
        if handle.movesTop { maxY = max(point.y, minY + minimum) }

        guard let aspect, aspect > 0 else {
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        if handle.isCorner {
            let width = max(maxX - minX, minimum)
            let height = max(width / aspect, minimum)
            let finalWidth = height * aspect
            if handle.movesLeft { minX = maxX - finalWidth } else { maxX = minX + finalWidth }
            if handle.movesBottom { minY = maxY - height } else { maxY = minY + height }
        } else if handle.movesLeft || handle.movesRight {
            let width = maxX - minX
            let height = width / aspect
            let midY = rect.midY
            minY = midY - height / 2
            maxY = midY + height / 2
        } else {
            let height = maxY - minY
            let width = height * aspect
            let midX = rect.midX
            minX = midX - width / 2
            maxX = midX + width / 2
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Translate, keeping the whole rect inside `bounds`.
    public static func move(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.x, dy: delta.y)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// Give the rect an exact size, anchored at its top-left corner — the corner the user
    /// started the drag from in the common case, and the one a size readout is placed by.
    /// Clamped so the rect stays inside `bounds`; a typed size larger than the screen shrinks.
    public static func resized(
        _ rect: CGRect,
        toSize size: CGSize,
        within bounds: CGRect,
        minimum: CGFloat = 1
    ) -> CGRect {
        let width = min(max(size.width, minimum), bounds.width)
        let height = min(max(size.height, minimum), bounds.height)
        var result = CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - height)
        return result
    }

    /// Where the options bar sits relative to the selection.
    ///
    /// Centred below the selection, one gap down. If that would fall off the bottom of the
    /// screen it goes above instead, and if there is no room above either — a selection
    /// spanning the whole height — it tucks inside along the bottom edge. Clamped horizontally
    /// so a selection at the screen's edge does not push half the bar off-screen.
    public static func barFrame(
        size: CGSize,
        below selection: CGRect,
        within bounds: CGRect,
        gap: CGFloat
    ) -> CGRect {
        var y = selection.minY - gap - size.height
        if y < bounds.minY {
            y = selection.maxY + gap
            if y + size.height > bounds.maxY {
                y = selection.minY + gap
            }
        }
        var x = selection.midX - size.width / 2
        x = min(max(x, bounds.minX + gap), max(bounds.minX + gap, bounds.maxX - gap - size.width))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The nearest simple ratio for a size, for the readout ("16:9"), or nil when nothing
    /// common is within tolerance.
    public static func namedAspect(of size: CGSize, tolerance: CGFloat = 0.01) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = size.width / size.height
        let candidates: [(String, CGFloat)] = [
            ("1:1", 1), ("4:3", 4 / 3), ("3:2", 3 / 2), ("16:10", 16 / 10), ("16:9", 16 / 9),
            ("21:9", 21 / 9), ("3:4", 3 / 4), ("2:3", 2 / 3), ("9:16", 9 / 16),
        ]
        return candidates.first { abs($0.1 - ratio) / $0.1 <= tolerance }?.0
    }
}
