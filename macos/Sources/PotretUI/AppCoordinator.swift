import AppKit
import PotretCapture
import PotretCore
import SwiftUI

/// Wires the pieces together: hotkeys and menu in, capture out, popup and history after.
///
/// Deliberately the only object that knows about all of them. Everything it touches — the engine,
/// the stores, the panel controller — is independently testable or swappable, so this stays thin.
@MainActor
public final class AppCoordinator {
    private let engine: any CaptureEngine
    private let configStore: ConfigStore
    private let historyStore: HistoryStore
    private let popup = CapturePopupController()
    private let hotKeys = HotKeyCenter()

    /// Guards against a hotkey that repeats or a menu item double-firing. Matches the Tauri app's
    /// 500ms, which existed for the same reason.
    private static let captureDebounce: TimeInterval = 0.5
    private var lastCaptureAt: Date = .distantPast

    public init(
        engine: any CaptureEngine = ScreenCaptureKitEngine(),
        bundleID: String
    ) {
        self.engine = engine
        self.configStore = ConfigStore(fileURL: AppIdentity.configFile(bundleID: bundleID))
        self.historyStore = HistoryStore(directory: AppIdentity.historyDirectory(bundleID: bundleID))
    }

    // MARK: Lifecycle

    public func start() async {
        // A development build starts from the released app's settings, so dogfooding does not mean
        // reconfiguring from scratch.
        await configStore.importIfEmpty(from: AppIdentity.configFile())

        let config = await configStore.current
        let (combos, failed) = LegacyShortcutMigration.migrate(config)
        if !failed.isEmpty {
            // Shortcuts the old string format could not express. They have been replaced with
            // working defaults; the user is told rather than left with a dead key.
            let names = failed.map(\.label).joined(separator: ", ")
            NSLog("[potret] replaced unusable shortcuts: \(names)")
        }

        hotKeys.onTrigger { [weak self] id in
            self?.handle(id)
        }
        hotKeys.apply(combos)

        // Retention runs at launch as well as after each save: the Tauri app kept every capture
        // forever while showing only the newest 50, so an upgrading user may arrive with a large
        // backlog to trim once.
        _ = try? historyStore.prune(policy: RetentionPolicy())
    }

    public func shutdown() {
        hotKeys.shutdown()
        Task { await configStore.flush() }
    }

    public var shortcutFailures: [ShortcutID: HotKeyError] { hotKeys.failures }

    // MARK: Capture

    private func handle(_ id: ShortcutID) {
        switch id {
        case .captureFullscreen: capture(.fullscreen)
        case .captureWindow: capture(.window)
        case .captureArea: capture(.area)
        case .recentCaptures: break // history panel lands with the rest of Phase 2
        }
    }

    public enum CaptureMode {
        case fullscreen
        case window
        case area
    }

    public func capture(_ mode: CaptureMode) {
        guard Date().timeIntervalSince(lastCaptureAt) > Self.captureDebounce else { return }
        lastCaptureAt = Date()

        guard CapturePermission.isGranted else {
            presentPermissionAlert()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let target = try await self.target(for: mode) else { return }
                let captured = try await self.engine.capture(target)
                try await self.finish(captured)
            } catch {
                self.present(error: error)
            }
        }
    }

    private func target(for mode: CaptureMode) async throws -> CaptureTarget? {
        let displays = try await engine.displays()
        guard !displays.isEmpty else { throw CaptureError.noDisplays }

        // The display under the pointer, so a capture lands on the screen being used rather than
        // always the primary one.
        let pointer = NSEvent.mouseLocation
        let active = displays.first { $0.frame.contains(pointer) } ?? displays[0]

        switch mode {
        case .fullscreen:
            return .display(active.id)
        case .window, .area:
            // Window picking and the region selector arrive with the rest of Phase 1; falling back
            // to the full display is a placeholder, not the shipped behaviour.
            return .display(active.id)
        }
    }

    /// Persist, then show the popup.
    private func finish(_ captured: CapturedImage) async throws {
        // History is always PNG regardless of the export format, so an annotated re-edit never
        // compounds JPEG artefacts.
        let png = try ImageEncoder.encode(captured.cgImage, format: .png, quality: 100)
        let thumbnailImage = try ImageEncoder.thumbnail(from: png)
        let thumbnail = try ImageEncoder.encode(thumbnailImage, format: .png, quality: 100)

        _ = try historyStore.save(
            imageData: png,
            thumbnailData: thumbnail,
            pixelSize: captured.pixelSize
        )
        _ = try? historyStore.prune(policy: RetentionPolicy())

        var actions = CapturePopupActions()
        actions.copy = { [weak self] in
            ClipboardWriter.write(captured.cgImage)
            self?.popup.flash("Copied")
        }
        actions.save = { [weak self] in
            guard let self else { return }
            Task { await self.save(captured) }
        }

        popup.present(
            image: NSImage(cgImage: captured.cgImage, size: captured.pointSize),
            pixelSize: captured.pixelSize,
            actions: actions
        )
    }

    private func save(_ captured: CapturedImage) async {
        let config = await configStore.current
        do {
            let data = try ImageEncoder.encode(
                captured.cgImage,
                format: config.format,
                quality: config.clampedJPEGQuality
            )
            let directory = config.saveDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = FilenameTemplate(config.filenameTemplate).uniqueURL(
                in: directory,
                ext: config.format.rawValue
            )
            try data.write(to: url, options: .atomic)
            // Name the folder, not the full path — the Tauri app put a raw absolute path in a
            // toast, which was unreadable at popup width.
            popup.flash("Saved to \(directory.lastPathComponent)")
        } catch {
            popup.flash("Couldn't save")
            NSLog("[potret] save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Errors

    private func present(error: any Error) {
        popup.dismiss()
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = (error as? CaptureError)?.errorDescription
            ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Potret needs Screen Recording permission"
        alert.informativeText = """
            Grant it in System Settings › Privacy & Security › Screen Recording, \
            then quit and reopen Potret.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            CapturePermission.request()
            NSWorkspace.shared.open(CapturePermission.settingsURL)
        }
    }
}
