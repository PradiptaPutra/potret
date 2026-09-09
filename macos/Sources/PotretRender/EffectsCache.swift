import CoreGraphics
import CoreImage
import Foundation
import PotretCore

/// Composites the pixelate and blur regions into one image, and remembers the result.
///
/// Two things this fixes from the Tauri editor:
///
///   * It ran a `getImageData` GPU-to-CPU readback **per 12px block** to sample a colour, then
///     filled that block — an O(area) loop of individual readbacks on the main thread.
///   * It re-ran that loop for every pixelate region on **every** shape mutation, because the
///     whole canvas was rebuilt from scratch whenever anything changed. Dragging an arrow across
///     a screenshot with two blurred regions re-pixelated both, every frame.
///
/// Here the work is CoreImage on the GPU, and the cache is keyed on the effect elements alone —
/// so moving an arrow, changing a colour or adding text does not invalidate it.
public final class EffectsCache {
    private struct Key: Equatable {
        let regions: [AnnotationElement]
        let sourceSize: CGSize
    }

    private var key: Key?
    private var cached: CGImage?
    private let context: CIContext

    public init() {
        // One CIContext for the life of the app. Creating one per render is the single most common
        // way to make CoreImage slow — each carries its own GPU pipeline state.
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Cache hits since creation, for the test that asserts unrelated edits do not invalidate.
    public private(set) var hits = 0
    public private(set) var misses = 0

    public func image(for document: AnnotationDocument, source: CGImage) -> CGImage? {
        let regions = document.elements.filter(\.kind.isEffect)
        guard !regions.isEmpty else { return nil }

        let candidate = Key(regions: regions, sourceSize: document.sourceSize)
        if candidate == key, let cached {
            hits += 1
            return cached
        }

        misses += 1
        let rendered = render(regions: regions, source: source)
        key = candidate
        cached = rendered
        return rendered
    }

    public func invalidate() {
        key = nil
        cached = nil
    }

    private func render(regions: [AnnotationElement], source: CGImage) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        var output = CIImage(color: .clear).cropped(to: extent)
        let input = CIImage(cgImage: source)

        for region in regions {
            guard let rect = effectRect(region, imageHeight: CGFloat(source.height)) else {
                continue
            }
            let processed: CIImage?
            switch region.kind {
            case .pixelate:
                processed = pixelate(input, rect: rect)
            case .blur:
                processed = blur(input, rect: rect)
            default:
                processed = nil
            }
            guard let processed else { continue }
            output = processed.cropped(to: rect).composited(over: output)
        }

        return context.createCGImage(output, from: extent)
    }

    /// Document space is y-down; CoreImage is y-up. Flip the region or the effect lands mirrored
    /// vertically — obvious on a tall screenshot, invisible on a square test image.
    private func effectRect(_ element: AnnotationElement, imageHeight: CGFloat) -> CGRect? {
        let rect: CGRect
        switch element.kind {
        case .pixelate(let value), .blur(let value): rect = value
        default: return nil
        }
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return CGRect(
            x: rect.minX,
            y: imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func pixelate(_ image: CIImage, rect: CGRect) -> CIImage? {
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(image, forKey: kCIInputImageKey)
        // Scaled to the region, with a floor: a fixed block size leaves a small redaction barely
        // pixelated and therefore still readable, which is the one thing this tool must not do.
        let scale = max(12, min(rect.width, rect.height) / 8)
        filter?.setValue(scale, forKey: kCIInputScaleKey)
        filter?.setValue(CIVector(x: rect.midX, y: rect.midY), forKey: kCIInputCenterKey)
        return filter?.outputImage
    }

    private func blur(_ image: CIImage, rect: CGRect) -> CIImage? {
        let filter = CIFilter(name: "CIGaussianBlur")
        // Clamping first stops the blur sampling transparent pixels beyond the image edge, which
        // would fade the result out at the borders.
        filter?.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(max(8, min(rect.width, rect.height) / 10), forKey: kCIInputRadiusKey)
        return filter?.outputImage
    }
}
