import AppKit
import PotretCore
import PotretRender

/// The drawing surface.
///
/// An `NSView` drawing through `AnnotationRenderer`, not a SwiftUI `Canvas`. SwiftUI's
/// `GraphicsContext` cannot render offscreen, so choosing it would force a second renderer for
/// export — which is exactly the two-renderers-drift problem being eliminated. Here the screen and
/// the exported file go through the same function.
@MainActor
final class AnnotationCanvasView: NSView {
    var model: EditorModel? {
        didSet { needsDisplay = true }
    }
    /// Called when a text element is created or double-clicked. The rect and font size are in
    /// view coordinates, so the editing field can be placed exactly where the text will render, at
    /// the size it will render — which is what makes typing WYSIWYG rather than a guess.
    var onEditText: ((AnnotationElement, CGRect, CGFloat) -> Void)?

    private let renderer = AnnotationRenderer()
    /// The document rendered to a bitmap at view resolution, reused across frames.
    ///
    /// Every mouse-moved event redraws this view, and a redraw re-scaled the full-resolution
    /// capture with high-quality interpolation — a 1920×1200 image resampled sixty times a second.
    /// That is why dragging a crop felt like it was fighting the trackpad. The base is now
    /// rendered once and only re-rendered when something that affects it actually changes.
    private var baseCache: CGImage?
    private var baseCacheKey: BaseCacheKey?

    private struct BaseCacheKey: Equatable {
        let elements: [AnnotationElement]
        let crop: CGRect?
        let background: Backdrop?
        let size: CGSize
        let scale: CGFloat
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var freehandPoints: [CGPoint] = []
    private var movingElement: AnnotationElement?
    private var cropDraft: CGRect?

    // NOT flipped, deliberately. An NSView with isFlipped = true hands its CGContext a y-down
    // CTM, and AnnotationRenderer applies its own y-down flip on top. The two cancel: the source
    // image still draws correctly (CGContext.draw handles orientation itself) but every annotation
    // renders vertically mirrored, while the mouse is mapped in y-down space — so shapes appear
    // reflected about the middle of the canvas instead of under the cursor. Keeping the view
    // y-up leaves the renderer as the single place that defines document orientation.
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    /// Draw at the display's real pixel density.
    ///
    /// This view lives inside an NSHostingView, so it is layer-backed. A layer whose
    /// contentsScale is left at 1 renders at half resolution on a Retina display, which is
    /// exactly what a blurry screenshot-of-a-screenshot looks like.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        baseCache = nil
        updateContentsScale()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        baseCache = nil
    }

    private func updateContentsScale() {
        guard let scale = window?.backingScaleFactor else { return }
        layer?.contentsScale = scale
        needsDisplay = true
    }

    // MARK: Geometry

