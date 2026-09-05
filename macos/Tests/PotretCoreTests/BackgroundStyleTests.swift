import CoreGraphics
import Foundation
import Testing
@testable import PotretCore

@Suite("Background style")
struct BackdropTests {
    @Test("Padding is proportional, so it looks the same on any capture size")
    func paddingScalesWithTheImage() {
        // The Tauri tool used absolute pixels: 60px around a 3400px Retina screenshot is a
        // hairline, while 60px around a 400px crop swallows it.
        let style = Backdrop(paddingFraction: 0.1)
        #expect(style.padding(for: CGSize(width: 1000, height: 500)) == 50)
        #expect(style.padding(for: CGSize(width: 4000, height: 2000)) == 200)
        // Always the shorter edge, so a very wide capture is not swamped.
        #expect(style.padding(for: CGSize(width: 4000, height: 200)) == 20)
    }

    @Test("Output size is the capture plus padding on every side")
    func outputSize() {
        let style = Backdrop(paddingFraction: 0.1)
        let output = style.outputSize(for: CGSize(width: 1000, height: 500))
        #expect(output == CGSize(width: 1100, height: 600))

        let rect = style.imageRect(for: CGSize(width: 1000, height: 500))
        #expect(rect == CGRect(x: 50, y: 50, width: 1000, height: 500))
    }

    @Test("Aspect-fill covers the target and centres the overflow")
    func aspectFillCentres() {
        // A wide photo behind a square backdrop: it must cover fully, and the overflow must be
        // split evenly rather than the image being stretched — which is what the old tool did to
        // every custom background.
        let rect = Backdrop.aspectFill(
            source: CGSize(width: 400, height: 100),
            in: CGSize(width: 200, height: 200)
        )
        #expect(rect.height == 200)
        #expect(rect.width == 800)
        #expect(rect.minX == -300) // (200 - 800) / 2
        #expect(rect.minY == 0)
        // Covers the whole target.
        #expect(rect.contains(CGRect(x: 0, y: 0, width: 200, height: 200)))
    }

    @Test("A degenerate source does not divide by zero")
    func aspectFillDegenerate() {
        let rect = Backdrop.aspectFill(source: .zero, in: CGSize(width: 10, height: 10))
        #expect(rect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("A document without a backdrop outputs at its visible size")
    func documentOutputSize() {
        var document = AnnotationDocument(sourceSize: CGSize(width: 800, height: 600))
        #expect(document.outputSize == CGSize(width: 800, height: 600))

        document.background = Backdrop(paddingFraction: 0.1)
        #expect(document.outputSize == CGSize(width: 920, height: 720))

        // Cropping first means the backdrop is sized to the crop, not the original.
        document.cropRect = CGRect(x: 0, y: 0, width: 400, height: 200)
        #expect(document.outputSize == CGSize(width: 440, height: 240))
    }

    @Test("Setting a backdrop is undoable")
    func backgroundIsUndoable() {
        var document = AnnotationDocument(sourceSize: CGSize(width: 100, height: 100))
        let edit = DocumentEdit.setBackground(old: nil, new: Backdrop())
        edit.apply(to: &document)
        #expect(document.background != nil)
        edit.inverse.apply(to: &document)
        #expect(document.background == nil)
    }

    @Test("Every gradient preset has at least two stops and a direction")
    func presetsAreWellFormed() {
        for preset in GradientPreset.allCases {
            #expect(preset.stops.count >= 2, "\(preset.name) needs at least two stops")
            #expect(!preset.name.isEmpty)
            let direction = preset.direction
            #expect(direction.start != direction.end)
        }
    }
}
