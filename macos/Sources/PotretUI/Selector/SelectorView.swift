import AppKit
import PotretCore

/// The drag surface for area selection: dim scrim, live marquee, dimension badge, reticle — and,
/// once a drag ends, an adjustable selection with handles and the options bar beneath it.
///
/// Drawn with CGContext in an NSView rather than SwiftUI. This view repaints on every mouse-moved
/// event while a drag is in flight, and it needs raw NSEvent deltas and cursor control — all
/// simpler and cheaper here than through a SwiftUI bridge. The bar is SwiftUI, hosted as a
/// subview this view positions.
final class SelectorView: NSView {
    enum Phase: Equatable {
        /// Reticle follows the pointer; nothing selected yet.
        case idle
        /// A marquee drag is in flight.
        case dragging
        /// A selection exists and can be resized, moved, or acted on from the bar.
        case adjusting
    }

    /// The selection changed or was cleared. Fires on drag end, every resize/move step, and a
    /// typed size. In this view's coordinates.
    var onSelectionChanged: ((CGRect?) -> Void)?
    /// Return or Space over a finished selection.
    var onConfirm: (() -> Void)?
    /// Esc.
    var onCancel: (() -> Void)?
    /// F, over a finished selection.
    var onToggleFreeze: (() -> Void)?
    /// Fires when a drag starts, so sibling screens can clear their own marquee.
    var onDragBegan: (() -> Void)?
    /// The cursor is hidden while the reticle is drawn and shown while a selection is being
    /// adjusted; the coordinator owns the (counted) hide/unhide pair.
    var onPhaseChanged: ((Phase) -> Void)?

