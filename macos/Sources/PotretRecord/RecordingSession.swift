import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import PotretCapture
import PotretCore
import ScreenCaptureKit

/// One recording, from start to finished file.
///
/// `SCStream` delivers `CMSampleBuffer`s; `AVAssetWriter` consumes them. Frames are written
/// straight through to a temp file rather than buffered, so a crash costs the tail of the
/// recording rather than all of it.
///
/// Timing comes from the sample buffers' own presentation timestamps, never from wall clock.
/// Video and system audio arrive as separate streams, and driving the writer from `Date()` makes
/// them drift apart over a long take — audible within a couple of minutes.
public final class RecordingSession: NSObject, @unchecked Sendable {
    public private(set) var isRecording = false
    public private(set) var isPaused = false

    private let settings: RecordingSettings
    private let outputURL: URL
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    /// Serial queue for everything writer-related. Sample buffers arrive on SCStream's queue, and
    /// AVAssetWriterInput is not safe to append to from more than one.
    private let writerQueue = DispatchQueue(label: "com.potret.app.recording.writer")

    private var sessionStart: CMTime?
    private var lastVideoTime: CMTime?
    /// Total time spent paused, subtracted so the finished file has no dead air.
    private var pausedDuration: CMTime = .zero
    private var pauseStarted: CMTime?
    private var pixelSize: CGSize = .zero
    private var frameCount = 0

    public init(settings: RecordingSettings, outputURL: URL? = nil) {
        self.settings = settings
        self.outputURL = outputURL
            ?? URL.temporaryDirectory.appending(path: "potret-recording-\(UUID().uuidString).mp4")
        super.init()
    }

    // MARK: Lifecycle

    /// Build the filter here rather than taking one.
    ///
    /// `SCContentFilter` is not Sendable, so passing one in from the main actor is a data race the
    /// compiler rejects. `CaptureTarget` is a plain value, so the target crosses the boundary and
    /// the filter is constructed on this side.
    public func start(target: CaptureTarget, excludingOwnWindows: Bool = true) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        let ours = excludingOwnWindows
            ? content.windows.filter { $0.owningApplication?.processID == getpid() }
            : []

        let filter: SCContentFilter
        let size: CGSize
        var sourceRect: CGRect?

        switch target {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingError.targetUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: ours)
            let scale = Self.scaleFactor(for: display)
            size = CGSize(
                width: (CGFloat(display.width) * scale).rounded(),
                height: (CGFloat(display.height) * scale).rounded()
            )

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingError.targetUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = content.displays.first.map(Self.scaleFactor(for:)) ?? 2
            size = CGSize(
                width: (window.frame.width * scale).rounded(),
                height: (window.frame.height * scale).rounded()
            )

        case .region(let globalRect, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecordingError.targetUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: ours)
            let scale = Self.scaleFactor(for: display)
            let local = CoordinateSpace.displayLocal(
                globalRect: globalRect, displayFrame: display.frame
            )
            sourceRect = local
            // H.264 requires even dimensions; an odd width silently produces a distorted file.
            size = CGSize(
                width: ((local.width * scale) / 2).rounded() * 2,
                height: ((local.height * scale) / 2).rounded() * 2
            )
        }

        try await start(filter: filter, size: size, sourceRect: sourceRect)
    }

    private static func scaleFactor(for display: SCDisplay) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(display.displayID), display.width > 0 else {
            return 1
        }
        return CGFloat(mode.pixelWidth) / CGFloat(display.width)
    }

    private func start(filter: SCContentFilter, size: CGSize, sourceRect: CGRect?) async throws {
        pixelSize = size

        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        configuration.showsCursor = settings.showsCursor
        configuration.colorSpaceName = CGColorSpace.sRGB
        // Room for the writer to fall behind briefly without SCStream dropping frames outright.
        configuration.queueDepth = 6
        if let sourceRect {
            // Crop at the source rather than recording the whole display and trimming later: it
            // keeps the file at the size the user asked for and avoids encoding pixels nobody
            // wants.
            configuration.sourceRect = sourceRect
        }
        configuration.capturesAudio = settings.capturesSystemAudio
        if settings.capturesSystemAudio {
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
        }

        try prepareWriter(size: size)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writerQueue)
        if settings.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writerQueue)
        }
        try await stream.startCapture()

        self.stream = stream
        isRecording = true
        Log.capture.info("recording started: \(Int(size.width))x\(Int(size.height))")
    }

    public func pause() {
        writerQueue.sync {
            guard isRecording, !isPaused else { return }
            isPaused = true
            pauseStarted = lastVideoTime
        }
    }

    public func resume() {
        writerQueue.sync {
            guard isRecording, isPaused else { return }
            isPaused = false
            if let pauseStarted, let lastVideoTime {
                // Fold the paused span into the running offset so the output has no dead air and
                // audio stays aligned with the picture.
                pausedDuration = CMTimeAdd(
                    pausedDuration, CMTimeSubtract(lastVideoTime, pauseStarted)
                )
            }
            pauseStarted = nil
        }
    }

    /// Stop and finalise. Always returns the file if any frames were written.
    public func stop() async throws -> Recording {
        guard isRecording else { throw RecordingError.notRecording }
        isRecording = false

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        let (writer, videoInput, audioInput) = writerQueue.sync {
            (self.writer, self.videoInput, self.audioInput)
        }
        guard let writer else { throw RecordingError.noFramesCaptured }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()

        if let error = writer.error {
            throw RecordingError.writerFailed(error)
        }
        guard frameCount > 0 else { throw RecordingError.noFramesCaptured }

        let asset = AVURLAsset(url: outputURL)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attributes?[.size] as? Int) ?? 0

        Log.capture.info("recording stopped: \(String(format: "%.1f", duration))s, \(self.frameCount) frames")
        return Recording(
            url: outputURL,
            duration: duration,
            pixelSize: pixelSize,
            fileSize: fileSize
        )
    }

    // MARK: Writer

    private func prepareWriter(size: CGSize) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.bitrate(for: size),
                    AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                    // Two seconds between keyframes: scrubbing and trimming stay responsive
                    // without inflating the file the way an all-keyframe stream would.
                    AVVideoMaxKeyFrameIntervalDurationKey: 2,
                ],
            ]
        )
        // The writer must never block the stream's delivery queue.
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecordingError.noFramesCaptured }
        writer.add(video)

        var audio: AVAssetWriterInput?
        if settings.capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ]
            )
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }

        writer.startWriting()
        self.writer = writer
        videoInput = video
        audioInput = audio
    }
}

// MARK: - Stream output

extension RecordingSession: SCStreamOutput, SCStreamDelegate {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard isRecording, !isPaused, sampleBuffer.isValid else { return }
        guard let writer, writer.status == .writing || writer.status == .unknown else { return }

        switch type {
        case .screen:
            // SCStream sends frames even when nothing changed, flagged as such. Writing those
            // wastes bitrate on identical pictures.
            guard isComplete(sampleBuffer) else { return }
            appendVideo(sampleBuffer, to: writer)
        case .audio:
            appendAudio(sampleBuffer)
        default:
            break
        }
    }

    /// SCStream marks each frame with a status; only `.complete` carries new pixels.
    private func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, to writer: AVAssetWriter) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if sessionStart == nil {
            sessionStart = timestamp
            writer.startSession(atSourceTime: timestamp)
        }
        lastVideoTime = timestamp

        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
        frameCount += 1
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // Audio before the first video frame has nowhere to sit — the session has not started.
        guard sessionStart != nil, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Log.capture.error("recording stream stopped: \(error.localizedDescription, privacy: .public)")
        isRecording = false
    }
}
