import AppKit
import PotretCore

/// Highlights the window under the pointer and reports the one clicked.
final class WindowPickerView: NSView {
    struct Candidate {
        let id: CGWindowID
        /// AppKit global coordinates.
        let frame: CGRect
        let title: String
        let app: String
    }

    var candidates: [Candidate] = []
    /// This screen's origin in global space, so global frames can be drawn locally.
    var screenOrigin: CGPoint = .zero
    var onPick: ((CGWindowID?) -> Void)?

    private var hovered: Candidate?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    /// Front-most window containing the point wins. `candidates` arrives ordered front to back.
    private func candidate(at globalPoint: CGPoint) -> Candidate? {
        candidates.first { $0.frame.contains(globalPoint) }
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = candidate(at: NSEvent.mouseLocation)
        guard hit?.id != hovered?.id else { return }
        hovered = hit
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onPick?(candidate(at: NSEvent.mouseLocation)?.id)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onPick?(nil) } // Esc
    }

    private func local(_ globalRect: CGRect) -> CGRect {
        globalRect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything, then cut out the hovered window so it reads as the thing being chosen.
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        if let hovered { path.addRect(local(hovered.frame)) }
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        guard let hovered else {
            drawHint(in: context)
            return
        }

        let frame = local(hovered.frame)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(3)
        context.stroke(frame)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(2)
        context.stroke(frame)

        drawLabel(for: hovered, in: frame, context: context)
    }

    private func drawLabel(for candidate: Candidate, in frame: CGRect, context: CGContext) {
        // App name plus window title: the title alone is often empty or ambiguous, and knowing
        // which app owns the window is usually what disambiguates two similar ones.
        let text = candidate.title == candidate.app
            ? candidate.app
            : "\(candidate.app) — \(candidate.title)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TypeRamp.AppKit.hint,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = Space.s
        let maxWidth = min(size.width, frame.width - padding * 2, bounds.width * 0.6)

        var badge = CGRect(
            x: frame.midX - (maxWidth + padding * 2) / 2,
            y: frame.midY - (size.height + padding) / 2,
            width: maxWidth + padding * 2,
            height: size.height + padding
        )
        // A window can be mostly off-screen; keep its label reachable.
        badge.origin.x = min(max(badge.minX, bounds.minX + Space.s), bounds.maxX - badge.width)
        badge.origin.y = min(max(badge.minY, bounds.minY + Space.s), bounds.maxY - badge.height)

        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.addPath(
            CGPath(roundedRect: badge, cornerWidth: Radius.sm, cornerHeight: Radius.sm,
                   transform: nil)
        )
        context.fillPath()

        (text as NSString).draw(
            in: CGRect(
                x: badge.minX + padding,
                y: badge.minY + padding / 2,
                width: maxWidth,
                height: size.height
            ),
            withAttributes: attributes
        )
    }

    private func drawHint(in context: CGContext) {
        let text = "Click a window to capture it · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TypeRamp.AppKit.hint,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = Space.m
        let badge = CGRect(
            x: bounds.midX - (size.width + padding * 2) / 2,
            y: bounds.maxY - size.height - padding * 3,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.addPath(
            CGPath(roundedRect: badge, cornerWidth: Radius.md, cornerHeight: Radius.md,
                   transform: nil)
        )
        context.fillPath()
        (text as NSString).draw(
            at: CGPoint(x: badge.minX + padding, y: badge.minY + padding / 2),
            withAttributes: attributes
        )
    }
}
