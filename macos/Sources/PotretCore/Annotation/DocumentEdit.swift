import CoreGraphics
import Foundation

/// A single undoable change.
///
/// Every mutation goes through one of these, and each knows its own inverse. The Tauri editor kept
/// two arrays of whole shape-lists and rebuilt from scratch on every change; an edit here costs a
/// couple of hundred bytes instead of a copy of the document, and crop is undoable like anything
/// else rather than clearing the entire history.
public enum DocumentEdit: Equatable, Sendable {
    case add(AnnotationElement)
    case remove(AnnotationElement)
    case replace(old: AnnotationElement, new: AnnotationElement)
    case setCrop(old: CGRect?, new: CGRect?)
    case reorder(id: AnnotationElement.ID, from: Int, to: Int)

    public var inverse: DocumentEdit {
        switch self {
        case .add(let element): .remove(element)
        case .remove(let element): .add(element)
        case .replace(let old, let new): .replace(old: new, new: old)
        case .setCrop(let old, let new): .setCrop(old: new, new: old)
        case .reorder(let id, let from, let to): .reorder(id: id, from: to, to: from)
        }
    }

    public func apply(to document: inout AnnotationDocument) {
        switch self {
        case .add(let element):
            document.elements.append(element)
        case .remove(let element):
            document.elements.removeAll { $0.id == element.id }
            document.selection.remove(element.id)
        case .replace(_, let new):
            guard let index = document.index(of: new.id) else { return }
            document.elements[index] = new
        case .setCrop(_, let new):
            document.cropRect = new
        case .reorder(let id, _, let to):
            guard let index = document.index(of: id) else { return }
            let element = document.elements.remove(at: index)
            document.elements.insert(element, at: min(max(0, to), document.elements.count))
        }
    }
}
