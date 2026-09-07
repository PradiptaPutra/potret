import AppKit
import PotretCapture
import PotretCore
import SwiftUI

/// What the user settled on in the selector.
public struct SelectionResult: Sendable {
    /// Global AppKit coordinates.
    public let rect: CGRect
    public let displayID: CGDirectDisplayID
    /// The display's frame in the same space, for mapping the rect into a frozen frame.
    public let displayFrame: CGRect
    /// Capture or record — the bar can override what the selector was opened for.
    public let intent: SelectionIntent
    /// Self-timer in seconds; zero means now.
    public let delay: Int
    /// The whole display as it was when the user chose Freeze. When present, the capture is a
    /// crop of this rather than a fresh screenshot — the point of freezing.
    public let frozen: CapturedImage?
}

/// Runs area selection across every attached display.
///
/// One panel per screen, each in its own coordinate space, all reporting into here so a drag is
/// accumulated in global coordinates and resolved to whichever display holds most of it. After
/// the drag the selection stays put with handles and an options bar, so the user can adjust it,
/// type a size, set a timer or freeze the screen before committing.
///
/// The teardown story matters more than the drawing. These panels sit at
/// `CGShieldingWindowLevel()`, above the menu bar and the Dock — a selector that fails to go away
/// leaves the Mac unusable, so there are three independent ways out: Esc, the app resigning
/// active, and a watchdog. Any one of them alone is enough.
@MainActor
public final class SelectorCoordinator {
    /// If nothing has happened in this long, something has gone wrong and the overlay is torn
    /// down regardless. Re-armed on every adjustment, so a slow, careful selection is fine.
    private static let watchdog: Duration = .seconds(90)

    private var panels: [(panel: OverlayPanel, view: SelectorView, screen: NSScreen)] = []
    private var completion: ((SelectionResult?) -> Void)?
    private var watchdogTask: Task<Void, Never>?
    private var resignObserver: (any NSObjectProtocol)?
    /// NSCursor.hide/unhide are counted, and an unbalanced pair leaves the user with no pointer.
    private var cursorHidden = false

    private let barModel = SelectionBarModel()
    private var frozenFrames: [CGDirectDisplayID: CapturedImage] = [:]
    private var freezeTask: Task<Void, Never>?

    /// Captures one display for Freeze. Injected so this class stays free of the engine.
    public var freezeProvider: ((CGDirectDisplayID) async throws -> CapturedImage)?
    public var onError: ((any Error) -> Void)?

    public init() {}

    public var isActive: Bool { !panels.isEmpty }

