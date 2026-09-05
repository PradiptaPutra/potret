import CoreGraphics
import Foundation
import ImageIO
import PotretCore
import UniformTypeIdentifiers

/// Encodes a captured frame to PNG or JPEG, and builds thumbnails.
///
/// All of this goes through ImageIO rather than NSBitmapImageRep so it stays free of AppKit and
/// can run off the main actor.
public enum ImageEncoder: Sendable {
    public enum EncodeError: Error {
        case destinationUnavailable
        case writeFailed
        case decodeFailed
    }

    public static func encode(
        _ image: CGImage,
        format: AppConfig.ImageFormat,
        quality: Int
    ) throws -> Data {
        let data = NSMutableData()
        let type: UTType = format == .png ? .png : .jpeg
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                type.identifier as CFString,
                1,
                nil
            )
        else { throw EncodeError.destinationUnavailable }

        var options: [CFString: Any] = [:]
        if format == .jpg {
            // JPEG has no alpha; ImageIO composites onto black rather than white, so anything
            // transparent would come out dark. Captures are opaque, but annotation exports may
            // not be — the render layer flattens onto white before it gets here.
            options[kCGImageDestinationLossyCompressionQuality] =
                Double(min(max(quality, 1), 100)) / 100.0
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodeError.writeFailed }
        return data as Data
    }

    /// Downscaled preview.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` uses the hardware path and decodes only what it
    /// needs, so it is markedly cheaper than decoding the full image and resampling — which is
    /// what the Tauri backend did for every history row.
    public static func thumbnail(from data: Data, maxPixelSize: Int = 640) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw EncodeError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw EncodeError.decodeFailed }
        return thumbnail
    }

    /// Pixel dimensions without decoding the image.
    public static func pixelSize(of data: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
