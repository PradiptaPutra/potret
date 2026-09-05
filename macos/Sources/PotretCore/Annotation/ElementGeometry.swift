import CoreGraphics
import Foundation

extension AnnotationElement {
    /// Tight bounds in document coordinates, ignoring stroke width.
    public var boundingBox: CGRect {
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .pixelate(let rect), .blur(let rect):
            return rect
        case .line(let from, let to), .arrow(let from, let to):
            return CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            )
        case .freehand(let points), .highlight(let points):
            return Self.bounds(of: points)
        case .text(let content):
            // Without a text engine this is an estimate; the renderer measures for real. Good
            // enough for hit-testing and selection, which is all the model needs.
            let width = CGFloat(content.string.count) * content.fontSize * 0.6
            return CGRect(
                x: content.origin.x, y: content.origin.y,
                width: max(width, content.fontSize), height: content.fontSize * 1.3
            )
        case .step(let center, _):
            let radius = Self.stepRadius
            return CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )
        }
    }

    /// Radius of a numbered-step badge, in document points.
    public static let stepRadius: CGFloat = 14

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Hit-testing, per kind.
    ///
    /// Filled kinds test their area; stroked kinds test proximity to the stroke, so clicking the
    /// middle of an empty rectangle does not select it — which is what a user expects and what
    /// makes overlapping outlines usable.
    public func contains(_ point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        let slop = max(tolerance, style.lineWidth)
        switch kind {
        case .rectangle(let rect):
            return rect.insetBy(dx: -slop, dy: -slop).contains(point)
                && !rect.insetBy(dx: slop, dy: slop).contains(point)
        case .ellipse(let rect):
            return Self.isNearEllipse(point, in: rect, tolerance: slop)
        case .pixelate(let rect), .blur(let rect):
            return rect.contains(point) // effects are filled regions
        case .line(let from, let to), .arrow(let from, let to):
            return Self.distance(from: point, toSegment: from, to) <= slop
        case .freehand(let points), .highlight(let points):
            guard points.count > 1 else {
                return points.first.map { $0.distance(to: point) <= slop } ?? false
            }
            for index in 0..<(points.count - 1)
            where Self.distance(from: point, toSegment: points[index], points[index + 1]) <= slop {
                return true
            }
            return false
        case .text:
            return boundingBox.insetBy(dx: -slop / 2, dy: -slop / 2).contains(point)
        case .step(let center, _):
            return center.distance(to: point) <= Self.stepRadius + slop / 2
        }
    }

    /// Distance from a point to a line segment.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return point.distance(to: a) }
        // Project onto the segment, clamped to its ends.
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return point.distance(to: projection)
    }

    static func isNearEllipse(_ point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        let value = dx * dx + dy * dy
        // 1.0 is exactly on the outline; widen the band by the tolerance relative to the radius.
        let band = tolerance / max(rect.width, rect.height) * 4
        return abs(value - 1) <= band
    }

    /// Move by a delta, whatever the kind.
    public func moved(by delta: CGVector) -> AnnotationElement {
        var copy = self
        switch kind {
        case .rectangle(let rect): copy.kind = .rectangle(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .ellipse(let rect): copy.kind = .ellipse(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .pixelate(let rect): copy.kind = .pixelate(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .blur(let rect): copy.kind = .blur(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case .line(let from, let to):
            copy.kind = .line(from: from.offset(by: delta), to: to.offset(by: delta))
        case .arrow(let from, let to):
            copy.kind = .arrow(from: from.offset(by: delta), to: to.offset(by: delta))
        case .freehand(let points):
            copy.kind = .freehand(points.map { $0.offset(by: delta) })
        case .highlight(let points):
            copy.kind = .highlight(points.map { $0.offset(by: delta) })
        case .text(var content):
            content.origin = content.origin.offset(by: delta)
            copy.kind = .text(content)
        case .step(let center, let number):
            copy.kind = .step(center: center.offset(by: delta), number: number)
        }
        return copy
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func offset(by delta: CGVector) -> CGPoint {
        CGPoint(x: x + delta.dx, y: y + delta.dy)
    }
}
