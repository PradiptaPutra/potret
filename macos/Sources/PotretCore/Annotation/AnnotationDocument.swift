import CoreGraphics
import Foundation

/// An image plus everything drawn over it.
///
/// The source image is `let`. That single decision removes a whole class of bug the Tauri editor
/// had: it composited the screenshot and every annotation into one canvas, so the eraser —
/// `destination-out` on that canvas — punched transparent holes through the screenshot itself, and
/// crop had to bake everything and wipe the undo stack because there was nothing else to crop.
/// Here annotations are a display list over an untouched image, so erasing means removing an
/// element and cropping is a rectangle the renderer honours.
public struct AnnotationDocument: Equatable, Sendable {
    /// Pixel size of the source image. The image itself lives outside the model, which keeps this
    /// type a value type and testable without loading anything.
    public let sourceSize: CGSize
    /// Non-destructive and undoable, unlike the Tauri crop.
    public var cropRect: CGRect?
    /// Back to front. Index is z-order.
    public var elements: [AnnotationElement]
    public var selection: Set<AnnotationElement.ID>
    /// A backdrop to sit the capture on. A document property rather than a separate tool, so it
    /// renders through the same pipeline, exports through the same path, and is undoable like
    /// anything else. The Tauri background tool was a 594-line modal with its own compositor, its
    /// own preview scaling and its own clipboard implementation.
    public var background: Backdrop?

    public init(
        sourceSize: CGSize,
        cropRect: CGRect? = nil,
        elements: [AnnotationElement] = [],
        selection: Set<AnnotationElement.ID> = [],
        background: Backdrop? = nil
    ) {
        self.sourceSize = sourceSize
        self.cropRect = cropRect
        self.elements = elements
        self.selection = selection
        self.background = background
    }

    /// Size of the finished image, including any backdrop padding.
    public var outputSize: CGSize {
        guard let background else { return visibleRect.size }
        return background.outputSize(for: visibleRect.size)
    }

    /// The region actually rendered — the crop if there is one, otherwise the whole image.
    public var visibleRect: CGRect {
        cropRect ?? CGRect(origin: .zero, size: sourceSize)
    }

    public var selectedElements: [AnnotationElement] {
        elements.filter { selection.contains($0.id) }
    }

    /// Next number for the step tool.
    ///
    /// Derived from the elements present rather than a running counter, so undoing a step frees
    /// its number. The Tauri editor used a monotonic ref that was never decremented, so undo then
    /// redraw produced 1, 2, 4.
    public var nextStepNumber: Int {
        let used = elements.compactMap { element -> Int? in
            if case .step(_, let number) = element.kind { return number }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    public func index(of id: AnnotationElement.ID) -> Int? {
        elements.firstIndex { $0.id == id }
    }

    /// Front-most element containing the point.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat = 8) -> AnnotationElement? {
        elements.reversed().first { $0.contains(point, tolerance: tolerance) }
    }

    public func elements(in rect: CGRect) -> [AnnotationElement] {
        elements.filter { rect.contains($0.boundingBox) }
    }
}