    /// Document → view, fitted and centred, recomputed on every layout so a resized window
    /// re-fits rather than scrolling.
    private var transform: DocumentTransform {
        guard let model else { return DocumentTransform() }
        return DocumentTransform.fitting(
            document: model.document.visibleRect.size,
            in: bounds.size,
            padding: Space.l
        )
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint {
        let inView = convert(event.locationInWindow, from: nil)
        // The view is y-up; document space is y-down, matching image pixels. Flip before mapping,
        // or the pointer and the ink disagree about which way is down.
        let yDown = CGPoint(x: inView.x, y: bounds.height - inView.y)
        let visible = model?.document.visibleRect ?? .zero
        let point = transform.toDocument(yDown)
        // The transform maps into the visible (cropped) region; elements live in full document
        // space, so shift by the crop origin.
        return CGPoint(x: point.x + visible.minX, y: point.y + visible.minY)
    }

    /// Run `body` with the context flipped to document orientation, so chrome drawn from
    /// document-derived rects lines up with the ink the renderer produced.
    private func inDocumentSpace(_ context: CGContext, _ body: () -> Void) {
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        body()
        context.restoreGState()
    }

    /// Convert a text element's position into view space and hand it to the host.
    private func beginEditing(_ element: AnnotationElement, fontSize: CGFloat) {
        guard let model, case .text(let content) = element.kind else { return }
        let visible = model.document.visibleRect
        let originInView = transform.toView(
            CGPoint(x: content.origin.x - visible.minX, y: content.origin.y - visible.minY)
        )
        let scaledFont = transform.toView(length: fontSize)
        let rect = CGRect(
            x: originInView.x,
            // The view is y-up while document space is y-down, so flip the origin back.
            y: bounds.height - originInView.y - scaledFont * 1.35,
            width: max(160, bounds.width - originInView.x - Space.l),
            height: scaledFont * 1.35
        )
        onEditText?(element, rect, scaledFont)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let context = NSGraphicsContext.current?.cgContext else { return }

        var document = model.document
        // Draw the in-progress shape as a real element, so what you see mid-drag is exactly what
        // gets committed — no separate preview code path to drift.
        if let draft = draftElement() {
            document.elements.append(draft)
        }

        if let cached = cachedBase(for: document, model: model) {
            context.saveGState()
            context.interpolationQuality = .none // 1:1 blit; the work was done when it was cached
            context.draw(cached, in: CGRect(origin: .zero, size: bounds.size))
            context.restoreGState()
        } else {
            renderer.draw(
                document: document,
                source: model.source,
                into: context,
                transform: transform,
                targetHeight: bounds.height
            )
        }

        drawSelectionChrome(in: context, model: model)
        drawCropChrome(in: context)
    }

    /// Render the document to a bitmap at view resolution, reusing the previous one when nothing
    /// that affects it has changed. Crop chrome and selection handles draw on top afterwards, so
    /// dragging either of those is a blit rather than a full re-render.
    private func cachedBase(for document: AnnotationDocument, model: EditorModel) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let key = BaseCacheKey(
            elements: document.elements,
            crop: document.cropRect,
            background: document.background,
            size: bounds.size,
            scale: scale
        )
        if key == baseCacheKey, let baseCache { return baseCache }

        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        renderer.draw(
            document: document,
            source: model.source,
            into: context,
            transform: transform,
            targetHeight: bounds.height
        )

        baseCache = context.makeImage()
        baseCacheKey = key
        return baseCache
    }

    private func draftElement() -> AnnotationElement? {
        guard let model, let start = dragStart, let current = dragCurrent else { return nil }
        let style = model.style()
        let rect = CoordinateSpace.normalized(from: start, to: current)

        switch model.tool {
        case .rectangle: return AnnotationElement(kind: .rectangle(rect), style: style)
        case .ellipse: return AnnotationElement(kind: .ellipse(rect), style: style)
        case .line: return AnnotationElement(kind: .line(from: start, to: current), style: style)
        case .arrow: return AnnotationElement(kind: .arrow(from: start, to: current), style: style)
        case .freehand:
            return AnnotationElement(kind: .freehand(freehandPoints), style: style)
        case .highlight:
            return AnnotationElement(kind: .highlight(freehandPoints), style: style)
        case .pixelate: return AnnotationElement(kind: .pixelate(rect), style: style)
        case .blur: return AnnotationElement(kind: .blur(rect), style: style)
        case .select, .text, .step, .crop: return nil
        }
    }

    private func drawSelectionChrome(in context: CGContext, model: EditorModel) {
        guard !model.document.selection.isEmpty else { return }
        let visible = model.document.visibleRect
        inDocumentSpace(context) {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            for element in model.document.selectedElements {
                let box = element.boundingBox.offsetBy(dx: -visible.minX, dy: -visible.minY)
                context.stroke(transform.toView(box).insetBy(dx: -3, dy: -3))
            }
        }
    }

    /// Crop chrome, with handles that are real.
    ///
    /// The Tauri editor drew four white dots inside a `pointer-events: none` container: they
    /// looked draggable and were purely decorative, which is the most misleading affordance the
    /// app had.
    private func drawCropChrome(in context: CGContext) {
        guard let model, model.tool == .crop else { return }
        let visible = model.document.visibleRect
        let rect = cropDraft ?? model.document.cropRect ?? CGRect(origin: .zero, size: model.document.sourceSize)
        let viewRect = transform.toView(rect.offsetBy(dx: -visible.minX, dy: -visible.minY))

        inDocumentSpace(context) {
            context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: bounds.size))
            path.addRect(viewRect)
            context.addPath(path)
            context.fillPath(using: .evenOdd)

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(viewRect)