    /// Present the overlay. `completion` receives the selection, or nil if the user cancelled.
    public func begin(
        intent: SelectionIntent,
        completion: @escaping (SelectionResult?) -> Void
    ) {
        guard panels.isEmpty else { return }
        self.completion = completion
        barModel.intent = intent
        barModel.delay = 0
        barModel.frozen = false
        barModel.aspectLocked = false

        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())),
                acceptsKeyboard: true // Esc, Return, arrows, and the size fields
            )
            panel.hasShadow = false
            // HUD chrome over a dimmed screen is dark whatever the system appearance.
            panel.appearance = NSAppearance(named: .darkAqua)

            let view = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.onDragBegan = { [weak self] in self?.clearOtherSelections(except: view) }
            view.onSelectionChanged = { [weak self, weak view] rect in
                guard let self, let view else { return }
                self.selectionChanged(rect, in: view)
            }
            view.onConfirm = { [weak self] in
                guard let self else { return }
                self.confirm(intent: self.barModel.intent)
            }
            view.onCancel = { [weak self] in self?.cancel() }
            view.onToggleFreeze = { [weak self] in self?.toggleFreeze() }
            view.onPhaseChanged = { [weak self] phase in
                // The reticle stands in for the pointer until there is something to point at.
                if phase == .adjusting { self?.showCursor() } else { self?.hideCursor() }
            }

            let bar = NSHostingView(
                rootView: SelectionBarView(model: barModel, actions: actions(for: view))
            )
            view.accessory = bar

            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            panel.present()
            panels.append((panel, view, screen))
        }

        // Key on the screen under the pointer, so Esc lands somewhere without activating the app.
        if let active = panels.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) })
            ?? panels.first {
            active.panel.makeKey()
            active.view.window?.makeFirstResponder(active.view)
        }

        Log.ui.info("selector shown on \(self.panels.count) screen(s)")
        hideCursor()
        armWatchdog()
        installResignObserver()
    }

    public func cancel() {
        finish(nil)
    }

    // MARK: Bar

    private func actions(for view: SelectorView) -> SelectionBarActions {
        var actions = SelectionBarActions()
        actions.capture = { [weak self] in self?.confirm(intent: .capture) }
        actions.record = { [weak self] in self?.confirm(intent: .record) }
        actions.toggleFreeze = { [weak self] in self?.toggleFreeze() }
        actions.toggleAspectLock = { [weak self] in
            guard let self else { return }
            self.barModel.aspectLocked.toggle()
            for entry in self.panels { entry.view.aspectLocked = self.barModel.aspectLocked }
        }
        actions.cancel = { [weak self] in self?.cancel() }
        actions.setSize = { [weak view] width, height in
            view?.setSelectionSize(pixels: CGSize(width: width, height: height))
        }
        actions.endEditing = { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
        return actions
    }

    private func selectionChanged(_ rect: CGRect?, in view: SelectorView) {
        guard let rect else { return }
        let scale = view.window?.backingScaleFactor ?? 1
        barModel.reflect(
            pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale)
        )
        armWatchdog()
    }

    /// The panel currently holding a selection.
    private var active: (panel: OverlayPanel, view: SelectorView, screen: NSScreen)? {
        panels.first { $0.view.selection != nil }
    }

    private func confirm(intent: SelectionIntent) {
        guard let active, let rect = active.view.selection,
              let displayID = active.screen.displayID
        else { return }
        let screen = active.screen
        // View coordinates are screen-local; the engine works in global space.
        let globalRect = CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        finish(
            SelectionResult(
                rect: globalRect,
                displayID: displayID,
                displayFrame: screen.frame,
                intent: intent,
                delay: barModel.delay,
                frozen: frozenFrames[displayID]
            )
        )
    }

    /// Snapshot every display and draw it under the overlay, so the selection is made over a
    /// still picture; or throw the snapshots away and show the live screen again.
    private func toggleFreeze() {
        guard freezeTask == nil else { return }
        if barModel.frozen {
            frozenFrames.removeAll()
            for entry in panels { entry.view.frozenImage = nil }
            barModel.frozen = false
            Log.ui.info("screen unfrozen")
            return
        }
        guard let freezeProvider else { return }
        freezeTask = Task { [weak self] in
            defer { self?.freezeTask = nil }
            guard let self else { return }
            do {
                for entry in self.panels {
                    guard let id = entry.screen.displayID else { continue }
                    let frame = try await freezeProvider(id)
                    guard self.isActive else { return }
                    self.frozenFrames[id] = frame
                    entry.view.frozenImage = frame.cgImage
                }
                self.barModel.frozen = true
                Log.ui.info("screen frozen on \(self.frozenFrames.count) display(s)")
            } catch {
                Log.ui.error("freeze failed: \(error.localizedDescription, privacy: .public)")
                self.onError?(error)
            }
        }
    }

    // MARK: Internals

    private func clearOtherSelections(except active: SelectorView) {
        for entry in panels where entry.view !== active {
            entry.view.clear()
        }
    }

    private func finish(_ result: SelectionResult?) {
        guard let completion else { return }
        self.completion = nil
        teardown()
        completion(result)
    }

    private func teardown() {
        watchdogTask?.cancel()
        watchdogTask = nil
        freezeTask?.cancel()
        freezeTask = nil
        frozenFrames.removeAll()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        showCursor()
        for entry in panels {
            entry.view.accessory = nil
            entry.panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func hideCursor() {
        guard !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    private func showCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }

    /// Second escape hatch: if anything else takes over, the overlay goes away rather than
    /// covering the screen indefinitely.
    private func installResignObserver() {
        // Ignore resigns for a moment after opening. Choosing "Record Area" from the menu bar
        // ends NSMenu's tracking loop, which resigns active — so an observer armed immediately
        // tore the overlay down in the same runloop turn it was created, and the feature looked
        // dead when invoked from the menu while working fine from a hotkey.
        let armedAt = Date()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                guard Date().timeIntervalSince(armedAt) > 0.75 else { return }
                Log.ui.info("overlay dismissed: app resigned active")
                self.cancel()
            }
        }
    }

    /// Third escape hatch. If this fires, the overlay is stuck and taking it down is strictly
    /// better than leaving it up.
    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard !Task.isCancelled else { return }
            Log.ui.error("selector watchdog fired")
            self?.cancel()
        }
    }
}

extension NSScreen {
    /// The CGDirectDisplayID behind this screen, for handing to ScreenCaptureKit.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
