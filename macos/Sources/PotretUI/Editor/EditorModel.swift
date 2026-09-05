import AppKit
import Observation
import PotretCore
import PotretRender

/// Which tool the pointer is currently wielding.
public enum EditorTool: String, CaseIterable, Sendable {
    case select
    case rectangle
    case ellipse
    case arrow
    case line
    case freehand
    case highlight
    case text
    case step
    case pixelate
    case blur
    case crop

    public var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .freehand: "scribble"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .step: "list.number"
        case .pixelate: "squareshape.split.3x3"
        case .blur: "drop"
        case .crop: "crop"
        }
    }

    public var label: String {
        switch self {
        case .select: "Select"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .line: "Line"
        case .freehand: "Draw"
        case .highlight: "Highlight"
        case .text: "Text"
        case .step: "Step number"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .crop: "Crop"
        }
    }

    /// Single-key shortcut. The Tauri editor had none at all, despite being a drawing tool.
    public var key: String {
        switch self {
        case .select: "v"
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .line: "l"
        case .freehand: "d"
        case .highlight: "h"
        case .text: "t"
        case .step: "s"
        case .pixelate: "p"
        case .blur: "b"
        case .crop: "c"
        }
    }
}

/// Editor state, and the only path through which the document is mutated.
///
/// Every change goes through `apply`, which registers the inverse with `UndoManager` — so ⌘Z and
/// ⌘⇧Z come from the system rather than being hand-rolled. The Tauri editor duplicated its undo
/// logic between a keyboard handler and two toolbar buttons, and its crop path silently discarded
/// the whole stack.
@MainActor
@Observable
public final class EditorModel {
    public private(set) var document: AnnotationDocument
    public let source: CGImage
    public var tool: EditorTool = .select
    public var color: InkColor = AnnotationPalette.default
    public var lineWidth: CGFloat = 4
    /// Set while a text element is being typed, so the canvas can host a field over it.
    public var editingText: AnnotationElement.ID?

    public let undoManager = UndoManager()
    private let onFinish: (CGImage) -> Void

    public init(document: AnnotationDocument, source: CGImage, onFinish: @escaping (CGImage) -> Void) {
        self.document = document
        self.source = source
        self.onFinish = onFinish
    }

    // MARK: Editing

    /// Mutate the document without recording undo — for the intermediate frames of a live drag.
    ///
    /// A drag produces one undoable edit on mouse-up, not sixty. Registering per frame would make
    /// ⌘Z rewind a move one pixel at a time.
    public func documentForLiveEdit(_ mutate: (inout AnnotationDocument) -> Void) {
        mutate(&document)
    }

    /// Replace an element without recording undo — used while text is being typed, so the canvas
    /// shows the real thing live but Cmd+Z rewinds the whole string rather than one letter.
    public func updateLive(_ element: AnnotationElement) {
        guard let index = document.index(of: element.id) else { return }
        document.elements[index] = element
    }

    public func apply(_ edit: DocumentEdit, name: String) {
        edit.apply(to: &document)
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.apply(edit.inverse, name: name) }
        }
    }

    public func add(_ element: AnnotationElement) {
        apply(.add(element), name: "Add \(element.kind.actionName)")
    }

    public func replace(_ old: AnnotationElement, with new: AnnotationElement) {
        apply(.replace(old: old, new: new), name: "Move \(old.kind.actionName)")
    }

    public func deleteSelection() {
        let doomed = document.selectedElements
        guard !doomed.isEmpty else { return }
        for element in doomed {
            apply(.remove(element), name: "Delete")
        }
        document.selection.removeAll()
    }

    public func setCrop(_ rect: CGRect?) {
        apply(.setCrop(old: document.cropRect, new: rect), name: "Crop")
    }

    public func select(_ id: AnnotationElement.ID?, extending: Bool = false) {
        guard let id else {
            document.selection.removeAll()
            return
        }
        if extending {
            document.selection.formSymmetricDifference([id])
        } else {
            document.selection = [id]
        }
    }

    public func nudgeSelection(by delta: CGVector) {
        for element in document.selectedElements {
            replace(element, with: element.moved(by: delta))
        }
    }

    /// Anything the user would lose by closing without saving.
    public var hasChanges: Bool {
        !document.elements.isEmpty || document.cropRect != nil || document.background != nil
    }

    public func style() -> AnnotationElement.Style {
        AnnotationElement.Style(color: color, lineWidth: lineWidth)
    }

    // MARK: Output

    /// Flatten to an image at full document resolution.
    public func render() -> CGImage? {
        let size = document.visibleRect.size
        guard size.width >= 1, size.height >= 1 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        AnnotationRenderer().draw(
            document: document,
            source: source,
            into: context,
            targetHeight: size.height
        )
        return context.makeImage()
    }

    public func finish() {
        guard let image = render() else { return }
        onFinish(image)
    }
}

extension AnnotationElement.Kind {
    var actionName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .freehand: "Drawing"
        case .highlight: "Highlight"
        case .text: "Text"
        case .step: "Step"
        case .pixelate: "Pixelation"
        case .blur: "Blur"
        }
    }
}
