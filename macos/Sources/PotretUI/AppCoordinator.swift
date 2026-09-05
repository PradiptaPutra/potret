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
    private let selector = SelectorCoordinator()
    private let windowPicker = WindowPickerCoordinator()
    private let historyModel: HistoryModel
    private let historyPanel: HistoryPanelController
    /// Set by the app delegate so the history panel can anchor under the menu-bar item.
    public weak var statusButton: NSStatusBarButton?
    private let cornerHover: CornerHoverController
    private var pinned: PinnedController!
    /// Latest settings, for paths that must answer synchronously (a drag cannot await).
    private var cachedConfig: AppConfig = .default
    private var settingsModel: SettingsModel?
    private var settingsWindow: MainWindowController?
    private var editorWindow: MainWindowController?
    private var editorModel: EditorModel?

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
        let store = HistoryStore(directory: AppIdentity.historyDirectory(bundleID: bundleID))
        self.historyStore = store

        let model = HistoryModel(store: store)
        self.historyModel = model

        var actions = HistoryActions()
        actions.copy = { item in
            guard let image = NSImage(contentsOf: item.imageURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return }
            ClipboardWriter.write(cgImage)
        }
        actions.reveal = { item in
            NSWorkspace.shared.activateFileViewerSelecting([item.imageURL])
        }
        actions.delete = { [weak model] item in model?.delete(item) }
        actions.clearAll = { [weak model] in model?.clearAll() }
        self.historyPanel = HistoryPanelController(model: model, actions: actions)
        self.cornerHover = CornerHoverController(model: model, actions: actions)

        self.pinned = PinnedController { [weak self] image, size in
            self?.openEditor(source: image, pixelSize: size)
        }

        // annotate and dragURL need `self`, so they are attached once initialisation is complete.
        var full = actions
        full.annotate = { [weak self] item in self?.openEditor(for: item) }
        full.dragURL = { [weak self] item in self?.stageForDrag(item) }
        historyPanel.updateActions(full)
        cornerHover.updateActions(full)
    }

    /// Open a stored capture in the editor.
    private func openEditor(for item: HistoryItem) {
        guard
            let image = NSImage(contentsOf: item.imageURL),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            Log.ui.error("could not open capture for editing")
            return
        }
        historyPanel.hide()
        openEditor(source: cgImage, pixelSize: item.pixelSize)
    }

    /// Stage an in-memory capture for dragging, under the user's filename template.
    private func stageForDrag(image: CGImage) -> URL? {
        do {
            let data = try ImageEncoder.encode(image, format: .png, quality: 100)
            let directory = DragStaging.directory
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = DragStaging.name(
                for: FilenameTemplate(cachedConfig.filenameTemplate), ext: "png"
            )
            let url = directory.appending(path: name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.ui.error("staging drag failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Copy a capture under its templated name so the drag carries a readable filename.
    private func stageForDrag(_ item: HistoryItem) -> URL? {
        let template = FilenameTemplate(cachedConfig.filenameTemplate)
        let name = DragStaging.name(
            for: template,
            ext: item.imageURL.pathExtension.isEmpty ? "png" : item.imageURL.pathExtension
        )
        return DragStaging.stage(source: item.imageURL, name: name)
    }

    /// Capture the screen and open the editor on it directly — verification path.
    public func captureAndEdit() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let displays = try await self.engine.displays()
                guard let display = displays.first else { return }
                let captured = try await self.engine.capture(.display(display.id))
                Log.ui.info("captureAndEdit: captured, opening editor")
                self.openEditor(source: captured.cgImage, pixelSize: captured.pixelSize)
            } catch {
                Log.capture.error("captureAndEdit failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Open the annotation editor on a captured image.
    public func openEditor(source: CGImage, pixelSize: CGSize) {
        let model = EditorModel(
            document: AnnotationDocument(sourceSize: pixelSize),
            source: source
        ) { [weak self] rendered in
            self?.finishEditing(rendered)
        }
        editorModel = model
        // A fresh window per session: the document is per-capture, and reusing one would carry the
        // previous capture's undo stack into the next. The Tauri editor keyed its React component
        // on the capture id for exactly this reason (issue #5, annotations bleeding between
        // screenshots).
        editorWindow = MainWindowController(
            title: "Annotate",
            // Big enough to show a capture at a useful size without immediately needing a resize.
            defaultSize: NSSize(width: 1000, height: 700),
            resizable: true
        ) {
            EditorView(model: model)
        }
        editorWindow?.show()
        Log.ui.info("editor window shown")
    }

    private func finishEditing(_ image: CGImage) {
        Task { [weak self] in
            guard let self else { return }
            let config = await self.configStore.current
            do {
                let png = try ImageEncoder.encode(image, format: .png, quality: 100)
                let thumbnailImage = try ImageEncoder.thumbnail(from: png)
                let thumbnail = try ImageEncoder.encode(thumbnailImage, format: .png, quality: 100)
                _ = try self.historyStore.save(
                    imageData: png,
                    thumbnailData: thumbnail,
                    pixelSize: CGSize(width: image.width, height: image.height)
                )
                let data = try ImageEncoder.encode(
                    image, format: config.format, quality: config.clampedJPEGQuality
                )
                let directory = config.saveDirectory
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let url = FilenameTemplate(config.filenameTemplate).uniqueURL(
                    in: directory, ext: config.format.rawValue
                )
                try data.write(to: url, options: .atomic)
                Log.ui.info("annotated capture saved")
            } catch {
                Log.ui.error("saving annotation failed: \(error.localizedDescription, privacy: .public)")
            }
            self.editorWindow?.close()
            self.editorWindow = nil
            self.editorModel = nil
        }
    }

    /// Force the corner stack open — verification only; the real trigger is the corner hot zone.
    public func showCornerStack() {
        cornerHover.showNow()
    }

    /// Open Settings, creating it on first use.
    public func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(
                configStore: configStore,
                historyStore: historyStore,
                applyShortcuts: { [weak self] combos in
                    guard let self else { return [:] }
                    self.hotKeys.apply(combos)
                    return self.hotKeys.failures
                }
            )
            settingsModel = model
            settingsWindow = MainWindowController(title: "Potret Settings") {
                SettingsView(model: model)
            }
        }
        settingsModel?.shortcutFailures = hotKeys.failures
        settingsWindow?.show()
    }

    /// Show or hide the Recent Captures panel.
    public func toggleHistory() {
        historyPanel.toggle(relativeTo: statusButton)
    }

    // MARK: Lifecycle

    public func start() async {
        // A development build starts from the released app's settings, so dogfooding does not mean
        // reconfiguring from scratch.
        await configStore.importIfEmpty(from: AppIdentity.configFile())

        let config = await configStore.current
        cachedConfig = config
        let (combos, failed) = LegacyShortcutMigration.migrate(config)
        if !failed.isEmpty {
            // Shortcuts the old string format could not express. They have been replaced with
            // working defaults; the user is told rather than left with a dead key.
            let names = failed.map(\.label).joined(separator: ", ")
            NSLog("[potret] replaced unusable shortcuts: \(names)")
        }

        hotKeys.onTrigger { [weak self] id in
            Log.shortcuts.info("hotkey fired: \(id.rawValue, privacy: .public)")
            self?.handle(id)
        }
        let results = hotKeys.apply(combos)
        for (id, result) in results {
            switch result {
            case .success:
                Log.shortcuts.info(
                    "registered \(id.rawValue, privacy: .public) as \(combos[id]?.displayString ?? "?", privacy: .public)"
                )
            case .failure(let error):
                Log.shortcuts.error(
                    "could NOT register \(id.rawValue, privacy: .public): \(error.message, privacy: .public)"
                )
            }
        }

        // The empty state names the user's own shortcut rather than a hardcoded default.
        historyPanel.setCaptureHint(combos[.captureFullscreen]?.displayString)

        cornerHover.isEnabled = config.cornerPopupEnabled
        cornerHover.install()

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
        case .recentCaptures: toggleHistory()
        }
    }

    public enum CaptureMode {
        case fullscreen
        case window
        case area
    }

    public func capture(_ mode: CaptureMode) {
        Log.capture.info("capture requested: \(String(describing: mode), privacy: .public)")

        guard Date().timeIntervalSince(lastCaptureAt) > Self.captureDebounce else {
            Log.capture.info("ignored — within the \(Self.captureDebounce)s debounce")
            return
        }
        lastCaptureAt = Date()

        guard CapturePermission.isGranted else {
            Log.capture.error("Screen Recording not granted for this bundle")
            presentPermissionAlert()
            return
        }

        switch mode {
        case .area:
            beginAreaSelection()
        case .window:
            beginWindowPicking()
        case .fullscreen:
            Task { [weak self] in
                guard let self else { return }
                do {
                    guard let target = try await self.target(for: mode) else { return }
                    let captured = try await self.engine.capture(target)
                    Log.capture.info(
                        "captured \(Int(captured.pixelSize.width))x\(Int(captured.pixelSize.height))px"
                    )
                    try await self.finish(captured)
                } catch {
                    Log.capture.error("capture failed: \(error.localizedDescription, privacy: .public)")
                    self.present(error: error)
                }
            }
        }
    }

    /// Area capture runs the selector first, then captures the chosen region.
    ///
    /// The popup is dismissed before the overlay appears so a previous capture's panel cannot end
    /// up inside the new one — though even if it did, SCContentFilter excludes our own windows.
    /// Window capture presents the picker, then captures whatever was clicked.
    private func beginWindowPicking() {
        guard !windowPicker.isActive else { return }
        popup.dismiss()

        Task { [weak self] in
            guard let self else { return }
            do {
                let windows = try await self.engine.windows()
                guard !windows.isEmpty else {
                    Log.capture.error("no capturable windows")
                    return
                }
                self.windowPicker.begin(windows: windows) { [weak self] id in
                    guard let self, let id else { return } // nil means cancelled
                    Task {
                        do {
                            let captured = try await self.engine.capture(.window(id))
                            Log.capture.info("captured window \(id)")
                            try await self.finish(captured)
                        } catch {
                            Log.capture.error(
                                "window capture failed: \(error.localizedDescription, privacy: .public)"
                            )
                            self.present(error: error)
                        }
                    }
                }
            } catch {
                Log.capture.error(
                    "could not list windows: \(error.localizedDescription, privacy: .public)"
                )
                self.present(error: error)
            }
        }
    }

    private func beginAreaSelection() {
        guard !selector.isActive else { return }
        popup.dismiss()

        selector.begin { [weak self] rect, displayID in
            guard let self, let rect, let displayID else { return } // nil means cancelled
            Task {
                do {
                    let captured = try await self.engine.capture(.region(rect, on: displayID))
                    try await self.finish(captured)
                } catch {
                    self.present(error: error)
                }
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
            return nil // handled by the picker and the selector; never reaches here
        }
    }

    /// Persist, then show the popup.
    private func finish(_ captured: CapturedImage) async throws {
        cachedConfig = await configStore.current

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
        actions.annotate = { [weak self] in
            guard let self else { return }
            self.popup.dismiss()
            self.openEditor(source: captured.cgImage, pixelSize: captured.pixelSize)
        }
        actions.pin = { [weak self] in
            guard let self else { return }
            self.popup.dismiss()
            self.pinned.pin(image: captured.cgImage) { [weak self] in
                self?.stageForDrag(image: captured.cgImage)
            }
        }
        // Dragging the preview out of the popup is how a capture gets somewhere without a round
        // trip through Save.
        actions.dragURL = { [weak self] in self?.stageForDrag(image: captured.cgImage) }

        if historyPanel.isVisible { historyModel.load() }

        Log.ui.info("presenting popup")
        popup.present(
            image: NSImage(cgImage: captured.cgImage, size: captured.pointSize),
            pixelSize: captured.pixelSize,
            actions: actions
        )
    }

    private func save(_ captured: CapturedImage) async {
        let config = await configStore.current
        cachedConfig = config
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
