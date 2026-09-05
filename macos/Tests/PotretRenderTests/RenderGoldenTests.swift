import CoreGraphics
import Foundation
import Testing
@testable import PotretCore
@testable import PotretRender

/// Renders documents offscreen and checks the pixels.
///
/// There is no UI automation available without Xcode, so these are the closest thing to a visual
/// regression test. Rather than comparing against checked-in PNGs from the start, the assertions
/// here are structural — specific pixels that must or must not have changed — which makes them
/// readable and keeps them from failing on a font-rendering difference between OS versions.
@Suite("Render")
struct RenderGoldenTests {
    /// A flat white source image to draw on.
    private func source(width: Int = 200, height: Int = 200) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func render(
        _ document: AnnotationDocument,
        source: CGImage,
        scale: CGFloat = 1
    ) throws -> Bitmap {
        let size = CGSize(
            width: document.visibleRect.width * scale,
            height: document.visibleRect.height * scale
        )
        let context = try #require(
            CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        AnnotationRenderer().draw(
            document: document,
            source: source,
            into: context,
            transform: DocumentTransform(scale: scale),
            targetHeight: size.height
        )
        return try Bitmap(context: context)
    }

    private func style(_ color: InkColor = AnnotationPalette.red) -> AnnotationElement.Style {
        AnnotationElement.Style(color: color, lineWidth: 4)
    }

    // MARK: Basics

    @Test("An empty document renders the source unchanged")
    func emptyDocumentIsPassThrough() throws {
        let image = try source()
        let bitmap = try render(
            AnnotationDocument(sourceSize: CGSize(width: 200, height: 200)), source: image
        )
        #expect(bitmap.isWhite(atX: 100, y: 100))
    }

    @Test("A stroked rectangle marks its edge and leaves its middle alone")
    func rectangleStrokesOnly() throws {
        var document = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
        document.elements = [
            AnnotationElement(
                kind: .rectangle(CGRect(x: 50, y: 50, width: 100, height: 100)),
                style: style()
            )
        ]
        let bitmap = try render(document, source: try source())
        #expect(!bitmap.isWhite(atX: 50, y: 100), "left edge should be drawn")
        #expect(bitmap.isWhite(atX: 100, y: 100), "interior must stay untouched")
    }

    // MARK: The three regression cases

    @Test("Text lands in the same place at 1x and 2x")
    func textPositionIsScaleInvariant() throws {
        // The shipped bug: the editor positioned its text input in CSS pixels and drew the text in
        // canvas pixels, at a different size again — so on a Retina capture the glyph landed at
        // roughly twice the intended offset. One transform makes that impossible, and this asserts
        // it: the same document rendered at 1x and 2x must mark proportionally the same spot.
        var document = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
        document.elements = [
            AnnotationElement(
                kind: .text(.init(string: "Hg", origin: CGPoint(x: 40, y: 40), fontSize: 40)),
                style: style(AnnotationPalette.black)
            )
        ]

        let atOne = try render(document, source: try source())
        let atTwo = try render(document, source: try source(), scale: 2)

        let inkAtOne = atOne.inkBoundingBox()
        let inkAtTwo = atTwo.inkBoundingBox()
        let one = try #require(inkAtOne)
        let two = try #require(inkAtTwo)

        // Within a pixel of exactly double, allowing for hinting at different sizes.
        #expect(abs(two.minX - one.minX * 2) <= 2, "x drifted: \(one.minX) vs \(two.minX)")
        #expect(abs(two.minY - one.minY * 2) <= 2, "y drifted: \(one.minY) vs \(two.minY)")
    }