    /// The options bar, positioned under the selection whenever it changes. Hidden mid-drag.
    var accessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let accessory {
                accessory.isHidden = true
                addSubview(accessory)
            }
        }
    }

    /// A frame captured when the user chose Freeze. Drawn under the scrim so the selection is
    /// made over a still picture rather than whatever is animating underneath.
    var frozenImage: CGImage? {
        didSet { needsDisplay = true }
    }

    /// Keep width ÷ height fixed while a handle drags.
    var aspectLocked = false

    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            onPhaseChanged?(phase)
        }
    }

    private var anchor: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint = .zero
    /// The finished selection. Separate from anchor/current so a resize does not have to
    /// pretend to be a drag from a corner.
    private var adjusted: CGRect?
    private var activeHandle: SelectionGeometry.Handle?
    private var moveOrigin: CGPoint?

    /// Below this a drag reads as a stray click rather than a selection.
    private static let minimumDrag: CGFloat = 5
    private static let handleRadius: CGFloat = 4.5
    private static let handleTolerance: CGFloat = 8

    override var acceptsFirstResponder: Bool { true }

    /// The current selection, in this view's coordinates, if there is one.
    var selection: CGRect? {
        switch phase {
        case .adjusting: return adjusted
        case .dragging:
            guard let anchor, let current else { return nil }
            let rect = CoordinateSpace.normalized(from: anchor, to: current)
            return rect.width >= Self.minimumDrag && rect.height >= Self.minimumDrag ? rect : nil
        case .idle: return nil
        }
    }

    private var lockedAspect: CGFloat? {
        guard aspectLocked, let adjusted, adjusted.height > 0 else { return nil }
        return adjusted.width / adjusted.height
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
        if phase == .adjusting, let adjusted {
            if let accessory, !accessory.isHidden, accessory.frame.contains(pointer) {
                NSCursor.arrow.set()
            } else {
                cursor(for: SelectionGeometry.hitTest(pointer, in: adjusted, tolerance: Self.handleTolerance)).set()
            }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point

        if phase == .adjusting, let adjusted {
            switch SelectionGeometry.hitTest(point, in: adjusted, tolerance: Self.handleTolerance) {
            case .handle(let handle):
                activeHandle = handle
                return
            case .inside:
                moveOrigin = point
                NSCursor.closedHand.set()
                return
            case .outside:
                break // a new selection replaces the old one
            }
        }

        // Starting a fresh drag: the bar and any previous selection go away first.
        adjusted = nil
        accessory?.isHidden = true
        anchor = point
        current = point
        phase = .dragging
        onDragBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point

        if let activeHandle, let adjusted {
            self.adjusted = SelectionGeometry.resize(
                adjusted, handle: activeHandle, to: clamped(point),
                aspect: lockedAspect, minimum: Self.minimumDrag
            )
            selectionDidChange()
        } else if let moveOrigin, let adjusted {
            let delta = CGPoint(x: point.x - moveOrigin.x, y: point.y - moveOrigin.y)
            self.adjusted = SelectionGeometry.move(adjusted, by: delta, within: bounds)
            self.moveOrigin = point
            selectionDidChange()
        } else {
            current = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if activeHandle != nil || moveOrigin != nil {
            activeHandle = nil
            moveOrigin = nil
            if let adjusted {
                cursor(for: SelectionGeometry.hitTest(point, in: adjusted, tolerance: Self.handleTolerance)).set()
            }
            selectionDidChange()
            return
        }

        guard phase == .dragging else { return }
        current = point
        if let rect = selection {
            adjusted = rect.integral
            anchor = nil
            current = nil
            phase = .adjusting
            selectionDidChange()
        } else {
            // A click, not a drag: back to the reticle.
            clear()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // kVK_Escape
            // Esc is one of three independent ways out — see SelectorCoordinator. A selector
            // stuck at shielding level covers the menu bar and the Dock, which would leave the
            // Mac unusable.
            onCancel?()
        case 36, 76, 49: // Return, keypad Enter, Space
            if phase == .adjusting { onConfirm?() }
        case 3: // F
            if phase == .adjusting { onToggleFreeze?() }
        case 123, 124, 125, 126: // arrows: nudge by a point, ten with Shift
            guard phase == .adjusting, let adjusted else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGPoint = switch event.keyCode {
            case 123: CGPoint(x: -step, y: 0)
            case 124: CGPoint(x: step, y: 0)
            case 125: CGPoint(x: 0, y: -step)
            default: CGPoint(x: 0, y: step)
            }
            self.adjusted = SelectionGeometry.move(adjusted, by: delta, within: bounds)
            selectionDidChange()
        default:
            super.keyDown(with: event)
        }
    }

    /// An exact size, typed into the bar. Pixels, converted with this window's scale.
    func setSelectionSize(pixels size: CGSize) {
        guard phase == .adjusting, let adjusted else { return }
        let scale = window?.backingScaleFactor ?? 1
        let points = CGSize(width: size.width / scale, height: size.height / scale)
        self.adjusted = SelectionGeometry.resized(
            adjusted, toSize: points, within: bounds, minimum: Self.minimumDrag
        )
        selectionDidChange()
    }

    func clear() {
        anchor = nil
        current = nil
        adjusted = nil
        activeHandle = nil
        moveOrigin = nil
        accessory?.isHidden = true
        let hadSelection = phase != .idle
        phase = .idle
        needsDisplay = true
        if hadSelection { onSelectionChanged?(nil) }
    }

    // MARK: Internals

    private func selectionDidChange() {
        layoutAccessory()
        needsDisplay = true
        onSelectionChanged?(adjusted)
    }

    /// Put the bar under the selection, or wherever there is room.
    private func layoutAccessory() {
        guard let accessory, let adjusted else { return }
        let size = accessory.fittingSize
        accessory.frame = SelectionGeometry.barFrame(
            size: size, below: adjusted, within: bounds, gap: Space.m
        )
        accessory.isHidden = false
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// The cursor for what is under the pointer. Diagonal resize cursors are only public from
    /// macOS 15; on 14 the corners fall back to the crosshair, which still reads as "grab here".
    private func cursor(for hit: SelectionGeometry.Hit) -> NSCursor {
        switch hit {
        case .inside: return .openHand
        case .outside: return .crosshair
        case .handle(let handle):
            if #available(macOS 15, *) {
                let position: NSCursor.FrameResizePosition = switch handle {
                case .topLeft: .topLeft
                case .top: .top
                case .topRight: .topRight
                case .left: .left
                case .right: .right
                case .bottomLeft: .bottomLeft
                case .bottom: .bottom
                case .bottomRight: .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            if handle.isCorner { return .crosshair }
            return handle.movesLeft || handle.movesRight ? .resizeLeftRight : .resizeUpDown
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let frozenImage {
            context.interpolationQuality = .high
            context.draw(frozenImage, in: bounds)
        }

        // Scrim with the selection punched out, as one even-odd fill rather than the four separate
        // rects the web overlay used — no seams where they met.
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection { path.addRect(selection) }
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        switch phase {
        case .idle:
            drawReticle(at: pointer, in: context)
            drawHint(in: context)
        case .dragging:
            if let selection {
                drawMarquee(selection, in: context)
                drawDimensions(for: selection, in: context)
            }
        case .adjusting:
            if let adjusted {
                drawMarquee(adjusted, in: context)
                drawHandles(for: adjusted, in: context)
            }
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

    private func drawHandles(for rect: CGRect, in context: CGContext) {
        let radius = Self.handleRadius
        for handle in SelectionGeometry.Handle.allCases {
            let point = handle.point(in: rect)
            let circle = CGRect(
                x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2
            )
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: circle)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: circle)
        }
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
        let text = "Drag to select an area · Esc to cancel"
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
