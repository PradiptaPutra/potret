import Foundation
import Testing
@testable import PotretCore

@Suite("App config")
struct AppConfigTests {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test("Reads a real config.json written by the Tauri app")
    func decodesTauriFixture() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "tauri-config-0.2.22",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))

        #expect(config.shortcutArea == "CommandOrControl+Shift+4")
        #expect(config.savePath == "/Users/example/Pictures/Shots")
        #expect(config.format == .jpg)
        #expect(config.jpegQuality == 82)
        #expect(config.filenameTemplate == "Shot {date} {seq}")
        #expect(config.cornerPopupEnabled == false)
    }

    @Test("Missing keys fall back instead of throwing")
    func toleratesMissingKeys() throws {
        // An early Tauri config predates format/quality/template/history/corner entirely.
        let config = try decode(#"{"shortcut_area":"CommandOrControl+Alt+4","save_path":null}"#)
        #expect(config.shortcutArea == "CommandOrControl+Alt+4")
        #expect(config.format == .png)
        #expect(config.jpegQuality == 90)
        #expect(config.cornerPopupEnabled == true)
    }

    @Test("Unknown and wrong-typed values fall back rather than resetting the whole file")
    func toleratesBadValues() throws {
        // A settings file that throws would cost the user every shortcut, so a single bad field
        // must degrade to its default and leave the rest intact.
        let config = try decode(#"{"format":"webp","jpeg_quality":"high","future_key":1}"#)
        #expect(config.format == .png)
        #expect(config.jpegQuality == 90)
    }

    @Test("Round-trips through encode and decode")
    func roundTrip() throws {
        var original = AppConfig.default
        original.savePath = "/tmp/shots"
        original.format = .jpg
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == original)
    }

    @Test("Defaults avoid the shortcuts macOS reserves for itself")
    func defaultsDoNotCollideWithMacOS() {
        // Cmd+Shift+3/4/5 belong to macOS's own screenshot tools; an app that registers them
        // never receives the keypress.
        for shortcut in [
            AppConfig.default.shortcutArea,
            AppConfig.default.shortcutWindow,
            AppConfig.default.shortcutFullscreen,
        ] {
            #expect(!shortcut.contains("Shift"))
            #expect(shortcut.contains("Alt"))
        }
    }

    @Test("JPEG quality is clamped so a hand-edited file cannot break encoding")
    func qualityClamping() {
        var config = AppConfig.default
        config.jpegQuality = 5000
        #expect(config.clampedJPEGQuality == 100)
        config.jpegQuality = -3
        #expect(config.clampedJPEGQuality == 1)
    }

    @Test("Retention is read from the file, defaults to 200, and 0 means keep everything")
    func retentionPersists() throws {
        // The Settings control used to change nothing past a relaunch: the prune at launch and
        // after each capture was hardcoded to 200.
        #expect(try decode("{}").retentionLimit == 200)
        #expect(try decode(#"{"retention_limit":50}"#).retentionPolicy.maximumItems == 50)
        #expect(try decode(#"{"retention_limit":0}"#).retentionPolicy == .unlimited)
    }

    @Test("Save directory has exactly one fallback")
    func saveDirectoryFallback() {
        // The Tauri app claimed "Default (App Support)" in Settings while writing to the Desktop.
        var config = AppConfig.default
        config.savePath = nil
        #expect(config.saveDirectory == AppConfig.defaultSaveDirectory)
        #expect(config.saveDirectory.lastPathComponent == "Desktop")

        config.savePath = "/tmp/elsewhere"
        #expect(config.saveDirectory.path() == "/tmp/elsewhere/")
    }
}
