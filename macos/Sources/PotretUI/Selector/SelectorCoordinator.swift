import AppKit
import PotretCapture
import PotretCore

/// Runs area selection across every attached display.
///
/// One panel per screen, each in its own coordinate space, all reporting into here so a drag is
/// accumulated in global coordinates and resolved to whichever display holds most of it.
///
/// The teardown story matters more than the drawing. These panels sit at
/// `CGShieldingWindowLevel()`, above the menu bar and the Dock — a selector that fails to go away
/// leaves the Mac unusable, so there are three independent ways out: Esc, the app resigning
/// active, and a watchdog. Any one of them alone is enough.
@MainActor
public final class SelectorCoordinator {
    /// If a selection has not finished in this long, something has gone wrong and the overlay is
    /// torn down regardless.
    private static let watchdog: Duration = .seconds(60)

    private var panels: [(panel: OverlayPanel, view: SelectorView, screen: NSScreen)] = []
    private var completion: ((CGRect?, CGDirectDisplayID?) -> Void)?
    private var watchdogTask: Task<Void, Never>?
    private var resignObserver: (any NSObjectProtocol)?
    /// NSCursor.hide/unhide are counted, and an unbalanced pair leaves the user with no pointer.
    private var cursorHidden = false

    public init() {}

    public var isActive: Bool { !panels.isEmpty }

    /// Present the overlay. `completion` receives a rect in global coordinates plus the display it
    /// belongs to, or nil if the user cancelled.
    public func begin(completion: @escaping (CGRect?, CGDirectDisplayID?) -> Void) {
        guard panels.isEmpty else { return }
        self.completion = completion

        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())),
                acceptsKeyboard: true // Esc
            )
            panel.hasShadow = false

            let view = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.onDragBegan = { [weak self] in self?.clearOtherSelections(except: view) }
            view.onComplete = { [weak self] rect in
                self?.finish(rect, from: view, on: screen)
            }
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

        hideCursor()
        installWatchdog()
        installResignObserver()
    }

    public func cancel() {
        finish(nil, from: nil, on: nil)
    }

    // MARK: Internals

    private func clearOtherSelections(except active: SelectorView) {
        for entry in panels where entry.view !== active {
            entry.view.clear()
        }
    }

    private func finish(_ rect: CGRect?, from view: SelectorView?, on screen: NSScreen?) {
        guard let completion else { return }
        self.completion = nil

        var globalRect: CGRect?
        var displayID: CGDirectDisplayID?

        if let rect, let screen {
            // View coordinates are screen-local; the engine works in global space.
            globalRect = CGRect(
                x: screen.frame.minX + rect.minX,
                y: screen.frame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
            displayID = screen.displayID
        }

        teardown()
        completion(globalRect, displayID)
    }

    private func teardown() {
        watchdogTask?.cancel()
        watchdogTask = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        showCursor()
        for entry in panels {
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
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.cancel()
            }
        }
    }

    /// Third escape hatch. Nobody spends a minute choosing a rectangle; if this fires, the
    /// overlay is stuck and taking it down is strictly better than leaving it up.
    private func installWatchdog() {
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard !Task.isCancelled else { return }
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
