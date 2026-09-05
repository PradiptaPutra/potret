import AppKit
import PotretCore

/// The drag surface for area selection: dim scrim, live marquee, dimension badge, reticle.
///
/// Drawn with CGContext in an NSView rather than SwiftUI. This view repaints on every mouse-moved
/// event while a drag is in flight, and it needs raw NSEvent deltas and cursor control — all
/// simpler and cheaper here than through a SwiftUI bridge.
final class SelectorView: NSView {
    /// Called with the selection in this view's coordinates, or nil when the user cancels.
    var onComplete: ((CGRect?) -> Void)?
    /// Fires when a drag starts, so sibling screens can clear their own marquee.
    var onDragBegan: (() -> Void)?

    private var anchor: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint = .zero

    /// Below this a drag reads as a stray click rather than a selection.
    private static let minimumDrag: CGFloat = 5

    override var acceptsFirstResponder: Bool { true }

    private var selection: CGRect? {
        guard let anchor, let current else { return nil }
        let rect = CoordinateSpace.normalized(from: anchor, to: current)
        return rect.width >= Self.minimumDrag && rect.height >= Self.minimumDrag ? rect : nil
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                // .activeAlways: the app is not frontmost during a capture, and without it the
                // reticle would freeze the moment focus went elsewhere.
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        anchor = point
        current = point
        pointer = point
        onDragBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        pointer = current ?? pointer
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let result = selection
        clear()
        onComplete?(result)
    }

    override func keyDown(with event: NSEvent) {
        // Esc is one of three independent ways out — see SelectorCoordinator. A selector stuck at
        // shielding level covers the menu bar and the Dock, which would leave the Mac unusable.
        if event.keyCode == 53 { // kVK_Escape
            clear()
            onComplete?(nil)
        }
    }

    func clear() {
        anchor = nil
        current = nil
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Scrim with the selection punched out, as one even-odd fill rather than the four separate
        // rects the web overlay used — no seams where they met.
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection { path.addRect(selection) }
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        if let selection {
            drawMarquee(selection, in: context)
            drawDimensions(for: selection, in: context)
        } else {
            drawReticle(at: pointer, in: context)
            drawHint(in: context)
        }
    }

    private func drawMarquee(_ rect: CGRect, in context: CGContext) {
        // A dark hairline outside the accent line keeps the edge visible on light content.
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(3)
        context.stroke(rect)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
    }

    private func drawDimensions(for rect: CGRect, in context: CGContext) {
        let scale = window?.backingScaleFactor ?? 1
        // Report pixels, which is what the file will contain — points would understate a Retina
        // capture by half.
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TypeRamp.AppKit.badge,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = Space.s
        var badge = CGRect(
            x: rect.minX,
            y: rect.minY - size.height - padding * 1.5,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        // Flip above the selection when there is no room below, and clamp horizontally, so the
        // badge is never half off-screen.
        if badge.minY < bounds.minY { badge.origin.y = rect.maxY + padding * 0.5 }
        badge.origin.x = min(max(badge.minX, bounds.minX + 2), bounds.maxX - badge.width - 2)

        context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.addPath(
            CGPath(roundedRect: badge, cornerWidth: Radius.sm, cornerHeight: Radius.sm,
                   transform: nil)
        )
        context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: badge.minX + padding, y: badge.minY + padding / 2),
            withAttributes: attributes
        )
    }

    /// The OS cursor is hidden during selection, so the overlay draws its own.
    ///
    /// A ring plus centre dot is easier to place precisely than an arrow, and being drawn rather
    /// than set it cannot be left stuck on screen after the overlay goes away.
    private func drawReticle(at point: CGPoint, in context: CGContext) {
        let radius: CGFloat = 7
        let ring = CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: ring)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: ring)

        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
    }

    private func drawHint(in context: CGContext) {
        let text = "Drag to capture an area · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TypeRamp.AppKit.hint,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = Space.m
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
