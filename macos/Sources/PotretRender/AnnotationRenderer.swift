import CoreGraphics
import CoreImage
import CoreText
import Foundation
import PotretCore

/// Draws a document into a `CGContext`.
///
/// There is exactly one of these, used by the on-screen view and by the exporter. That is the
/// point: the Tauri editor drew the canvas for display and re-derived the export separately, and
/// the two drifted — most visibly in text, which appeared in one place while editing and landed
/// somewhere else in the saved file.
///
/// Document space has its origin at the **top-left** with y increasing downward, matching image
/// pixels. The renderer flips the context once at the start so every element's maths reads the way
/// the coordinates were authored.
public final class AnnotationRenderer {
    private let effects: EffectsCache

    public init(effects: EffectsCache = EffectsCache()) {
        self.effects = effects
    }

    /// - Parameters:
    ///   - transform: document → target space. Use `.init()` for a 1:1 export.
    /// - Parameter backgroundImage: decoded custom backdrop, when the style uses one. Passed in
    ///   rather than loaded here so this stays synchronous and free of file IO.
    public func draw(
        document: AnnotationDocument,
        source: CGImage,
        into context: CGContext,
        transform: DocumentTransform = DocumentTransform(),
        targetHeight: CGFloat,
        backgroundImage: CGImage? = nil
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        // A capture is almost always larger than the canvas it is shown in, so it is drawn
        // downscaled. CoreGraphics' default interpolation is visibly soft at those ratios —
        // text in a screenshot of a screenshot turns to mush.
        context.interpolationQuality = .high

        // CGContext is y-up; document space is y-down. Flip once here rather than negating every
        // coordinate downstream.
        context.translateBy(x: 0, y: targetHeight)
        context.scaleBy(x: 1, y: -1)

        context.translateBy(x: transform.offset.dx, y: transform.offset.dy)
        context.scaleBy(x: transform.scale, y: transform.scale)

        let visible = document.visibleRect

        // Backdrop pass. Shifts the capture inward by the padding, so everything below draws in
        // the same document coordinates whether or not there is a background.
        if let background = document.background {
            let inset = background.padding(for: visible.size)
            drawBackground(background, imageSize: visible.size, in: context, backgroundImage: backgroundImage)
            context.translateBy(x: inset, y: inset)
        }

        context.translateBy(x: -visible.minX, y: -visible.minY)

        // Rounded corners belong to the capture, so the clip is the corner radius when there is a
        // backdrop and a plain rect otherwise.
        if let background = document.background, background.cornerFraction > 0 {
            let radius = background.cornerRadius(for: visible.size)
            context.addPath(
                CGPath(roundedRect: visible, cornerWidth: radius, cornerHeight: radius, transform: nil)
            )
            context.clip()
        } else {
            context.clip(to: visible)
        }

        drawUpright(source, size: document.sourceSize, in: context)

        // Effects composite as one cached image, so dragging an arrow across a pixelated region
        // does not recompute the pixelation. The Tauri editor re-ran a getImageData loop per 12px
        // block on every single shape mutation.
        if let effectsImage = effects.image(for: document, source: source) {
            drawUpright(effectsImage, size: document.sourceSize, in: context)
        }

        for element in document.elements where !element.kind.isEffect {
            draw(element, in: context)
        }
    }

