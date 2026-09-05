import AppKit
import PotretCore
import SwiftUI
import UniformTypeIdentifiers

/// An AppKit drag source, for surfaces where SwiftUI's `.onDrag` proved unreliable.
///
/// `.onDrag` recognises the gesture through SwiftUI's own tracking, which is re-established every
/// time the view's body is re-evaluated. The capture popup re-evaluates twenty times a second to
/// advance its countdown, and the drag never crossed its threshold before being reset. An
/// `NSView` owns its mouse events directly: mouse-down, a few points of movement, and it begins
/// an `NSDraggingSession` — nothing SwiftUI does afterwards can interrupt that.
///
/// Placed as an overlay on the thing being dragged. It is transparent and takes the mouse.
struct FileDragSource: NSViewRepresentable {
    /// Stages the file and returns its URL; nil declines the drag.
    let provideURL: () -> URL?
    /// The picture that travels with the pointer.
    let dragImage: NSImage?
    var onBegan: (() -> Void)? = nil
    /// A click that did not become a drag.
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: DragSourceView) {
        view.provideURL = provideURL
        view.dragImage = dragImage
        view.onBegan = onBegan
        view.onClick = onClick
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var provideURL: (() -> URL?)?
        var dragImage: NSImage?
        var onBegan: (() -> Void)?
        var onClick: (() -> Void)?

        private var mouseDownLocation: NSPoint?
        /// Movement below this is a click, above it a drag — AppKit's own threshold.
        private static let dragThreshold: CGFloat = 4

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownLocation else { return }
            let now = event.locationInWindow
            guard hypot(now.x - start.x, now.y - start.y) >= Self.dragThreshold else { return }
            mouseDownLocation = nil

            guard let url = provideURL?() else {
                Log.ui.error("drag declined: nothing to stage")
                return
            }
            onBegan?()
            Log.ui.info("drag session began for \(url.lastPathComponent, privacy: .public)")

            let item = NSDraggingItem(pasteboardWriter: Self.pasteboardItem(for: url))
            item.setDraggingFrame(bounds, contents: dragImage)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            // Never moved far enough to drag: it was a click.
            if mouseDownLocation != nil {
                mouseDownLocation = nil
                onClick?()
            }
        }

        /// Both a file reference and the raw bytes, so every kind of destination is served: Finder
        /// and Slack take the file (keeping the filename), while text fields and web composers —
        /// which would otherwise paste "file:///…" as a string — take the image data.
        private static func pasteboardItem(for url: URL) -> NSPasteboardItem {
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if let data = try? Data(contentsOf: url) {
                let type: NSPasteboard.PasteboardType = url.pathExtension.lowercased() == "png"
                    ? .png
                    : NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)
                item.setData(data, forType: type)
            }
            return item
        }

        // MARK: NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            Log.ui.info("drag session ended: \(operation.rawValue)")
        }
    }
}
