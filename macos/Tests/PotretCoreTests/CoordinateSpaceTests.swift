import CoreGraphics
import Testing
@testable import PotretCore

// Multi-display geometry is where this app is most likely to be silently wrong: every conversion
// below is an identity on a single centred 1x display, and only diverges once there is a second
// screen or a Retina scale factor. These fixtures are the arrangements that actually break things.
@Suite("Coordinate space")
struct CoordinateSpaceTests {
    // A 1512x982 @2x built-in display at the origin, with a 1920x1080 @1x display to its right.
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let toTheRight = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    // An external display placed ABOVE the built-in one: positive y origin in AppKit's y-up space.
    let above = CGRect(x: 0, y: 982, width: 1920, height: 1080)
    // ...and one placed below, which is where negative origins come from.
    let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)

    @Test("Top-left of a display maps to the local origin")
    func topLeftIsLocalOrigin() {
        // In a y-up space the top-left corner is (minX, maxY), and a 10x10 rect hanging off it
        // spans y 972...982.
        let rect = CGRect(x: 0, y: 972, width: 10, height: 10)
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: builtIn)
        #expect(local == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("Bottom-left of a display maps to the bottom of local space")
    func bottomLeftFlips() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: builtIn)
        #expect(local.minY == 972) // 982 height - 10 tall
    }

    @Test("A display to the right subtracts its x offset")
    func sideBySideOffset() {
        let rect = CGRect(x: 1612, y: 1000, width: 100, height: 80)
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: toTheRight)
        #expect(local.minX == 100)
        #expect(local.minY == 0) // 1080 top - 1080 rect maxY
    }

    @Test("A display above the primary one, positive origin")
    func displayAbove() {
        let rect = CGRect(x: 40, y: 1062, width: 200, height: 500)
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: above)
        #expect(local.minX == 40)
        // above.maxY is 2062; rect.maxY is 1562 → 500 down from the top.
        #expect(local.minY == 500)
    }

    @Test("A display below the primary one, negative origin")
    func displayBelow() {
        let rect = CGRect(x: 0, y: -80, width: 50, height: 50)
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: below)
        // below.maxY is 0; rect.maxY is -30 → 30 down from the top.
        #expect(local.minY == 30)
    }

    @Test("Global and display-local round-trip on every arrangement")
    func roundTrips() {
        let rect = CGRect(x: 120, y: 240, width: 300, height: 200)
        for frame in [builtIn, toTheRight, above, below] {
            let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: frame)
            let back = CoordinateSpace.global(displayLocalRect: local, displayFrame: frame)
            #expect(back == rect)
        }
    }

    @Test("Pixel conversion scales, and rounds outward so no edge is cropped")
    func pixelScaling() {
        let rect = CGRect(x: 10.4, y: 20.6, width: 100.2, height: 50.9)
        let onePlex = CoordinateSpace.pixels(from: rect, scale: 1)
        #expect(onePlex == CGRect(x: 10, y: 20, width: 101, height: 51))

        let twoPlex = CoordinateSpace.pixels(from: CGRect(x: 5, y: 5, width: 100, height: 50),
                                             scale: 2)
        #expect(twoPlex == CGRect(x: 10, y: 10, width: 200, height: 100))
    }

    @Test("A drag in any direction normalises to a positive rect")
    func dragNormalisation() {
        let downRight = CoordinateSpace.normalized(from: CGPoint(x: 10, y: 10),
                                                   to: CGPoint(x: 110, y: 60))
        let upLeft = CoordinateSpace.normalized(from: CGPoint(x: 110, y: 60),
                                                to: CGPoint(x: 10, y: 10))
        #expect(downRight == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(downRight == upLeft)
    }

    @Test("A selection spanning two displays resolves to the one holding most of it")
    func spanningSelectionPicksDominantDisplay() {
        // 300 wide starting 100pt left of the seam: 100pt on the built-in, 200pt on the right.
        let spanning = CGRect(x: 1412, y: 100, width: 300, height: 100)
        let index = CoordinateSpace.dominantDisplay(for: spanning, among: [builtIn, toTheRight])
        #expect(index == 1)
    }

    @Test("A selection touching no display resolves to nothing rather than guessing")
    func offscreenSelectionHasNoDisplay() {
        let offscreen = CGRect(x: 9000, y: 9000, width: 10, height: 10)
        #expect(CoordinateSpace.dominantDisplay(for: offscreen, among: [builtIn]) == nil)
    }
}
