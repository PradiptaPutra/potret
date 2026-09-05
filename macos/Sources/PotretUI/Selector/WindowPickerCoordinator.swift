import AppKit
import PotretCapture
import PotretCore

/// Click-a-window capture.
///
/// A custom overlay rather than `SCContentSharingPicker`. The system picker is attached to a
/// stream, so a one-shot screenshot would mean starting a stream, taking a frame and stopping it;
/// its "share" wording also reads wrong for taking a picture. This matches what `screencapture -w`
/// users already expect and can be styled to match the rest of the app.
@MainActor
public final class WindowPickerCoordinator {
    private static let watchdog: Duration = .seconds(60)

    private var panels: [(panel: OverlayPanel, view: WindowPickerView, screen: NSScreen)] = []
    private var completion: ((CGWindowID?) -> Void)?
    private var watchdogTask: Task<Void, Never>?
    private var resignObserver: (any NSObjectProtocol)?

    public init() {}

    public var isActive: Bool { !panels.isEmpty }

    /// Present the picker. `completion` receives the chosen window, or nil if cancelled.
    public func begin(windows: [WindowInfo], completion: @escaping (CGWindowID?) -> Void) {
        guard panels.isEmpty, !windows.isEmpty else {
            completion(nil)
            return
        }
        self.completion = completion

        // SCWindow frames are CG global (top-left origin); hit-testing happens against
        // NSEvent.mouseLocation, which is AppKit global (bottom-left origin).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let converted = windows.map { window in
            (
                id: window.id,
                frame: CoordinateSpace.appKitGlobal(
                    cgGlobalRect: window.frame,
                    primaryHeight: primaryHeight
                ),
                title: window.title.isEmpty ? window.owningApplication : window.title,
                app: window.owningApplication
            )
        }

        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())),
                acceptsKeyboard: true
            )
            panel.hasShadow = false

            let view = WindowPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenOrigin = screen.frame.origin
            view.candidates = converted.map {
                WindowPickerView.Candidate(id: $0.id, frame: $0.frame, title: $0.title, app: $0.app)
            }
            view.onPick = { [weak self] id in self?.finish(id) }
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            panel.present()
            panels.append((panel, view, screen))
        }

        if let active = panels.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) })
            ?? panels.first {
            active.panel.makeKey()
            active.panel.makeFirstResponder(active.view)
        }

        installWatchdog()
        installResignObserver()
    }

    public func cancel() { finish(nil) }

    private func finish(_ id: CGWindowID?) {
        guard let completion else { return }
        self.completion = nil
        teardown()
        completion(id)
    }

    private func teardown() {
        watchdogTask?.cancel()
        watchdogTask = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        for entry in panels { entry.panel.orderOut(nil) }
        panels.removeAll()
    }

    /// Same three independent teardown paths as the area selector — these panels also sit above
    /// the menu bar and the Dock, where getting stuck would leave the Mac unusable.
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

    private func installWatchdog() {
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }
}
