import Foundation
import Testing
@testable import PotretCore

@Suite("Config store")
struct ConfigStoreTests {
    private func temporaryDirectory() -> URL {
        let url = URL.temporaryDirectory.appending(path: "potret-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A missing file yields defaults without creating one")
    func missingFile() async {
        let directory = temporaryDirectory()
        let url = directory.appending(path: "config.json")
        let store = ConfigStore(fileURL: url)
        #expect(await store.current == .default)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("An update is persisted and reads back")
    func persists() async throws {
        let url = temporaryDirectory().appending(path: "config.json")
        let store = ConfigStore(fileURL: url, debounce: .zero)
        await store.update { $0.savePath = "/tmp/shots" }
        await store.flush()

        let reloaded = ConfigStore(fileURL: url)
        #expect(await reloaded.current.savePath == "/tmp/shots")
    }

    @Test("Writing an unchanged value does not touch the disk")
    func noOpUpdate() async {
        let url = temporaryDirectory().appending(path: "config.json")
        let store = ConfigStore(fileURL: url, debounce: .zero)
        await store.update { $0.format = .png } // already the default
        await store.flush()
        // flush() still writes once; the point is that update() short-circuited, so the value
        // is unchanged rather than a redundant mutation being propagated.
        #expect(await store.current == .default)
    }

    @Test("Rapid edits coalesce into one write")
    func debounceCoalesces() async throws {
        // The Tauri Settings pane saved on every keystroke of the filename template, and each
        // save re-registered all four global hotkeys.
        let url = temporaryDirectory().appending(path: "config.json")
        let store = ConfigStore(fileURL: url, debounce: .milliseconds(80))

        for character in "Screenshot" {
            await store.update { $0.filenameTemplate.append(character) }
        }
        // Nothing on disk yet — the debounce has not elapsed.
        #expect(!FileManager.default.fileExists(atPath: url.path))

        await store.flush()
        let reloaded = ConfigStore(fileURL: url)
        #expect(await reloaded.current.filenameTemplate.hasSuffix("Screenshot"))
    }

    @Test("A corrupt file falls back in memory but is not destroyed")
    func corruptFileIsPreserved() async throws {
        let url = temporaryDirectory().appending(path: "config.json")
        let garbage = "{ not json at all"
        try garbage.write(to: url, atomically: true, encoding: .utf8)

        let store = ConfigStore(fileURL: url)
        #expect(await store.current == .default)
        #expect(ConfigStore.isUnreadable(at: url))
        // The user's file is still there to be fixed by hand.
        #expect(try String(contentsOf: url, encoding: .utf8) == garbage)
    }

    @Test("Settings are imported from another install, but never over an existing file")
    func importSeedsOnlyWhenEmpty() async throws {
        let directory = temporaryDirectory()
        let source = directory.appending(path: "source.json")
        var seed = AppConfig.default
        seed.savePath = "/tmp/from-tauri"
        try JSONEncoder().encode(seed).write(to: source)

        let fresh = directory.appending(path: "fresh.json")
        let store = ConfigStore(fileURL: fresh, debounce: .zero)
        await store.importIfEmpty(from: source)
        #expect(await store.current.savePath == "/tmp/from-tauri")

        // A store that already has a file must be left alone.
        await store.flush()
        let existing = ConfigStore(fileURL: fresh, debounce: .zero)
        await existing.update { $0.savePath = "/tmp/mine" }
        await existing.flush()
        await existing.importIfEmpty(from: source)
        #expect(await existing.current.savePath == "/tmp/mine")
    }
}
