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
    /// Called when a text element is created or double-clicked, so the host can present a field.
    var onEditText: ((AnnotationElement) -> Void)?

    private let renderer = AnnotationRenderer()
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var freehandPoints: [CGPoint] = []
    private var movingElement: AnnotationElement?
    private var cropDraft: CGRect?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

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
        let visible = model?.document.visibleRect ?? .zero
        let point = transform.toDocument(inView)
        // Transform maps into the visible (cropped) region; elements live in full document space.
        return CGPoint(x: point.x + visible.minX, y: point.y + visible.minY)
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

        renderer.draw(
            document: document,
            source: model.source,
            into: context,
            transform: transform,
            targetHeight: bounds.height
        )

        drawSelectionChrome(in: context, model: model)
        drawCropChrome(in: context)
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
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        for element in model.document.selectedElements {
            let box = element.boundingBox.offsetBy(dx: -visible.minX, dy: -visible.minY)
            context.stroke(transform.toView(box).insetBy(dx: -3, dy: -3))
        }
        context.restoreGState()
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

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
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
        context.restoreGState()
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
        case .step:
            model.add(
                AnnotationElement(
                    kind: .step(center: point, number: model.document.nextStepNumber),
                    style: model.style()
                )
            )
            dragStart = nil
        case .text:
            let element = AnnotationElement(
                kind: .text(.init(string: "", origin: point, fontSize: max(18, model.lineWidth * 6))),
                style: model.style()
            )
            model.add(element)
            onEditText?(element)
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
