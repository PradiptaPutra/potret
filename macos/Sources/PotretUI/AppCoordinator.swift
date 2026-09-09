import AppKit
import PotretCapture
import PotretCore
import PotretRecord
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
    private let countdown = CountdownController()
    private let windowPicker = WindowPickerCoordinator()
    private let historyModel: HistoryModel
    private let historyPanel: HistoryPanelController
    private var historyActions = HistoryActions()
    /// Set by the app delegate so the history panel can anchor under the menu-bar item.
    public weak var statusButton: NSStatusBarButton?
    /// Called when recording state changes, so the menu bar can reflect it.
    public var onRecordingStateChanged: (() -> Void)?
    private let cornerHover: CornerHoverController
    private var pinned: PinnedController!
    private var recorder: RecordingController!
    private let toast = ToastController()
    /// Latest settings, for paths that must answer synchronously (a drag cannot await).
    private var cachedConfig: AppConfig = .default
    private var settingsModel: SettingsModel?
    private var settingsWindow: MainWindowController?
    private var editorWindow: MainWindowController?
    private var homeWindow: MainWindowController?
    private var trimWindow: MainWindowController?
    private var trimModel: TrimModel?
    /// Shortcut glyphs for display, e.g. "⌥⌘3". Read by the menu.
    public private(set) var shortcutLabels: [ShortcutID: String] = [:]
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
        // Its own model: the corner loads with a limit of five, and doing that on the model the
        // home window and history panel share truncated their lists to five as well.
        let cornerModel = HistoryModel(store: store)

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
        actions.delete = { [weak model, weak cornerModel] item in
            model?.delete(item)
            cornerModel?.load(limit: CornerHoverView.itemCount)
        }
        actions.clearAll = { [weak model] in model?.clearAll() }
        self.historyPanel = HistoryPanelController(model: model, actions: actions)
        self.cornerHover = CornerHoverController(model: cornerModel, actions: actions)

        self.pinned = PinnedController { [weak self] image, size in
            self?.openEditor(source: image, pixelSize: size)
        }
        self.recorder = RecordingController(
            onFinished: { [weak self] recording in
                self?.onRecordingStateChanged?()
                self?.finishRecording(recording)
            },
            onError: { [weak self] error in
                self?.onRecordingStateChanged?()
                self?.present(error: error)
            }
        )

        // Freeze snapshots a display through the same engine as every other capture, so the
        // overlay's own panels are excluded from it.
        selector.freezeProvider = { [engine] id in try await engine.capture(.display(id)) }
        selector.onError = { [weak self] error in self?.present(error: error) }

        // annotate and dragURL need `self`, so they are attached once initialisation is complete.
        var full = actions
        full.annotate = { [weak self] item in self?.openEditor(for: item) }
        full.dragURL = { [weak self] item in self?.stageForDrag(item) }
        historyPanel.updateActions(full)
        cornerHover.updateActions(full)
        historyActions = full
    }

    /// Open the newest stored capture in the editor — the same path a card click takes.
    public func editLatestForTesting() {
        historyModel.load()
        guard let item = historyModel.items.first else {
            Log.ui.error("no history item to edit")
            return
        }
        openEditor(for: item)
    }

    /// Trim the newest recording to a fixed range and save it, with no pointer involved.
    ///
    /// The trim path is otherwise only reachable by dragging two handles, which cannot be checked
    /// without taking over the machine's input. This drives the same code the buttons drive.
    public func trimLatestForTesting(start: TimeInterval, end: TimeInterval) {
        historyModel.load()
        guard let item = historyModel.items.first(where: \.isRecording) else {
            Log.ui.error("no recording to trim")
            return
        }
        openEditor(for: item)
        guard let model = trimModel else { return }
        model.setStart(start)
        model.setEnd(end)
        Log.ui.info(
            "trim test: \(item.id, privacy: .public) \(start, format: .fixed(precision: 2))–\(end, format: .fixed(precision: 2))"
        )
        Task { [weak self] in
            guard let self, let model = self.trimModel else { return }
            let output = TrimScratch.url(extension: "mp4")
            do {
                try await VideoTools.trim(
                    model.url, from: model.start, to: model.end, to: output
                )
                self.finishTrim(output, trimmedTo: model.trimmedDuration, historyID: item.id)
            } catch {
                Log.ui.error("trim test failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Open a stored capture in the editor.
    private func openEditor(for item: HistoryItem) {
        Log.ui.info("opening editor for \(item.id, privacy: .public)")
        // A recording cannot be annotated; open it in the trimmer instead of failing silently.
        if item.isRecording {
            Log.ui.info("item is a recording — opening the trimmer")
            openTrimmer(
                for: Recording(
                    url: item.imageURL,
                    duration: item.duration ?? 0,
                    pixelSize: item.pixelSize,
                    fileSize: item.fileSize
                ),
                historyID: item.id
            )
            return
        }
        guard
            let image = NSImage(contentsOf: item.imageURL),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            Log.ui.error("could not decode \(item.imageURL.lastPathComponent, privacy: .public)")
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
        // One editor at a time. Replacing the controller while its window was still open orphaned
        // that window — no delegate, never counted as closed — and the app kept its Dock icon for
        // good. Bringing the existing one forward loses nothing.
        if let editorWindow, editorWindow.isVisible {
            editorWindow.show()
            toast.show("Finish the current annotation first")
            return
        }
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
        // The close button and Cmd-W used to discard the annotations silently — only Done saved.
        editorWindow?.shouldClose = { [weak self] in
            guard let self, let model = self.editorModel, model.hasChanges else { return true }
            self.promptToSaveAnnotations(model)
            return false
        }
        editorWindow?.show()
        Log.ui.info("editor window shown")
    }

    private func promptToSaveAnnotations(_ model: EditorModel) {
        guard let window = editorWindow?.window else { return }
        let alert = NSAlert()
        alert.messageText = "Save your annotations?"
        alert.informativeText = "Your changes will be saved to your folder and to the library."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        // A sheet on the editor itself, which is key and frontmost — unlike a modal alert from a
        // background accessory, this one is guaranteed to be seen.
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: model.finish()
            case .alertSecondButtonReturn: self?.editorWindow?.closeWithoutPrompt()
            default: break
            }
        }
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
                self.historyModel.load()
            } catch {
                Log.ui.error("saving annotation failed: \(error.localizedDescription, privacy: .public)")
            }
            self.editorWindow?.closeWithoutPrompt()
            self.editorWindow = nil
            self.editorModel = nil
        }
    }

    /// Force the corner stack open — verification only; the real trigger is the corner hot zone.
    public func showCornerStack() {
        cornerHover.showNow()
    }

    public var isRecording: Bool { recorder.isRecording }

    /// Start a recording, choosing the target the same way a capture does.
    ///
    /// A browser tab cannot be targeted directly — a tab is not a window, and ScreenCaptureKit
    /// works in windows and displays. Recording the browser window follows whatever tab is in
    /// front of it, and area recording covers the case where only part of the page matters.
    public func record(_ mode: CaptureMode) {
        Log.capture.info("record requested: \(String(describing: mode), privacy: .public)")
        guard !recorder.isRecording else {
            Log.capture.info("already recording — stopping instead")
            recorder.stop()
            return
        }
        guard CapturePermission.isGranted else {
            presentPermissionAlert()
            return
        }

        switch mode {
        case .fullscreen:
            Task { [weak self] in
                guard let self else { return }
                do {
                    let displays = try await self.engine.displays()
                    let pointer = NSEvent.mouseLocation
                    let active = displays.first { $0.frame.contains(pointer) } ?? displays.first
                    guard let active else { throw CaptureError.noDisplays }
                    await self.countdownBeforeRecording(on: active.frame)
                    await self.recorder.start(
                        target: .display(active.id),
                        settings: await self.currentRecordingSettings()
                    )
                    self.onRecordingStateChanged?()
                } catch {
                    self.present(error: error)
                }
            }
        case .window:
            Task { [weak self] in
                guard let self else { return }
                do {
                    let windows = try await self.engine.windows()
                    self.windowPicker.begin(windows: windows) { [weak self] id in
                        guard let self, let id else { return }
                        Task {
                            // Centred on the screen, not the window: WindowInfo frames are in CG
                            // global space (top-left origin) and panels are placed in AppKit's,
                            // so using one here would put the countdown at the wrong height.
                            await self.countdownBeforeRecording(
                                on: PanelPlacement.activeScreen.frame
                            )
                            await self.recorder.start(
                                target: .window(id), settings: await self.currentRecordingSettings()
                            )
                            self.onRecordingStateChanged?()
                        }
                    }
                } catch {
                    self.present(error: error)
                }
            }
        case .area:
            guard !selector.isActive else { return }
            popup.dismiss()
            selector.begin(intent: .record) { [weak self] result in
                self?.handle(selection: result)
            }
        }
    }

    /// What happens after the selector: the timer if one was set, then a capture or a
    /// recording of the region — whichever the bar's choice was, regardless of which hotkey
    /// opened the selector.
    private func handle(selection result: SelectionResult?) {
        guard let result else {
            Log.capture.info("area selection cancelled")
            return
        }
        Log.capture.info(
            "area \(String(describing: result.intent), privacy: .public) \(NSStringFromRect(result.rect), privacy: .public) delay=\(result.delay) frozen=\(result.frozen != nil)"
        )
        Task { [weak self] in
            guard let self else { return }
            if result.delay > 0 {
                await self.countdown.run(seconds: result.delay, centredOn: result.displayFrame)
            } else if result.intent == .record {
                // No timer chosen in the bar, so fall back to the recording countdown from
                // Settings — an area recording gets the same beat to get set up as any other.
                await self.countdownBeforeRecording(on: result.displayFrame)
            }
            switch result.intent {
            case .capture:
                do {
                    let captured: CapturedImage
                    if let frozen = result.frozen,
                       let crop = frozen.cropped(
                           toGlobalRect: result.rect, displayFrame: result.displayFrame
                       ) {
                        captured = crop
                    } else {
                        captured = try await self.engine.capture(
                            .region(result.rect, on: result.displayID)
                        )
                    }
                    try await self.finish(captured)
                } catch {
                    self.present(error: error)
                }
            case .record:
                await self.recorder.start(
                    target: .region(result.rect, on: result.displayID),
                    settings: await self.currentRecordingSettings()
                )
                self.onRecordingStateChanged?()
            }
        }
    }

    /// Record the front-most window without the picker — isolates the window pipeline from the
    /// overlay interaction when diagnosing.
    public func recordFrontWindowForTesting() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let windows = try await self.engine.windows()
                // A real app window, not Finder's desktop layer: that is what a user picks.
                guard let front = windows.first(where: {
                    !$0.title.isEmpty && $0.frame.width > 400 && $0.frame.height > 300
                }) ?? windows.first else {
                    Log.capture.error("test window record: no windows")
                    return
                }
                Log.capture.info("test window record: \(front.owningApplication, privacy: .public) \(front.id)")
                await self.recorder.start(target: .window(front.id), settings: await self.currentRecordingSettings())
                self.onRecordingStateChanged?()
            } catch {
                self.present(error: error)
            }
        }
    }

    /// Record a fixed region without the selector — isolates the region pipeline from the
    /// overlay interaction when diagnosing.
    public func recordRegionForTesting(_ rect: CGRect) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let displays = try await self.engine.displays()
                guard let display = displays.first else { return }
                Log.capture.info("test region record \(NSStringFromRect(rect), privacy: .public)")
                await self.recorder.start(
                    target: .region(rect, on: display.id), settings: await self.currentRecordingSettings()
                )
                self.onRecordingStateChanged?()
            } catch {
                self.present(error: error)
            }
        }
    }

    public func stopRecording() {
        recorder.stop()
    }

    /// Settings for a recording about to start, read from the store rather than from the cache.
    ///
    /// `cachedConfig` is only refreshed by a capture, so a user who opens Settings, turns the
    /// pointer off and records straight away would have got the old value — the setting would
    /// appear to need a capture, or a relaunch, before it took. Re-reading here costs one actor
    /// hop on a path that is already async and already about to touch the disk.
    private func currentRecordingSettings() async -> RecordingSettings {
        let config = await configStore.current
        cachedConfig = config
        return RecordingSettings(
            frameRate: config.clampedRecordingFrameRate,
            // Anything unrecognised in a hand-edited config falls back rather than failing.
            quality: RecordingSettings.Quality(rawValue: config.recordingQuality) ?? .standard,
            showsCursor: config.recordingShowsCursor,
            highlightsClicks: config.recordingHighlightsClicks
        )
    }

    /// Count down before a recording starts, unless the caller already did.
    ///
    /// Every recording needs the same beat to arrange the window being demonstrated — the area
    /// selector offered it and the window and screen paths began the instant they were asked,
    /// which is too soon to be useful for anything you meant to show.
    private func countdownBeforeRecording(on frame: CGRect) async {
        let seconds = await configStore.current.clampedRecordingCountdown
        guard seconds > 0 else { return }
        await countdown.run(seconds: seconds, centredOn: frame)
    }

    /// A finished recording goes into history alongside stills, and opens the trimmer.
    private func finishRecording(_ recording: Recording) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let poster = try await VideoTools.posterFrame(for: recording.url)
                let png = try ImageEncoder.encode(poster, format: .png, quality: 100)
                let thumbnailImage = try ImageEncoder.thumbnail(from: png)
                let thumbnail = try ImageEncoder.encode(thumbnailImage, format: .png, quality: 100)
                let stored = try self.historyStore.saveRecording(
                    videoURL: recording.url,
                    thumbnailData: thumbnail,
                    pixelSize: recording.pixelSize,
                    duration: recording.duration
                )
                self.historyModel.load()
                Log.capture.info("recording saved to history")

                // Open the trimmer on the STORED file, not the one that was just recorded.
                // saveRecording MOVES the temp file into the history directory, so the original
                // URL is dead by this point — the player had nothing to play and saving copied
                // from a path that no longer existed.
                self.openTrimmer(
                    for: Recording(
                        url: stored.imageURL,
                        duration: recording.duration,
                        pixelSize: recording.pixelSize,
                        fileSize: stored.fileSize
                    ),
                    historyID: stored.id
                )
            } catch {
                Log.capture.error(
                    "storing recording failed: \(error.localizedDescription, privacy: .public)"
                )
                self.present(error: error)
            }
        }
    }

    /// Open a finished recording for trimming and export.
    ///
    /// - Parameter historyID: the library entry this recording is, when it has one. Saving a trim
    ///   replaces that entry's video, so the grid stops showing a take the user already cut.
    private func openTrimmer(for recording: Recording, historyID: String?) {
        // One trimmer at a time, like the editor. Opening a second recording used to overwrite
        // these references without closing the first window, orphaning it — and its player —
        // mid-playback with nothing left holding a reference able to stop it.
        closeTrimmer()

        let model = TrimModel(recording: recording)
        trimModel = model
        let title = "Recording · \(Int(recording.pixelSize.width))×\(Int(recording.pixelSize.height)) · \(DurationFormat.clock(recording.duration))"
        let controller = MainWindowController(
            title: title,
            defaultSize: NSSize(width: 720, height: 520),
            resizable: true
        ) { [weak self] in
            TrimView(
                model: model,
                onSave: { [weak self] url, trimmedDuration in
                    self?.finishTrim(url, trimmedTo: trimmedDuration, historyID: historyID)
                },
                onExportGIF: { [weak self] url in
                    self?.exportRecordingFile(url, extension: "gif")
                    self?.closeTrimmer()
                },
                onDiscard: { self?.closeTrimmer() }
            )
        }
        // However the window goes — a button in the HUD, the red one, or Cmd-W — the player stops
        // and the references go. Only the HUD button used to run that, so closing the window the
        // ordinary way left an AVPlayer and its periodic observer alive and unreachable.
        controller.onClosed = { [weak self] in
            self?.trimModel?.stop()
            self?.trimModel = nil
            self?.trimWindow = nil
        }
        trimWindow = controller
        controller.show()
    }

    private func closeTrimmer() {
        trimModel?.stop()
        trimWindow?.close()
        trimWindow = nil
        trimModel = nil
    }

    /// Export the finished video, and — when it was actually trimmed — make the cut stick in the
    /// library rather than leaving the full-length take behind.
    private func finishTrim(_ url: URL, trimmedTo duration: TimeInterval?, historyID: String?) {
        exportRecordingFile(url, extension: "mp4")

        guard let duration, let historyID else {
            closeTrimmer()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                // A fresh poster frame: the old one may have come from a part just cut away.
                let poster = try await VideoTools.posterFrame(for: url)
                let png = try ImageEncoder.encode(poster, format: .png, quality: 100)
                let thumbnailImage = try ImageEncoder.thumbnail(from: png)
                let thumbnail = try ImageEncoder.encode(thumbnailImage, format: .png, quality: 100)
                // Moves the scratch file into place, so nothing is left behind in the temp folder.
                _ = try self.historyStore.replaceRecording(
                    id: historyID,
                    videoURL: url,
                    thumbnailData: thumbnail,
                    duration: duration
                )
                self.historyModel.load()
                self.cornerHover.reload()
                Log.capture.info("history entry \(historyID, privacy: .public) replaced with the trim")
            } catch {
                // The export already succeeded, so this does not warrant an error dialog — the
                // user has their file. Say it plainly and leave the original entry alone.
                Log.capture.error(
                    "updating history after a trim failed: \(error.localizedDescription, privacy: .public)"
                )
                self.toast.show(
                    "Saved, but the library still holds the untrimmed recording", isError: true
                )
                TrimScratch.discard(url)
            }
            self.closeTrimmer()
        }
    }

    /// Copy a finished video or GIF into the user's save folder, under the filename template.
    ///
    /// Copies rather than moves: the source is either the history entry, which has to stay, or a
    /// scratch file the caller may still need to file away afterwards.
    private func exportRecordingFile(_ url: URL, extension ext: String) {
        do {
            let directory = cachedConfig.saveDirectory
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let destination = FilenameTemplate(cachedConfig.filenameTemplate)
                .uniqueURL(in: directory, ext: ext)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
            }
            try FileManager.default.copyItem(at: url, to: destination)
            Log.capture.info("saved recording to \(destination.lastPathComponent, privacy: .public)")
            // The toast names the file and stops there. Revealing it called
            // NSWorkspace.activateFileViewerSelecting, which brings Finder to the front and takes
            // the keyboard — from an app whose every other surface goes out of its way not to.
            toast.show("Saved \(destination.lastPathComponent)")
        } catch {
            Log.capture.error("saving recording failed: \(error.localizedDescription, privacy: .public)")
            present(error: error)
        }
    }

    /// The app's main window: capture and record actions, and everything captured so far.
    public func showHome() {
        if homeWindow == nil {
            var actions = HomeActions()
            actions.captureArea = { [weak self] in self?.capture(.area) }
            actions.captureWindow = { [weak self] in self?.capture(.window) }
            actions.captureScreen = { [weak self] in self?.capture(.fullscreen) }
            actions.recordArea = { [weak self] in self?.record(.area) }
            actions.recordWindow = { [weak self] in self?.record(.window) }
            actions.recordScreen = { [weak self] in self?.record(.fullscreen) }
            actions.openSettings = { [weak self] in self?.showSettings() }

            let model = historyModel
            let history = historyActions
            let labels = shortcutLabels
            homeWindow = MainWindowController(
                title: "Potret",
                defaultSize: NSSize(width: 860, height: 560),
                resizable: true
            ) {
                HomeView(
                    model: model,
                    actions: actions,
                    historyActions: history,
                    shortcuts: labels
                )
            }
        }
        historyModel.load()
        homeWindow?.show()
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
        shortcutLabels = combos.mapValues(\.displayString)

        // One-time cleanup of the LaunchAgent the Tauri autostart plugin wrote; it points at the
        // old bundle and is invisible in System Settings.
        if LoginItem.migrateLegacyLaunchAgent() {
            Log.ui.info("removed the legacy LaunchAgent and re-registered via SMAppService")
        }

        cornerHover.isEnabled = config.cornerPopupEnabled
        cornerHover.install()

        // Retention runs at launch as well as after each save: the Tauri app kept every capture
        // forever while showing only the newest 50, so an upgrading user may arrive with a large
        // backlog to trim once.
        _ = try? historyStore.prune(policy: config.retentionPolicy)

        // Clear out files no entry owns. Earlier builds wrote every trim and every GIF straight
        // into the history folder and left them there, where nothing could reach them — so an
        // upgrading user arrives with a pile of them to collect once.
        if let swept = try? historyStore.sweepOrphans(), swept > 0 {
            Log.ui.info("swept \(swept) orphaned file(s) from history")
        }
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

        selector.begin(intent: .capture) { [weak self] result in
            self?.handle(selection: result)
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
        _ = try? historyStore.prune(policy: cachedConfig.retentionPolicy)

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

        // The home window and history panel share this model; a capture taken while either is
        // open used to leave it stale until reopened.
        historyModel.load()

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

    /// Errors go to a panel, not an alert.
    ///
    /// NSAlert.runModal() from an accessory app that is not active can land behind whatever the
    /// user is looking at — so failures were being reported where nobody could see them, and a
    /// feature that failed looked identical to one that did nothing.
    private func present(error: any Error) {
        popup.dismiss()
        let message = (error as? CaptureError)?.errorDescription
            ?? (error as? RecordingError)?.errorDescription
            ?? error.localizedDescription
        Log.capture.error("presented error: \(message, privacy: .public)")
        toast.show(message, isError: true)
    }

    /// A short confirmation, for actions with no other visible result.
    public func notify(_ message: String) {
        toast.show(message)
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
