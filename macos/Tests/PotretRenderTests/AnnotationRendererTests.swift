import CoreGraphics
import Foundation
import Testing
@testable import PotretRender

@Suite("Annotation renderer")
struct AnnotationRendererTests {
    /// Proves the render target can be driven with no display attached — the property the whole
    /// golden-image strategy in Phase 3 depends on.
    @Test("Renders headlessly into a bitmap context")
    func rendersOffscreen() throws {
        let size = CGSize(width: 4, height: 4)
        let context = try #require(
            CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        AnnotationRenderer.drawPlaceholder(into: context, size: size)
        #expect(context.makeImage() != nil)
    }
}
