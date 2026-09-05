import Foundation
import Testing
@testable import PotretCore

@Suite("Shortcuts")
struct ShortcutTests {
    private func combo(_ key: String, _ modifiers: KeyCombo.Modifiers) -> KeyCombo {
        KeyCombo(keyCode: KeyCodes.code(for: key)!, modifiers: modifiers)
    }

    @Test("Key codes are physical positions, so Option cannot rewrite them")
    func keyCodeTable() {
        // 0x15 is kVK_ANSI_4. On macOS, Option+4 produces "¢" — reading the character instead of
        // the position is what would make the shipped Cmd+Option defaults unrecordable.
        #expect(KeyCodes.code(for: "4") == 0x15)
        #expect(KeyCodes.code(for: "a") == 0x00) // case-insensitive
        #expect(KeyCodes.code(for: "F5") == 0x60)
        #expect(KeyCodes.code(for: "¢") == nil)
        #expect(KeyCodes.name(for: 0x15) == "4")
    }

    @Test("Display string uses macOS modifier order")
    func displayString() {
        #expect(combo("4", [.command, .option]).displayString == "⌥⌘4")
        #expect(combo("H", [.command, .shift]).displayString == "⇧⌘H")
        #expect(combo("F1", []).displayString == "F1")
        #expect(combo("3", [.control, .option, .shift, .command]).displayString == "⌃⌥⇧⌘3")
    }

    @Test("A bare key is rejected, but a bare F-key is allowed")
    func modifierRequirement() {
        #expect(
            ShortcutValidator.validate(combo("A", []), for: .captureArea, existing: [:])
                == .needsModifier
        )
        // F-keys carry no character, so they cannot fire mid-sentence.
        #expect(ShortcutValidator.validate(combo("F5", []), for: .captureArea, existing: [:]) == nil)
    }

    @Test("macOS's own screenshot shortcuts are refused with a reason")
    func macOSScreenshotShortcuts() {
        // The system consumes these before any app sees them, so registering one yields a
        // shortcut that silently does nothing.
        for key in ["3", "4", "5", "6"] {
            let rejection = ShortcutValidator.validate(
                combo(key, [.command, .shift]), for: .captureArea, existing: [:]
            )
            #expect(rejection == .reservedByMacOS("⇧⌘\(key)"))
        }
        // The same digits with Option instead of Shift are exactly what we ship.
        #expect(
            ShortcutValidator.validate(
                combo("4", [.command, .option]), for: .captureArea, existing: [:]
            ) == nil
        )
    }

    @Test("Shortcuts the system owns outright are refused")
    func systemReserved() {
        #expect(
            ShortcutValidator.validate(combo("Q", [.command]), for: .captureArea, existing: [:])
                == .reservedBySystem("⌘Q")
        )
        // ⌘⇧Q is not ⌘Q; only the exact combo is reserved.
        #expect(
            ShortcutValidator.validate(
                combo("Q", [.command, .shift]), for: .captureArea, existing: [:]
            ) == nil
        )
    }

    @Test("A combo already bound elsewhere is refused, but rebinding to itself is fine")
    func duplicates() {
        let existing: [ShortcutID: KeyCombo] = [.captureWindow: combo("5", [.command, .option])]
        #expect(
            ShortcutValidator.validate(
                combo("5", [.command, .option]), for: .captureArea, existing: existing
            ) == .duplicate(.captureWindow)
        )
        #expect(
            ShortcutValidator.validate(
                combo("5", [.command, .option]), for: .captureWindow, existing: existing
            ) == nil
        )
    }

    @Test("Legacy Tauri strings parse")
    func legacyParsing() {
        #expect(
            LegacyShortcutMigration.parse("CommandOrControl+Alt+4")
                == combo("4", [.command, .option])
        )
        #expect(
            LegacyShortcutMigration.parse("CommandOrControl+Shift+H")
                == combo("H", [.command, .shift])
        )
        // The exact strings that bricked the old app: its parser errored, and the error path
        // unregistered everything.
        #expect(LegacyShortcutMigration.parse("CommandOrControl+Shift+-") == nil)
        #expect(LegacyShortcutMigration.parse("CommandOrControl+Alt+,") == nil)
    }

    @Test("Migrating a real config moves colliding shortcuts to working ones")
    func migrationFixesCollisions() {
        // Straight from the 0.2.22 fixture: all three captures on macOS's own shortcuts.
        var config = AppConfig.default
        config.shortcutArea = "CommandOrControl+Shift+4"
        config.shortcutWindow = "CommandOrControl+Shift+5"
        config.shortcutFullscreen = "CommandOrControl+Shift+3"

        let (combos, failed) = LegacyShortcutMigration.migrate(config)
        #expect(failed.isEmpty)
        #expect(combos[.captureArea] == combo("4", [.command, .option]))
        #expect(combos[.captureFullscreen] == combo("3", [.command, .option]))
        // The history shortcut is Cmd+Shift+H — Shift is fine, it is only 3/4/5/6 that collide.
        #expect(combos[.recentCaptures] == combo("H", [.command, .shift]))
    }

    @Test("An unmappable shortcut is reported and replaced, never left dead")
    func migrationReportsFailures() {
        var config = AppConfig.default
        config.shortcutArea = "CommandOrControl+Shift+-" // what bricked the Tauri app
        let (combos, failed) = LegacyShortcutMigration.migrate(config)

        #expect(failed == [.captureArea])
        // The other three are untouched, and the broken one falls back to a working default
        // rather than taking the rest down with it.
        #expect(combos[.captureArea] == combo("4", [.command, .option]))
        #expect(combos[.captureWindow] == combo("5", [.command, .option]))
        #expect(combos.count == 4)
    }
}
