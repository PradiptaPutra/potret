import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PotretCore
import UniformTypeIdentifiers

/// Post-recording operations: poster frames, trimming, GIF export.
public enum VideoTools {
    /// A frame to represent the recording in history.
    ///
    /// Taken a little way in rather than at zero: the first frame of a screen recording is often
    /// the moment before anything happened — a menu still closing, or the selector fading out.
    public static func posterFrame(
        for url: URL,
        at seconds: TimeInterval = 0.5
    ) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let duration = try await asset.load(.duration).seconds
        let time = CMTime(seconds: min(seconds, max(0, duration - 0.1)), preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        return image
    }

    /// Write a trimmed copy.
    ///
    /// Passthrough preset: trimming re-muxes rather than re-encodes, so it is fast and loses
    /// nothing. Cuts land on keyframes, which is why the recorder asks for one every two seconds.
    public static func trim(
        _ url: URL,
        from start: TimeInterval,
        to end: TimeInterval,
        to outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard
            let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw RecordingError.writerFailed(
                NSError(domain: "Potret", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create an export session.",
                ])
            )
        }

        try? FileManager.default.removeItem(at: outputURL)
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        try await session.export(to: outputURL, as: .mp4)
    }

    /// Export a range as an animated GIF.
    ///
    /// GIFs grow fast, so both the frame rate and the width are reduced by default, and the caller
    /// is expected to show the estimate below before writing.
    public static func exportGIF(
        _ url: URL,
        from start: TimeInterval,
        to end: TimeInterval,
        frameRate: Double = 15,
        maximumWidth: CGFloat = 640,
        to outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumWidth, height: 0)
        // Frames are sampled on a fixed cadence, so tolerance has to be tight or several requests
        // return the same frame and the GIF stutters.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frameCount = max(1, Int((end - start) * frameRate))
        let times = (0..<frameCount).map { index in
            CMTime(seconds: start + Double(index) / frameRate, preferredTimescale: 600)
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard
            let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
            )
        else {
            throw RecordingError.writerFailed(
                NSError(domain: "Potret", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create the GIF file.",
                ])
            )
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / frameRate],
        ] as CFDictionary

        for time in times {
            guard let (image, _) = try? await generator.image(at: time) else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw RecordingError.writerFailed(
                NSError(domain: "Potret", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not finish writing the GIF.",
                ])
            )
        }
    }

    /// Rough size of a GIF before writing it.
    ///
    /// GIFs get enormous quickly and there is no way to know until it is written, so an estimate
    /// shown next to the button is the difference between an informed choice and a surprise.
    public static func estimatedGIFBytes(
        duration: TimeInterval,
        frameRate: Double,
        width: CGFloat,
        height: CGFloat
    ) -> Int {
        // Empirical: screen content palettises well, landing near 0.12 bytes per pixel per frame.
        let frames = max(1, duration * frameRate)
        return Int(frames * width * height * 0.12)
    }
}
