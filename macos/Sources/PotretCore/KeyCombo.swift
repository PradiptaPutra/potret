import Foundation

/// A global shortcut, stored as a **virtual key code** plus modifiers.
///
/// The Tauri app stored shortcuts as strings ("CommandOrControl+Shift+4") and parsed them at
/// registration time. That parser knew only 0-9, A-Z and F1-F12, so any other key produced an
/// error — and the registration path responded to an error by unregistering everything and
/// bailing, which silently killed all four hotkeys until the config file was hand-edited.
///
/// Storing a key code deletes that entire failure class: there is no parser, so there is nothing
/// to fail. A code either maps to a key on the user's keyboard or it doesn't, and the recorder can
/// only ever produce codes that do.
public struct KeyCombo: Codable, Hashable, Sendable {
    /// Virtual key code (`kVK_*`). Physical position, independent of layout — the same reason the
    /// recorder reads `event.code` rather than `event.key`: holding Option on macOS rewrites the
    /// character, so ⌥4 arrives as "¢".
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Deliberately not `NSEvent.ModifierFlags`: this module stays free of AppKit so it can be
    /// tested headless. The UI layer converts at the boundary.
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// Human-readable, in the order macOS renders modifiers: ⌃⌥⇧⌘.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += KeyCodes.name(for: keyCode) ?? "?"
        return result
    }
}

/// Virtual key codes for the keys a shortcut may use.
///
/// The values are `kVK_*` constants from Carbon's Events.h, written out rather than imported so
/// this module needs no Carbon dependency. They are positions on an ANSI keyboard and do not
/// change with layout.
public enum KeyCodes {
    public static let letters: [String: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
        "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "O": 0x1F,
        "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28,
        "N": 0x2D, "M": 0x2E,
    ]

    public static let digits: [String: UInt16] = [
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
    ]

    public static let functionKeys: [String: UInt16] = [
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61,
        "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]

    public static var all: [String: UInt16] {
        letters.merging(digits) { first, _ in first }
            .merging(functionKeys) { first, _ in first }
    }

    public static func code(for name: String) -> UInt16? {
        all[name.uppercased()]
    }

    public static func name(for code: UInt16) -> String? {
        all.first { $0.value == code }?.key
    }
}
