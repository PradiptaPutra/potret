import CoreGraphics
import Darwin
import Foundation
import PotretCore
import ScreenCaptureKit

/// Anything that can turn a `CaptureTarget` into an image.
///
/// A protocol rather than a concrete type so the UI can be driven by a fake in development and in
/// tests — capturing for real needs a display and a TCC grant, neither of which exists in CI.
public protocol CaptureEngine: Sendable {
    func capture(_ target: CaptureTarget) async throws -> CapturedImage
    /// Displays currently attached, in global AppKit coordinates.
    func displays() async throws -> [DisplayInfo]
    /// On-screen windows belonging to other apps, front to back.
    func windows() async throws -> [WindowInfo]
}

public struct DisplayInfo: Sendable, Equatable {
    public let id: CGDirectDisplayID
    /// Global AppKit coordinates: bottom-left origin, y up.
    public let frame: CGRect
    public let scale: CGFloat

    public init(id: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

public struct WindowInfo: Sendable, Equatable {
    public let id: CGWindowID
    public let frame: CGRect
    public let title: String
    public let owningApplication: String

    public init(id: CGWindowID, frame: CGRect, title: String, owningApplication: String) {
        self.id = id
        self.frame = frame
        self.title = title
        self.owningApplication = owningApplication
    }
}

/// ScreenCaptureKit implementation.
///
/// `SCScreenshotManager.captureImage` hands back a `CGImage` directly — no stream, no frame
/// callback, no temp file, no polling. That single call replaces the Tauri pipeline's
/// `screencapture` subprocess, its temp-file existence poll, its 10ms compositor sleep and its
/// 24ms hide-the-main-window-first delay.
public struct ScreenCaptureKitEngine: CaptureEngine {
    /// Whether the pointer is burned into the capture.
    public var showsCursor: Bool

    public init(showsCursor: Bool = false) {
        self.showsCursor = showsCursor
    }

    // MARK: Content

    /// Everything shareable, minus our own windows.
    ///
    /// Excluding by `processID == getpid()` is the structural fix for self-capture: the selector
    /// scrim, the Quick Access popup, the corner panel and any pinned windows simply are not in
    /// the frame. The Tauri app instead hid its main window and slept 24ms hoping the compositor
    /// had caught up — a race it sometimes lost.
    private func shareableContent() async throws -> SCShareableContent {
        guard CapturePermission.isGranted else { throw CaptureError.permissionDenied }
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.captureFailed(error)
        }
    }

    private func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let me = getpid()
        return content.windows.filter { $0.owningApplication?.processID == me }
    }

    public func displays() async throws -> [DisplayInfo] {
        let content = try await shareableContent()
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        return content.displays.map {
            DisplayInfo(
                id: $0.displayID,
                frame: $0.frame,
                scale: scaleFactor(for: $0)
            )
        }
    }

    public func windows() async throws -> [WindowInfo] {
        let content = try await shareableContent()
        let me = getpid()
        return content.windows.compactMap { window in
            guard let app = window.owningApplication, app.processID != me else { return nil }
            // Menu-bar extras and other 1pt chrome are not things a user means to capture.
            guard window.frame.width > 40, window.frame.height > 40 else { return nil }
            return WindowInfo(
                id: window.windowID,
                frame: window.frame,
                title: window.title ?? "",
                owningApplication: app.applicationName
            )
        }
    }

    /// SCDisplay reports its size in points; CGDisplayMode reports pixels. Their ratio is the
    /// backing scale, and there is no direct `scaleFactor` on SCDisplay to ask for it.
    private func scaleFactor(for display: SCDisplay) -> CGFloat {
        guard
            let mode = CGDisplayCopyDisplayMode(display.displayID),
            display.width > 0
        else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(display.width)
    }

    // MARK: Capture

    public func capture(_ target: CaptureTarget) async throws -> CapturedImage {
        let content = try await shareableContent()
        let excluded = ownWindows(in: content)

        switch target {
        case .display(let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.displayNotFound }
            let scale = scaleFactor(for: display)
            let configuration = baseConfiguration()
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            return try await capture(filter: filter, configuration: configuration, scale: scale)

        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID })
            else { throw CaptureError.windowNotFound }
            let scale = displayScale(containing: window.frame, in: content)
            let configuration = baseConfiguration()
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return try await capture(filter: filter, configuration: configuration, scale: scale)

        case .region(let globalRect, let displayID):
            guard globalRect.width >= 1, globalRect.height >= 1 else {
                throw CaptureError.emptyRegion
            }
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.displayNotFound }
            let scale = scaleFactor(for: display)

            // sourceRect is display-local with a TOP-LEFT origin, while the selection arrives in
            // AppKit's global bottom-left space. This flip is the one that is invisible on a
            // single display and wrong on every other arrangement.
            let local = CoordinateSpace.displayLocal(
                globalRect: globalRect,
                displayFrame: display.frame
            )
            let configuration = baseConfiguration()
            configuration.sourceRect = local
            configuration.width = Int((local.width * scale).rounded())
            configuration.height = Int((local.height * scale).rounded())
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            return try await capture(filter: filter, configuration: configuration, scale: scale)
        }
    }

    private func capture(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        scale: CGFloat
    ) async throws -> CapturedImage {
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return CapturedImage(cgImage: image, scale: scale)
        } catch {
            throw CaptureError.captureFailed(error)
        }
    }

    private func baseConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        // Pin the colour space. Without this an HDR/EDR display can hand back a frame whose PNG
        // looks washed out or oversaturated in other apps.
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    private func displayScale(containing frame: CGRect, in content: SCShareableContent) -> CGFloat {
        let frames = content.displays.map(\.frame)
        guard let index = CoordinateSpace.dominantDisplay(for: frame, among: frames) else {
            return content.displays.first.map(scaleFactor(for:)) ?? 1
        }
        return scaleFactor(for: content.displays[index])
    }
}
