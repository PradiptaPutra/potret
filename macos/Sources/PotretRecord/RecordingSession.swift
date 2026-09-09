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

    /// Rings drawn at each click, composited into the frames. Nil unless the setting is on, so a
    /// recording without it takes exactly the path it always did.
    private var clicks: ClickHighlighter?
    /// Only needed when a ring is actually being drawn; frames otherwise go straight through as
    /// the sample buffers they arrived in.
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var compositeFailures = 0

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
            // Window frames are routinely odd-sized (a browser at 1237x811 is typical), and H.264
            // requires even dimensions — the writer accepts every frame and then fails at finish.
            // The region path already rounded; this one did not, which is why recording a window
            // failed where recording a display worked.
            size = CGSize(
                width: ((window.frame.width * scale) / 2).rounded() * 2,
                height: ((window.frame.height * scale) / 2).rounded() * 2
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

        // Where the frames sit on screen, so a click can be placed inside them. Each target
        // answers it differently, and getting it wrong puts the ring somewhere the user did not
        // click — so it is derived here, beside the filter it has to agree with.
        if settings.highlightsClicks {
            let highlighter: ClickHighlighter
            let area: (rect: CGRect, scale: CGFloat)

            switch target {
            case .display(let id):
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw RecordingError.targetUnavailable
                }
                area = (display.frame, Self.scaleFactor(for: display))
                highlighter = ClickHighlighter()

            case .region(let globalRect, let displayID):
                guard
                    let display = content.displays.first(where: { $0.displayID == displayID })
                else { throw RecordingError.targetUnavailable }
                area = (globalRect, Self.scaleFactor(for: display))
                highlighter = ClickHighlighter()

            case .window(let id):
                let scale = content.displays.first.map(Self.scaleFactor(for:)) ?? 2
                let primaryHeight = content.displays
                    .max(by: { $0.frame.height < $1.frame.height })
                    .map(\.frame.height) ?? NSScreen.main?.frame.height ?? 0
                // A window recording follows its window, so the rectangle is re-read on every
                // frame that draws a ring rather than captured once at the start — otherwise
                // moving the window puts every later click in the wrong place.
                let provider: @Sendable () -> (rect: CGRect, scale: CGFloat)? = {
                    guard let frame = Self.windowFrame(id: id, primaryHeight: primaryHeight) else {
                        return nil
                    }
                    return (frame, scale)
                }
                area = (provider()?.rect ?? .zero, scale)
                highlighter = ClickHighlighter(areaProvider: provider)
            }

            clicks = highlighter
            await MainActor.run { highlighter.start(covering: area.rect, scale: area.scale) }
        }

        try await start(filter: filter, size: size, sourceRect: sourceRect)
    }

    /// A window's current frame in global AppKit coordinates.
    ///
    /// `CGWindowListCopyWindowInfo` reports in CG global space — origin at the top-left of the
    /// primary display, y down — while clicks arrive in AppKit global space. Both are called
    /// "global coordinates" and both are in points, which is exactly how they get confused.
    private static func windowFrame(id: CGWindowID, primaryHeight: CGFloat) -> CGRect? {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow], id
            ) as? [[String: Any]],
            let bounds = list.first?[kCGWindowBounds as String] as? [String: CGFloat],
            let x = bounds["X"], let y = bounds["Y"],
            let width = bounds["Width"], let height = bounds["Height"],
            width > 0, height > 0
        else { return nil }

        return CoordinateSpace.appKitGlobal(
            cgGlobalRect: CGRect(x: x, y: y, width: width, height: height),
            primaryHeight: primaryHeight
        )
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

        // The writer is NOT created here. It is created on the first delivered frame, sized from
        // that frame's pixel buffer. Declaring the size up front from the window's frame produced
        // frames the encoder rejected (-12142, kVTParameterErr) because for window capture the
        // delivered buffer does not match the requested size exactly. Sizing from what actually
        // arrives cannot mismatch.
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writerQueue)
        if settings.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writerQueue)
        }
        try await stream.startCapture()

        self.stream = stream
        isRecording = true
        // The pointer flag is logged because it is invisible in the output until playback: a
        // recording made with the wrong setting looks fine until you watch it back.
        Log.capture.info(
            "recording started: \(Int(size.width))x\(Int(size.height)) cursor=\(self.settings.showsCursor)"
        )
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

        if let clicks {
            Log.capture.info(
                "click highlighting: \(clicks.clicksSeen) click(s), \(clicks.framesDrawn) frame(s) drawn, \(self.compositeFailures) append failure(s)"
            )
            await MainActor.run { clicks.stop() }
            self.clicks = nil
        }

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
            // "The operation could not be completed" on its own is useless; the NSError carries
            // the code and usually an underlying error that says what actually went wrong.
            let nsError = error as NSError
            Log.capture.error(
                "writer failed: \(nsError.domain, privacy: .public) \(nsError.code) \(String(describing: nsError.userInfo), privacy: .public)"
            )
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

    private func prepareWriter(size rawSize: CGSize) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // H.264 needs even dimensions. The encoder scales a buffer that is off by one pixel,
        // which is invisible; it refuses an odd declared size outright.
        let size = CGSize(
            width: (rawSize.width / 2).rounded(.down) * 2,
            height: (rawSize.height / 2).rounded(.down) * 2
        )
        pixelSize = size

        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
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
        if clicks != nil {
            // BGRA to match what SCStream delivers, so compositing never converts formats.
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: video,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(size.width),
                    kCVPixelBufferHeightKey as String: Int(size.height),
                ]
            )
        }
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

        // First usable video frame: build the writer to match it exactly.
        if writer == nil {
            guard type == .screen, isComplete(sampleBuffer),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            let actual = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
            Log.capture.info("first frame \(Int(actual.width))x\(Int(actual.height))px")
            do {
                try prepareWriter(size: actual)
            } catch {
                Log.capture.error("writer setup failed: \(error.localizedDescription, privacy: .public)")
                isRecording = false
                return
            }
        }
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

        // The ordinary path, and the only one when clicks are not being highlighted or none is
        // on screen: hand the writer the buffer exactly as it arrived. Compositing is opt-in per
        // frame rather than a stage every frame pays for.
        if composite(sampleBuffer, at: timestamp) {
            frameCount += 1
            return
        }

        videoInput.append(sampleBuffer)
        frameCount += 1
    }

    /// Draw the live click rings into a copy of the frame and write that instead.
    ///
    /// Returns false whenever the frame should be written untouched — highlighting off, nothing
    /// clicked recently, or anything at all going wrong. A ring is a nicety; dropping the frame
    /// because one could not be drawn would not be.
    private func composite(_ sampleBuffer: CMSampleBuffer, at timestamp: CMTime) -> Bool {
        guard
            let clicks, clicks.hasActiveRipples,
            let adaptor = pixelBufferAdaptor,
            let pool = adaptor.pixelBufferPool,
            let source = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return false }

        let height = CGFloat(CVPixelBufferGetHeight(source))
        guard let overlaid = clicks.overlay(on: CIImage(cvPixelBuffer: source), frameHeight: height)
        else { return false }

        var destination: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
            let destination
        else { return false }

        clicks.render(overlaid, to: destination)
        let appended = adaptor.append(destination, withPresentationTime: timestamp)
        if !appended { compositeFailures += 1 }
        return appended
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
