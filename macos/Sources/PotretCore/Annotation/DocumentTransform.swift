import CoreGraphics
import Foundation

/// The one place a coordinate crosses between document space and anything else.
///
/// Document space is the source image's pixel grid. View space is what is on screen at the current
/// zoom and scroll. Export space is the output image.
///
/// This type exists because its absence is a specific, shipped bug: the Tauri editor positioned
/// its text input in CSS pixels and then drew the text with `fillText` in canvas pixels, and
/// separately sized the input at 12px while rendering at 30px. On a Retina capture the committed
/// text landed at roughly twice the intended offset, at two and a half times the intended size.
/// With one transform used by the view, the text editor and the exporter, that cannot recur.
public struct DocumentTransform: Equatable, Sendable {
    /// Points of view space per point of document space.
    public let scale: CGFloat
    /// View-space offset of the document's origin.
    public let offset: CGVector

    public init(scale: CGFloat = 1, offset: CGVector = .zero) {
        self.scale = scale
        self.offset = offset
    }

    /// Fit a document into a viewport, centred, never magnifying past 1:1 unless asked.
    public static func fitting(
        document: CGSize,
        in viewport: CGSize,
        allowUpscaling: Bool = false,
        padding: CGFloat = 0
    ) -> DocumentTransform {
        let available = CGSize(
            width: max(1, viewport.width - padding * 2),
            height: max(1, viewport.height - padding * 2)
        )
        guard document.width > 0, document.height > 0 else { return DocumentTransform() }

        var scale = min(available.width / document.width, available.height / document.height)
        if !allowUpscaling { scale = min(scale, 1) }

        let scaled = CGSize(width: document.width * scale, height: document.height * scale)
        return DocumentTransform(
            scale: scale,
            offset: CGVector(
                dx: (viewport.width - scaled.width) / 2,
                dy: (viewport.height - scaled.height) / 2
            )
        )
    }

    public func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.dx, y: point.y * scale + offset.dy)
    }

    public func toDocument(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.dx) / scale, y: (point.y - offset.dy) / scale)
    }

    public func toView(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + offset.dx,
            y: rect.minY * scale + offset.dy,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    public func toDocument(_ rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - offset.dx) / scale,
            y: (rect.minY - offset.dy) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    /// Scale a document-space length (a stroke width, a font size) into view space.
    public func toView(length: CGFloat) -> CGFloat {
        length * scale
    }
}
