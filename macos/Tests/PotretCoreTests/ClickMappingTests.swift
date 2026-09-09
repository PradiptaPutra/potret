import CoreGraphics
import Testing
@testable import PotretCore

@Suite("Click mapping")
struct ClickMappingTests {
    /// A 1000x800 display at the origin.
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("A click maps to frame pixels with the y axis flipped once")
    func mapsAndFlips() {
        // Top-left of the display in AppKit space is y = maxY, which is y = 0 in the frame.
        #expect(
            ClickMapping.framePoint(of: CGPoint(x: 0, y: 800), covering: display, scale: 1)
                == CGPoint(x: 0, y: 0)
        )
        // Bottom-left is the last row of the frame.
        #expect(
            ClickMapping.framePoint(of: CGPoint(x: 0, y: 0), covering: display, scale: 1)
                == CGPoint(x: 0, y: 800)
        )
        #expect(
            ClickMapping.framePoint(of: CGPoint(x: 250, y: 600), covering: display, scale: 2)
                == CGPoint(x: 500, y: 400)
        )
    }

    @Test("A click outside the recorded area has nowhere to go")
    func outsideIsRejected() {
        // The whole point: on a second display, or beside the region being recorded, there is no
        // pixel to mark and drawing one would put a ring where nobody clicked.
        #expect(ClickMapping.framePoint(of: CGPoint(x: -5, y: 400), covering: display, scale: 1) == nil)
        #expect(ClickMapping.framePoint(of: CGPoint(x: 500, y: 900), covering: display, scale: 1) == nil)
        #expect(ClickMapping.framePoint(of: CGPoint(x: 1200, y: 400), covering: display, scale: 1) == nil)
    }

    @Test("A region is measured from its own corner, not the display's")
    func regionIsRelative() {
        // A region recording crops at the source, so frame (0,0) is the region's top-left.
        let region = CGRect(x: 200, y: 100, width: 400, height: 300)
        #expect(
            ClickMapping.framePoint(of: CGPoint(x: 200, y: 400), covering: region, scale: 1)
                == CGPoint(x: 0, y: 0)
        )
        #expect(
            ClickMapping.framePoint(of: CGPoint(x: 400, y: 250), covering: region, scale: 2)
                == CGPoint(x: 400, y: 300)
        )
        // Inside the display but outside the region.
        #expect(ClickMapping.framePoint(of: CGPoint(x: 100, y: 400), covering: region, scale: 1) == nil)
    }

    @Test("A degenerate area is refused rather than dividing by nothing")
    func degenerateArea() {
        #expect(ClickMapping.framePoint(of: .zero, covering: .zero, scale: 1) == nil)
        #expect(ClickMapping.framePoint(of: .zero, covering: display, scale: 0) == nil)
    }

    @Test("A ripple runs once and then stops being drawn")
    func rippleLifetime() {
        #expect(ClickMapping.progress(start: 100, now: 100, duration: 0.5) == 0)
        #expect(ClickMapping.progress(start: 100, now: 100.25, duration: 0.5) == 0.5)
        // Finished, and never drawn again — otherwise a ring would sit in frame forever.
        #expect(ClickMapping.progress(start: 100, now: 100.5, duration: 0.5) == nil)
        #expect(ClickMapping.progress(start: 100, now: 200, duration: 0.5) == nil)
        // A frame whose timestamp precedes the click cannot show it.
        #expect(ClickMapping.progress(start: 100, now: 99, duration: 0.5) == nil)
    }

    @Test("A ripple expands and fades over its life")
    func rippleShape() {
        let start = ClickMapping.ripple(progress: 0, maximumRadius: 100)
        let middle = ClickMapping.ripple(progress: 0.5, maximumRadius: 100)
        let end = ClickMapping.ripple(progress: 0.99, maximumRadius: 100)

        #expect(start.radius < middle.radius)
        #expect(middle.radius < end.radius)
        #expect(end.radius <= 100)
        // Fully opaque at the click, effectively gone by the end.
        #expect(start.opacity == 1)
        #expect(start.opacity > middle.opacity)
        #expect(end.opacity < 0.05)
    }
}
