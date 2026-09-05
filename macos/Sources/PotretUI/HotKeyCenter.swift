import AppKit
import Carbon.HIToolbox
import PotretCore

/// Why a hotkey could not be registered.
public enum HotKeyError: Error, Equatable, Sendable {
    /// Another application already owns this combination.
    case alreadyTaken
    case registrationFailed(OSStatus)

    public var message: String {
        switch self {
        case .alreadyTaken: "Already used by another app."
        case .registrationFailed(let status): "Could not register (error \(status))."
        }
    }
}

/// Registers the app's global shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey`, chosen over the alternatives for one decisive reason: it
/// returns a status **per registration**, which is what makes per-shortcut isolation possible at
/// all. `NSEvent.addGlobalMonitorForEvents` would need Accessibility permission — a second TCC
/// wall on top of Screen Recording — cannot consume the event, so the keystroke would also reach
/// whatever app is frontmost, and returns nil silently when unapproved.
///
/// The structural rule here: **there is no `unregisterAll`.** `apply` diffs against what is
/// currently registered and touches only what changed. The Tauri app called `unregister_all()`
/// and then bailed on the first parse error, so one bad shortcut deregistered the other three and
/// left the app with no hotkeys at all until its config was hand-edited.
@MainActor
public final class HotKeyCenter {
    public typealias Handler = (ShortcutID) -> Void

    private struct Registration {
        let combo: KeyCombo
        let ref: EventHotKeyRef
        let carbonID: UInt32
    }

    private var registrations: [ShortcutID: Registration] = [:]
    private var byCarbonID: [UInt32: ShortcutID] = [:]
    private var nextCarbonID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var handler: Handler?

    /// Last outcome per shortcut, so Settings can show a failure inline in the row rather than
    /// leaving the user to discover a dead hotkey by pressing it.
    public private(set) var status: [ShortcutID: HotKeyError] = [:]

    public init() {}

    public func onTrigger(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Make the registered set match `desired`.
    ///
    /// Returns a result per shortcut. A failure on one never affects another: unchanged shortcuts
    /// are not touched at all, and a combo that fails to register leaves the others live.
    @discardableResult
    public func apply(_ desired: [ShortcutID: KeyCombo]) -> [ShortcutID: Result<Void, HotKeyError>] {
        installEventHandlerIfNeeded()
        var results: [ShortcutID: Result<Void, HotKeyError>] = [:]

        // Drop only what is going away or changing.
        for (id, registration) in registrations
        where desired[id] == nil || desired[id] != registration.combo {
            unregister(id)
        }

        for (id, combo) in desired {
            if let existing = registrations[id], existing.combo == combo {
                results[id] = .success(()) // already live, nothing to do
                continue
            }
            switch register(combo, for: id) {
            case .success:
                status[id] = nil
                results[id] = .success(())
            case .failure(let error):
                status[id] = error
                results[id] = .failure(error)
            }
        }
        return results
    }

    /// Shortcuts that are currently not working, for the status item badge and Settings.
    public var failures: [ShortcutID: HotKeyError] { status }

    // MARK: Registration

    private func register(_ combo: KeyCombo, for id: ShortcutID) -> Result<Void, HotKeyError> {
        let carbonID = nextCarbonID
        nextCarbonID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: carbonID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            Self.carbonModifiers(combo.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            // eventHotKeyExistsErr means another app got there first — worth saying so precisely,
            // because the fix ("pick a different combo") is different from a generic failure.
            return .failure(
                status == OSStatus(eventHotKeyExistsErr)
                    ? .alreadyTaken
                    : .registrationFailed(status)
            )
        }

        registrations[id] = Registration(combo: combo, ref: ref, carbonID: carbonID)
        byCarbonID[carbonID] = id
        return .success(())
    }

    private func unregister(_ id: ShortcutID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
        byCarbonID[registration.carbonID] = nil
    }

    // MARK: Carbon plumbing

    /// Four-char code identifying our hotkeys, so the handler ignores anyone else's.
    private static let signature: OSType = 0x504F_5452 // 'POTR'

    private static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The C callback cannot capture, so `self` travels as userData. Unretained is correct:
        // the center outlives the handler, and retaining would make a cycle that never releases.
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers on the main run loop, so this is already the main actor —
                // assumeIsolated avoids an async hop that would lose the event ordering.
                MainActor.assumeIsolated { center.dispatch(carbonID: hotKeyID.id) }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    private func dispatch(carbonID: UInt32) {
        guard let id = byCarbonID[carbonID] else { return }
        handler?(id)
    }

    /// Release every registration and the Carbon handler.
    ///
    /// Explicit rather than a `deinit`, because a `deinit` on a `@MainActor` type cannot touch
    /// main-actor state under Swift 6 strict concurrency. In practice this object lives as long as
    /// the app does, so the call site is `applicationWillTerminate` — but hotkeys are a
    /// process-global resource, and leaving them claimed after the app is done with them is the
    /// kind of thing that makes a combo mysteriously unavailable until logout.
    public func shutdown() {
        for id in Array(registrations.keys) {
            unregister(id)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        status.removeAll()
    }
}
