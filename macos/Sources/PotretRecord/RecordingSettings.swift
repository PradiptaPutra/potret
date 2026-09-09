import CoreGraphics
import Foundation
import PotretCore

/// What to record and how.
public struct RecordingSettings: Equatable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        case standard
        case high

        /// Bits per second per megapixel, applied to the actual output size.
        var bitrateScale: Double {
            switch self {
            case .standard: 4_000_000
            case .high: 9_000_000
            }
        }
    }

    public var frameRate: Int
    public var quality: Quality
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var showsCursor: Bool
    /// Composite a ring into the frame wherever the user clicks. The difference between a demo a
    /// viewer can follow and one where things change for no visible reason.
    public var highlightsClicks: Bool

    public init(
        frameRate: Int = 30,
        quality: Quality = .standard,
        capturesSystemAudio: Bool = true,
        capturesMicrophone: Bool = false,
        showsCursor: Bool = true,
        highlightsClicks: Bool = false
    ) {
        self.frameRate = frameRate
        self.quality = quality
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.showsCursor = showsCursor
        self.highlightsClicks = highlightsClicks
    }

    /// Target bitrate for an output of this pixel size.
    ///
    /// Scaled by area rather than fixed: a bitrate that looks fine for a small window turns a full
    /// 4K display to mush, and one tuned for 4K wastes an order of magnitude on a 400×300 region.
    public func bitrate(for size: CGSize) -> Int {
        let megapixels = max(0.1, (size.width * size.height) / 1_000_000)
        return Int(megapixels * quality.bitrateScale)
    }
}

/// A finished recording on disk.
public struct Recording: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let pixelSize: CGSize
    public let fileSize: Int

    public init(url: URL, duration: TimeInterval, pixelSize: CGSize, fileSize: Int) {
        self.url = url
        self.duration = duration
        self.pixelSize = pixelSize
        self.fileSize = fileSize
    }
}

public enum RecordingError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case targetUnavailable
    case writerFailed(any Error)
    case noFramesCaptured

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "There is no recording to stop."
        case .targetUnavailable: "That window or display is no longer available."
        case .writerFailed(let error): "Recording failed — \(error.localizedDescription)"
        case .noFramesCaptured: "No frames were captured."
        }
    }
}

/// Duration formatting for the HUD and the history list.
public enum DurationFormat {
    /// "0:07", "1:42", "1:02:03" — the shape a stopwatch uses.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
