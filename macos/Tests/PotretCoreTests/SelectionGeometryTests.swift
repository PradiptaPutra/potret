import CoreGraphics
import Testing
@testable import PotretCore

@Suite("SelectionGeometry")
struct SelectionGeometryTests {
    let rect = CGRect(x: 100, y: 100, width: 400, height: 200)
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("handles sit on the edges they move")
    func handlePoints() {
        #expect(SelectionGeometry.Handle.topLeft.point(in: rect) == CGPoint(x: 100, y: 300))
        #expect(SelectionGeometry.Handle.bottomRight.point(in: rect) == CGPoint(x: 500, y: 100))
        #expect(SelectionGeometry.Handle.top.point(in: rect) == CGPoint(x: 300, y: 300))
        #expect(SelectionGeometry.Handle.left.point(in: rect) == CGPoint(x: 100, y: 200))
    }

    @Test("hit-testing prefers a handle over the interior")
    func hitTest() {
        #expect(
            SelectionGeometry.hitTest(CGPoint(x: 103, y: 297), in: rect, tolerance: 6)
                == .handle(.topLeft)
        )
        #expect(SelectionGeometry.hitTest(CGPoint(x: 300, y: 200), in: rect, tolerance: 6) == .inside)
        #expect(SelectionGeometry.hitTest(CGPoint(x: 10, y: 10), in: rect, tolerance: 6) == .outside)
        // Just outside the tolerance of an edge handle, but inside the rect.
        #expect(SelectionGeometry.hitTest(CGPoint(x: 300, y: 290), in: rect, tolerance: 6) == .inside)
    }

    @Test("a corner drag keeps the opposite corner fixed")
    func resizeCorner() {
        let out = SelectionGeometry.resize(rect, handle: .topRight, to: CGPoint(x: 600, y: 400))
        #expect(out == CGRect(x: 100, y: 100, width: 500, height: 300))
    }

    @Test("an edge drag only moves that edge")
    func resizeEdge() {
        let out = SelectionGeometry.resize(rect, handle: .left, to: CGPoint(x: 50, y: 999))
        #expect(out == CGRect(x: 50, y: 100, width: 450, height: 200))
    }

    @Test("dragging past the opposite edge stops at the minimum rather than flipping")
    func resizeNeverInverts() {
        let out = SelectionGeometry.resize(
            rect, handle: .right, to: CGPoint(x: 0, y: 0), minimum: 10
        )
        #expect(out.minX == 100)
        #expect(out.width == 10)
    }

    @Test("a locked aspect is honoured from a corner")
    func resizeCornerLocked() {
        let out = SelectionGeometry.resize(
            rect, handle: .bottomRight, to: CGPoint(x: 900, y: 0), aspect: 2
        )
        #expect(out.minX == 100)
        #expect(out.maxY == 300)
        #expect(abs(out.width / out.height - 2) < 0.0001)
        #expect(out.width == 800)
    }

    @Test("a locked aspect from an edge grows the other dimension about the centre")
    func resizeEdgeLocked() {
        let out = SelectionGeometry.resize(
            rect, handle: .right, to: CGPoint(x: 700, y: 0), aspect: 2
        )
        #expect(out.width == 600)
        #expect(out.height == 300)
        #expect(out.midY == rect.midY)
    }

    @Test("moving is clamped to the bounds")
    func move() {
        let out = SelectionGeometry.move(rect, by: CGPoint(x: 5000, y: -5000), within: bounds)
        #expect(out == CGRect(x: 600, y: 0, width: 400, height: 200))
        let free = SelectionGeometry.move(rect, by: CGPoint(x: 10, y: 10), within: bounds)
        #expect(free.origin == CGPoint(x: 110, y: 110))
    }

    @Test("an exact size anchors at the top-left corner")
    func resized() {
        let out = SelectionGeometry.resized(
            rect, toSize: CGSize(width: 200, height: 100), within: bounds
        )
        #expect(out.minX == 100)
        #expect(out.maxY == 300)
        #expect(out.size == CGSize(width: 200, height: 100))
    }

    @Test("an exact size larger than the screen is clamped to it")
    func resizedClamped() {
        let out = SelectionGeometry.resized(
            rect, toSize: CGSize(width: 5000, height: 5000), within: bounds
        )
        #expect(out == bounds)
    }

    @Test("the bar sits below, flips above when there is no room, then tucks inside")
    func barPlacement() {
        let size = CGSize(width: 300, height: 40)
        let below = SelectionGeometry.barFrame(size: size, below: rect, within: bounds, gap: 12)
        #expect(below.maxY == rect.minY - 12)
        #expect(below.midX == rect.midX)

        let low = CGRect(x: 100, y: 10, width: 400, height: 200)
        let above = SelectionGeometry.barFrame(size: size, below: low, within: bounds, gap: 12)
        #expect(above.minY == low.maxY + 12)

        let tall = CGRect(x: 100, y: 10, width: 400, height: 780)
        let inside = SelectionGeometry.barFrame(size: size, below: tall, within: bounds, gap: 12)
        #expect(inside.minY == tall.minY + 12)
    }

    @Test("the bar never leaves the screen horizontally")
    func barClampedHorizontally() {
        let size = CGSize(width: 300, height: 40)
        let edge = CGRect(x: 950, y: 300, width: 40, height: 40)
        let frame = SelectionGeometry.barFrame(size: size, below: edge, within: bounds, gap: 12)
        #expect(frame.maxX == bounds.maxX - 12)
    }

    @Test("common aspect ratios are named, odd ones are not")
    func aspectNames() {
        #expect(SelectionGeometry.namedAspect(of: CGSize(width: 1920, height: 1080)) == "16:9")
        #expect(SelectionGeometry.namedAspect(of: CGSize(width: 500, height: 500)) == "1:1")
        #expect(SelectionGeometry.namedAspect(of: CGSize(width: 1000, height: 700)) == nil)
    }
}
