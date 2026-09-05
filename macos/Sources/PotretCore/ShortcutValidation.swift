import Foundation

/// Which of the app's global shortcuts a combo is bound to.
public enum ShortcutID: String, CaseIterable, Codable, Sendable {
    case captureArea
    case captureWindow
    case captureFullscreen
    case recentCaptures

    public var label: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        case .captureFullscreen: "Capture Fullscreen"
        case .recentCaptures: "Recent Captures"
        }
    }
}

/// Why a proposed shortcut cannot be used.
///
/// Every case carries text meant to be shown to the user in the row they are editing. The Tauri
/// app reported the equivalent failures with `eprintln!` to a stderr nobody reads, so a shortcut
/// that silently did nothing looked identical to one that worked.
public enum ShortcutRejection: Equatable, Sendable {
    case needsModifier
    case reservedByMacOS(String)
    case reservedBySystem(String)
    case duplicate(ShortcutID)

    public var message: String {
        switch self {
        case .needsModifier:
            "Add ⌘, ⇧ or ⌥ — a bare key would fire while you're typing."
        case .reservedByMacOS(let combo):
            "\(combo) belongs to macOS's own screenshot tool, so Potret never sees it."
        case .reservedBySystem(let combo):
            "\(combo) is reserved by macOS."
        case .duplicate(let other):
            "Already used by \"\(other.label)\"."
        }
    }
}

/// Rejects shortcuts that cannot work, before they can ever be written to disk.
public enum ShortcutValidator {
    /// macOS's own screenshot shortcuts: ⌘⇧3/4/5/6 and ⌘⌃⇧3/4. The system consumes these before
    /// any app sees the keypress, so registering one produces a shortcut that silently does
    /// nothing. The Tauri app shipped ⌘⇧3/4/5 as its defaults, added a migration to move users
    /// off them, and then reintroduced them through a "Reset to defaults" button.
    static func isMacOSScreenshotShortcut(_ combo: KeyCombo) -> Bool {
        guard combo.modifiers.contains(.command), combo.modifiers.contains(.shift) else {
            return false
        }
        guard let name = KeyCodes.name(for: combo.keyCode) else { return false }
        return ["3", "4", "5", "6"].contains(name)
    }

    /// Combos the system owns outright, where stealing them would break the Mac.
    static func isSystemReserved(_ combo: KeyCombo) -> Bool {
        guard let name = KeyCodes.name(for: combo.keyCode) else { return false }
        let onlyCommand = combo.modifiers == .command
        // ⌘Q quit, ⌘W close, ⌘Space Spotlight, ⌘Tab app switcher.
        return onlyCommand && ["Q", "W"].contains(name)
    }

    /// - Parameters:
    ///   - combo: the proposed shortcut.
    ///   - id: which shortcut is being edited, so it doesn't clash with itself.
    ///   - existing: the current bindings.
    public static func validate(
        _ combo: KeyCombo,
        for id: ShortcutID,
        existing: [ShortcutID: KeyCombo]
    ) -> ShortcutRejection? {
        // A bare key would fire in the middle of typing. F-keys are the exception: they carry no
        // character, so they are safe unmodified and some users prefer them.
        let isFunctionKey = KeyCodes.functionKeys.values.contains(combo.keyCode)
        if combo.modifiers.isEmpty && !isFunctionKey {
            return .needsModifier
        }
        if isMacOSScreenshotShortcut(combo) {
            return .reservedByMacOS(combo.displayString)
        }
        if isSystemReserved(combo) {
            return .reservedBySystem(combo.displayString)
        }
        if let clash = existing.first(where: { $0.key != id && $0.value == combo })?.key {
            return .duplicate(clash)
        }
        return nil
    }
}

/// Reads the Tauri app's string shortcuts once, so an upgrading user keeps their bindings.
public enum LegacyShortcutMigration {
    /// Parses "CommandOrControl+Shift+4" into a `KeyCombo`.
    ///
    /// Returns nil for anything unmappable — a shortcut the old app could not register either.
    /// The caller drops those and tells the user, rather than refusing to load the whole config.
    public static func parse(_ string: String) -> KeyCombo? {
        var modifiers: KeyCombo.Modifiers = []
        var keyName: String?

        for part in string.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "CommandOrControl", "CmdOrCtrl", "Command", "Meta", "Super":
                modifiers.insert(.command)
            case "Shift":
                modifiers.insert(.shift)
            case "Alt", "Option":
                modifiers.insert(.option)
            case "Control", "Ctrl":
                modifiers.insert(.control)
            default:
                keyName = part
            }
        }

        guard let keyName, let code = KeyCodes.code(for: keyName) else { return nil }
        return KeyCombo(keyCode: code, modifiers: modifiers)
    }

    /// Every shortcut in a config, migrated. Unmappable ones are reported rather than dropped
    /// silently, and anything macOS reserves is replaced with the working default — which is what
    /// the Tauri app's `migrate_colliding_shortcuts` did, except this cannot be undone later by a
    /// stale Reset button.
    public static func migrate(_ config: AppConfig) -> (
        combos: [ShortcutID: KeyCombo], failed: [ShortcutID]
    ) {
        let sources: [ShortcutID: String] = [
            .captureArea: config.shortcutArea,
            .captureWindow: config.shortcutWindow,
            .captureFullscreen: config.shortcutFullscreen,
            .recentCaptures: config.shortcutHistory,
        ]
        let fallbacks: [ShortcutID: String] = [
            .captureArea: AppConfig.default.shortcutArea,
            .captureWindow: AppConfig.default.shortcutWindow,
            .captureFullscreen: AppConfig.default.shortcutFullscreen,
            .recentCaptures: AppConfig.default.shortcutHistory,
        ]

        var combos: [ShortcutID: KeyCombo] = [:]
        var failed: [ShortcutID] = []

        for id in ShortcutID.allCases {
            guard let combo = sources[id].flatMap(parse) else {
                failed.append(id)
                if let fallback = fallbacks[id].flatMap(parse) { combos[id] = fallback }
                continue
            }
            if ShortcutValidator.isMacOSScreenshotShortcut(combo) {
                combos[id] = fallbacks[id].flatMap(parse) ?? combo
            } else {
                combos[id] = combo
            }
        }
        return (combos, failed)
    }
}
