import AppKit
import CoreImage
import Foundation
import PotretCore

/// Draws a ring wherever the user clicks, into the recording only.
///
/// A screen recording of an app is close to unreadable without this: the pointer moves, something
/// changes, and the viewer has to infer that a click happened and where. The ring is composited
/// into the frame during encoding rather than shown on screen, so it appears in the file without
/// putting anything over the user's actual display while they work.
///
/// Mouse events are watched with a global `NSEvent` monitor. That needs no permission — only
/// keyboard monitoring sits behind the Accessibility wall — so this costs the user nothing beyond
/// the Screen Recording grant they have already given.
public final class ClickHighlighter: @unchecked Sendable {
    /// How long a ring lives. Long enough to read at 30fps, short enough that a double-click
    /// reads as two rings rather than one smear.
    public static let duration: Double = 0.45

    private struct Ripple {
        let point: CGPoint
        let start: Double
    }

    /// The screen rectangle the recording covers, in global AppKit coordinates, and the scale of
    /// the frames. Nil until recording starts; a click before that has nowhere to go.
    private var area: (rect: CGRect, scale: CGFloat)?
    private var ripples: [Ripple] = []
    /// Monitors fire on the main thread; frames are composited on the writer queue.
    private let lock = NSLock()
    private var monitors: [Any] = []

    /// Recomputes the covered rectangle, for a target that can move. A window recording follows
    /// its window, so a rectangle captured once is wrong the moment the user drags it.
    private let areaProvider: (@Sendable () -> (rect: CGRect, scale: CGFloat)?)?

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    /// The ring is drawn once and reused, scaled per ripple — cheaper than rasterising a stroked
    /// circle for every frame of every click.
    private lazy var ringImage: CIImage? = Self.makeRing()

    public init(areaProvider: (@Sendable () -> (rect: CGRect, scale: CGFloat)?)? = nil) {
        self.areaProvider = areaProvider
    }

    // MARK: Lifecycle

    @MainActor
    public func start(covering rect: CGRect, scale: CGFloat) {
        lock.lock()
        area = (rect, scale)
        ripples.removeAll()
        lock.unlock()

        // Global monitors see other apps — the normal case, since the app being demonstrated is
        // not this one. The local monitor covers clicks on Potret's own windows, which a global
        // monitor never receives.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.record(at: NSEvent.mouseLocation)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.record(at: NSEvent.mouseLocation)
            return event
        }
        monitors = [global, local].compactMap { $0 }
        Log.capture.info("click highlighting armed")
    }

    @MainActor
    public func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        lock.lock()
        ripples.removeAll()
        area = nil
        lock.unlock()
    }

    /// Clicks seen and frames actually drawn on, reported when the recording stops. Without this
    /// a ring that never appears is indistinguishable from a click that was never seen.
    public private(set) var clicksSeen = 0
    public private(set) var framesDrawn = 0

    private func record(at point: CGPoint) {
        let now = CACurrentMediaTime()
        lock.lock()
        defer { lock.unlock() }
        // One click can reach both monitors — the global one and, when the click is on Potret's
        // own window, the local one. Two rings at the same spot draw twice as opaque and fade
        // wrongly, so a repeat at the same place within a few milliseconds is the same click.
        if let last = ripples.last,
           now - last.start < 0.05,
           abs(last.point.x - point.x) < 2, abs(last.point.y - point.y) < 2 {
            return
        }
        ripples.append(Ripple(point: point, start: now))
        clicksSeen += 1
        // Nothing older than one animation can still be drawn.
        ripples.removeAll { $0.start < now - Self.duration }
    }

    /// Whether any ring is currently visible. Checked per frame, so it stays cheap: when nothing
    /// has been clicked the recording path never touches the pixels at all.
    public var hasActiveRipples: Bool {
        let cutoff = CACurrentMediaTime() - Self.duration
        lock.lock()
        defer { lock.unlock() }
        return ripples.contains { $0.start >= cutoff }
    }

    // MARK: Compositing

    /// Draw the live rings over a frame. Returns nil when there is nothing to draw, so the caller
    /// can pass the original buffer straight through untouched.
    public func overlay(on source: CIImage, frameHeight: CGFloat) -> CIImage? {
        guard let ringImage else { return nil }

        lock.lock()
        let stored = area
        let live = ripples
        lock.unlock()

        let now = CACurrentMediaTime()
        guard let currentArea = areaProvider?() ?? stored else { return nil }

        // Rings scale with the recorded area, so one on a 4K display is not a dot and one on a
        // small region does not swallow it.
        let maximumRadius = max(36, min(currentArea.rect.width, currentArea.rect.height) * 0.08)
            * currentArea.scale

        var output = source
        var drawn = 0
        for ripple in live {
            guard
                let progress = ClickMapping.progress(
                    start: ripple.start, now: now, duration: Self.duration
                ),
                let point = ClickMapping.framePoint(
                    of: ripple.point, covering: currentArea.rect, scale: currentArea.scale
                )
            else { continue }

            let shape = ClickMapping.ripple(progress: progress, maximumRadius: maximumRadius)
            guard shape.radius > 0, shape.opacity > 0.01 else { continue }

            // CoreImage works bottom-up; the mapped point is top-down.
            let centre = CGPoint(x: point.x, y: frameHeight - point.y)
            let diameter = shape.radius * 2
            let factor = diameter / Self.ringSize

            let placed = ringImage
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                .transformed(
                    by: CGAffineTransform(
                        translationX: centre.x - shape.radius,
                        y: centre.y - shape.radius
                    )
                )
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: shape.opacity),
                ])

            output = placed.composited(over: output)
            drawn += 1
        }
        if drawn > 0 {
            lock.lock()
            framesDrawn += 1
            lock.unlock()
        }
        return drawn > 0 ? output : nil
    }

    public func render(_ image: CIImage, to buffer: CVPixelBuffer) {
        context.render(image, to: buffer)
    }

    // MARK: Ring artwork

    private static let ringSize: CGFloat = 160

    /// The ring, drawn once at a fixed size and scaled per ripple.
    ///
    /// Three passes, because a click can land on anything. A plain white ring disappears against
    /// a white page — which is most product UI — and a plain dark one disappears against a dark
    /// one. A dark stroke outside a bright one survives both, the same trick the selection
    /// marquee uses to stay visible over arbitrary content.
    ///
    /// These colours are deliberately literals rather than theme tokens: they are baked into an
    /// exported video, like the annotation palette, so they must not change with the user's
    /// appearance or accent colour.
    private static func makeRing() -> CIImage? {
        let size = Int(ringSize)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let inset: CGFloat = 16
        let rect = CGRect(
            x: inset, y: inset, width: ringSize - inset * 2, height: ringSize - inset * 2
        )

        // A wash inside, so the point of contact reads even before the ring is noticed.
        context.setFillColor(CGColor(red: 1, green: 0.78, blue: 0.16, alpha: 0.20))
        context.fillEllipse(in: rect)
        // Dark halo first, wider, so the bright ring always has an edge against light content.
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        context.setLineWidth(inset)
        context.strokeEllipse(in: rect)
        // Amber over it: warm enough to read as a deliberate marker rather than part of the UI,
        // and distinct from the accent blue that Potret's own chrome uses.
        context.setStrokeColor(CGColor(red: 1, green: 0.78, blue: 0.16, alpha: 1))
        context.setLineWidth(inset * 0.62)
        context.strokeEllipse(in: rect)

        return context.makeImage().map(CIImage.init(cgImage:))
    }
}
