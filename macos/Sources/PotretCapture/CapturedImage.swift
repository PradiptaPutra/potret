import CoreGraphics
import Foundation
import PotretCore

/// A captured frame, with the metadata needed to save or describe it.
///
/// `CGImage` is a reference type that CoreGraphics does not annotate as `Sendable`, but it is
/// immutable once created and is only ever read after capture — so this is safe to hand across
/// actors. The `@unchecked` is doing real work and is deliberately narrow: it applies to this
/// wrapper, not to CGImage generally.
public struct CapturedImage: @unchecked Sendable {
    public let cgImage: CGImage
    /// Backing scale of the display it came from, so a Retina capture can be described in points.
    public let scale: CGFloat

    public init(cgImage: CGImage, scale: CGFloat) {
        self.cgImage = cgImage
        self.scale = scale
    }

    public var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    public var pointSize: CGSize {
        CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
    }

    /// A region of a whole-display capture, addressed the way a live region capture is: a rect
    /// in global AppKit coordinates plus the display's frame. This is what a frozen-screen
    /// capture crops from, so it goes through the same flip as `CaptureTarget.region`.
    public func cropped(toGlobalRect rect: CGRect, displayFrame: CGRect) -> CapturedImage? {
        let local = CoordinateSpace.displayLocal(globalRect: rect, displayFrame: displayFrame)
        let pixels = CoordinateSpace.pixels(from: local, scale: scale).integral
        guard let image = cgImage.cropping(to: pixels) else { return nil }
        return CapturedImage(cgImage: image, scale: scale)
    }
}

public enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplays
    case displayNotFound
    case windowNotFound
    case emptyRegion
    case captureFailed(any Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Potret needs Screen Recording permission. Grant it in System Settings, then relaunch."
        case .noDisplays:
            "No displays were available to capture."
        case .displayNotFound:
            "That display is no longer connected."
        case .windowNotFound:
            "That window has closed."
        case .emptyRegion:
            "The selected region was empty."
        case .captureFailed(let underlying):
            "Capture failed — \(underlying.localizedDescription)"
        }
    }
}