    /// Fill, then the capture's drop shadow.
    ///
    /// The shadow is cast by a **separate filled shape drawn before any clipping**. This is the
    /// exact bug the Tauri background tool shipped: it set shadowBlur/shadowColor and then clipped
    /// to the same rounded rect it drew the image into, so the shadow rendered entirely outside
    /// the clip region and was discarded. With the default corner radius of 12 the shadow toggle
    /// did nothing at all — the feature looked implemented and never drew a pixel.
    private func drawBackground(
        _ style: Backdrop,
        imageSize: CGSize,
        in context: CGContext,
        backgroundImage: CGImage?
    ) {
        let output = style.outputSize(for: imageSize)
        let imageRect = style.imageRect(for: imageSize)
        let radius = style.cornerRadius(for: imageSize)
        let bounds = CGRect(origin: .zero, size: output)

        context.saveGState()
        switch style.fill {
        case .none:
            break
        case .solid(let ink):
            context.setFillColor(ink.cgColor)
            context.fill(bounds)
        case .gradient(let preset):
            drawGradient(preset, in: bounds, context: context)
        case .image:
            if let backgroundImage {
                let source = CGSize(width: backgroundImage.width, height: backgroundImage.height)
                // Aspect-fill and centred, never stretched.
                let rect = Backdrop.aspectFill(source: source, in: output)
                context.saveGState()
                context.clip(to: bounds)
                drawUpright(backgroundImage, size: rect.size, in: context, at: rect.origin)
                context.restoreGState()
            }
        }
        context.restoreGState()

        guard let shadow = style.shadow else { return }
        let shorter = min(imageSize.width, imageSize.height)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: shorter * shadow.yOffsetFraction),
            blur: shorter * shadow.radiusFraction,
            color: CGColor(gray: 0, alpha: shadow.opacity)
        )
        // An opaque shape whose only visible contribution is the shadow it casts; the capture is
        // drawn over it immediately afterwards.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(
            CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        )
        context.fillPath()
        context.restoreGState()
    }

    private func drawGradient(_ preset: GradientPreset, in rect: CGRect, context: CGContext) {
        let colors = preset.stops.map(\.cgColor) as CFArray
        let locations = preset.stops.enumerated().map { index, _ in
            CGFloat(index) / CGFloat(max(1, preset.stops.count - 1))
        }
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations
            )
        else { return }
        let direction = preset.direction
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX + direction.start.x * rect.width,
                           y: rect.minY + direction.start.y * rect.height),
            end: CGPoint(x: rect.minX + direction.end.x * rect.width,
                         y: rect.minY + direction.end.y * rect.height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// Draw an image the right way up inside the y-down document space.
    ///
    /// `CGContext.draw` honours the current transform, and the context has been flipped so that
    /// document coordinates read top-left origin. Drawing an image directly into that space
    /// renders it vertically mirrored — so the flip is undone locally, for the image only. Getting
    /// this wrong is invisible on a symmetrical test image and unmistakable on a screenshot.
    private func drawUpright(
        _ image: CGImage,
        size: CGSize,
        in context: CGContext,
        at origin: CGPoint = .zero
    ) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    /// CoreText attribute keys, not AppKit's. `.font` and `.foregroundColor` are declared by
    /// AppKit/UIKit, and this module stays free of both so it can render headlessly in tests.
    private static func textAttributes(font: CTFont, color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    }

    // MARK: Elements

    private func draw(_ element: AnnotationElement, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let color = element.style.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(element.style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setAlpha(element.style.opacity)

        switch element.kind {
        case .rectangle(let rect):
            context.stroke(rect)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .line(let from, let to):
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, width: element.style.lineWidth, in: context)
        case .freehand(let points):
            stroke(points, in: context)
        case .highlight(let points):
            // Multiply blend is what makes a highlighter tint text rather than fog it. The Tauri
            // version used plain source-over at 35% alpha, which greyed out whatever it covered.
            context.setBlendMode(.multiply)
            context.setLineWidth(element.style.lineWidth * 6)
            context.setAlpha(element.style.opacity * 0.4)
            stroke(points, in: context)
        case .text(let content):
            draw(content, color: color, in: context)
        case .step(let center, let number):
            draw(step: number, at: center, color: color, in: context)
        case .pixelate, .blur:
            break // composited by EffectsCache
        }
    }

    private func stroke(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    /// Arrow with a filled head.
    ///
    /// The shaft stops short of the tip by the head's height, so the stroke does not poke through
    /// the point — the Tauri arrow ran the shaft to the exact tip and drew the head as two open
    /// strokes, which showed at larger widths.
    private func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, in context: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(12, width * 4)
        let headWidth = headLength * 0.8
        let shaftEnd = CGPoint(
            x: to.x - cos(angle) * headLength * 0.85,
            y: to.y - sin(angle) * headLength * 0.85
        )

        context.move(to: from)
        context.addLine(to: shaftEnd)
        context.strokePath()

        context.move(to: to)
        context.addLine(to: CGPoint(
            x: to.x - cos(angle - .pi / 7) * headLength,
            y: to.y - sin(angle - .pi / 7) * headLength
        ))
        context.addLine(to: CGPoint(
            x: to.x - cos(angle + .pi / 7) * headLength,
            y: to.y - sin(angle + .pi / 7) * headLength
        ))
        context.closePath()
        context.fillPath()
        _ = headWidth
    }

    private func draw(step number: Int, at center: CGPoint, color: CGColor, in context: CGContext) {
        let radius = AnnotationElement.stepRadius
        context.fillEllipse(
            in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        )

        let text = "\(number)"
        let font = CTFontCreateWithName("SFPro-Semibold" as CFString, radius * 1.15, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: Self.textAttributes(font: font, color: CGColor(gray: 1, alpha: 1))
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        context.saveGState()
        // Text is drawn in a flipped context, so undo the flip locally or the digits render
        // upside down.
        context.translateBy(x: center.x - bounds.width / 2 - bounds.minX,
                            y: center.y + bounds.height / 2)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func draw(_ content: AnnotationElement.TextContent, color: CGColor, in context: CGContext) {
        guard !content.string.isEmpty else { return }
        let font = CTFontCreateWithName("SFPro-Semibold" as CFString, content.fontSize, nil)
        let attributed = NSAttributedString(
            string: content.string,
            attributes: Self.textAttributes(font: font, color: color)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let ascent = CTFontGetAscent(font)

        context.saveGState()
        // origin is the top-left of the text box; CoreText draws from the baseline.
        context.translateBy(x: content.origin.x, y: content.origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