            for handle in CropHandle.allCases {
                let point = handle.position(in: viewRect)
                let box = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: box)
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
                context.strokeEllipse(in: box)
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = documentPoint(event)
        dragStart = point
        dragCurrent = point
        freehandPoints = [point]

        switch model.tool {
        case .select:
            let hit = model.document.hitTest(point, tolerance: 8 / max(transform.scale, 0.01))
            model.select(hit?.id, extending: event.modifierFlags.contains(.shift))
            movingElement = hit
            // Double-clicking existing text re-opens it for editing. The Tauri editor had no way
            // to change a string once placed — you deleted it and typed it again.
            if event.clickCount == 2, let hit, case .text(let content) = hit.kind {
                beginEditing(hit, fontSize: content.fontSize)
            }
        case .step:
            model.add(
                AnnotationElement(
                    kind: .step(center: point, number: model.document.nextStepNumber),
                    style: model.style()
                )
            )
            dragStart = nil
        case .text:
            let fontSize = max(18, model.lineWidth * 6)
            let element = AnnotationElement(
                kind: .text(.init(string: "", origin: point, fontSize: fontSize)),
                style: model.style()
            )
            model.add(element)
            beginEditing(element, fontSize: fontSize)
            dragStart = nil
        case .crop:
            cropDraft = CGRect(origin: point, size: .zero)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let start = dragStart else { return }
        let point = documentPoint(event)
        dragCurrent = point

        switch model.tool {
        case .freehand, .highlight:
            freehandPoints.append(point)
        case .select:
            if let moving = movingElement {
                let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
                // Live-move the element without recording an edit per frame; the undoable edit is
                // registered once on mouse-up.
                if let index = model.document.index(of: moving.id) {
                    model.documentForLiveEdit { $0.elements[index] = moving.moved(by: delta) }
                }
            }
        case .crop:
            cropDraft = CoordinateSpace.normalized(from: start, to: point)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        defer {
            dragStart = nil
            dragCurrent = nil
            freehandPoints = []
            movingElement = nil
            needsDisplay = true
        }

        switch model.tool {
        case .select:
            if let moving = movingElement, let index = model.document.index(of: moving.id) {
                let moved = model.document.elements[index]
                if moved != moving {
                    // Restore the original, then apply the move as one undoable edit.
                    model.documentForLiveEdit { $0.elements[index] = moving }
                    model.replace(moving, with: moved)
                }
            }
        case .crop:
            if let draft = cropDraft, draft.width > 8, draft.height > 8 {
                model.setCrop(draft)
            }
            cropDraft = nil
        default:
            if let draft = draftElement(), draft.isMeaningful {
                model.add(draft)
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        needsDisplay = true
    }

    /// The pointer tells you what the next click will do, and a crosshair marks the exact pixel.
    /// An arrow cursor over a drawing surface hides its own hotspot behind the arrowhead, which is
    /// why placing a box accurately was guesswork.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor(for: model?.tool ?? .select))
    }

    private func cursor(for tool: EditorTool) -> NSCursor {
        switch tool {
        case .select: .arrow
        case .text: .iBeam
        case .freehand, .highlight: .crosshair
        case .crop: .crosshair
        default: .crosshair
        }
    }

    /// Called by the host when the tool changes, since cursor rects are cached until invalidated.
    func toolDidChange() {
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}

/// Corners of a crop rectangle.
enum CropHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

extension AnnotationElement {
    /// A click that produced no drag should not leave an invisible zero-sized element behind.
    var isMeaningful: Bool {
        switch kind {
        case .freehand(let points), .highlight(let points):
            return points.count > 1
        case .text(let content):
            return !content.string.isEmpty
        case .step:
            return true
        default:
            return boundingBox.width > 2 || boundingBox.height > 2
        }
    }
}