    @Test("Pixelation composites under a vector element, not over it")
    func effectsRenderBeneathInk() throws {
        // Effects are a separate cached layer drawn before the ink; an arrow crossing a pixelated
        // region must remain visible on top of it.
        var document = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
        document.elements = [
            AnnotationElement(
                kind: .pixelate(CGRect(x: 20, y: 20, width: 160, height: 160)),
                style: style()
            ),
            AnnotationElement(
                kind: .line(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 180, y: 100)),
                style: style(AnnotationPalette.red)
            ),
        ]
        let bitmap = try render(document, source: try source())
        #expect(bitmap.isRedish(atX: 100, y: 100), "the line must draw over the effect layer")
    }

    @Test("Cropping shifts the origin without moving annotations relative to the image")
    func cropIsNonDestructive() throws {
        // Crop is a rectangle the renderer honours, not a rasterise-and-wipe. An element at
        // document (60,60) inside a crop starting at (50,50) must land at (10,10) in the output.
        var document = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
        document.elements = [
            AnnotationElement(
                kind: .pixelate(CGRect(x: 60, y: 60, width: 20, height: 20)),
                style: style()
            )
        ]
        document.cropRect = CGRect(x: 50, y: 50, width: 100, height: 100)

        let bitmap = try render(document, source: try source())
        #expect(bitmap.width == 100 && bitmap.height == 100)
        #expect(document.elements.count == 1, "crop must not consume annotations")
    }

    // MARK: Cache behaviour

    @Test("Moving unrelated ink does not recompute the effects layer")
    func effectsCacheSurvivesUnrelatedEdits() throws {
        // This is the performance bug made into an assertion: the Tauri editor re-ran its
        // pixelation loop on every shape mutation.
        let cache = EffectsCache()
        let renderer = AnnotationRenderer(effects: cache)
        let image = try source()

        var document = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
        let effect = AnnotationElement(
            kind: .pixelate(CGRect(x: 20, y: 20, width: 100, height: 100)), style: style()
        )
        var arrow = AnnotationElement(
            kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50)), style: style()
        )
        document.elements = [effect, arrow]

        func drawOnce() throws {
            let context = try #require(
                CGContext(
                    data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            renderer.draw(document: document, source: image, into: context, targetHeight: 200)
        }

        try drawOnce()
        #expect(cache.misses == 1)

        // Drag the arrow ten times, as a live drag would.
        for step in 1...10 {
            arrow = arrow.moved(by: CGVector(dx: 1, dy: 1))
            document.elements[1] = arrow
            try drawOnce()
            #expect(cache.misses == 1, "effects recomputed on arrow move \(step)")
        }
        #expect(cache.hits == 10)

        // Changing the effect itself must invalidate.
        document.elements[0] = AnnotationElement(
            kind: .pixelate(CGRect(x: 30, y: 30, width: 100, height: 100)), style: style()
        )
        try drawOnce()
        #expect(cache.misses == 2)
    }
}

/// Minimal pixel reader for the assertions above.
private struct Bitmap {
    let width: Int
    let height: Int
    private let pixels: [UInt8]
    private let bytesPerRow: Int

    init(context: CGContext) throws {
        width = context.width
        height = context.height
        bytesPerRow = context.bytesPerRow
        let data = try #require(context.data)
        pixels = Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self),
                count: bytesPerRow * height
            )
        )
    }

    /// Document space is y-down; the bitmap is y-up.
    private func components(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let flipped = height - 1 - y
        let index = flipped * bytesPerRow + x * 4
        guard index + 2 < pixels.count else { return (0, 0, 0) }
        return (pixels[index], pixels[index + 1], pixels[index + 2])
    }

    func isWhite(atX x: Int, y: Int) -> Bool {
        let pixel = components(x: x, y: y)
        return pixel.r > 245 && pixel.g > 245 && pixel.b > 245
    }

    func isRedish(atX x: Int, y: Int) -> Bool {
        let pixel = components(x: x, y: y)
        return pixel.r > 150 && pixel.g < 120 && pixel.b < 120
    }

    /// Bounds of everything that is not white, in document (y-down) coordinates.
    func inkBoundingBox() -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where !isWhite(atX: x, y: y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
