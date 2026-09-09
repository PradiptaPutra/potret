import Foundation
import Testing
@testable import PotretCore

@Suite("Drag staging")
struct DragStagingTests {
    private func temporaryFile(named name: String = "source.png") throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "potret-drag-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    @Test("A capture is staged under its templated name, not its UUID")
    func stagesWithReadableName() throws {
        // Dropping a screenshot into another app should carry the user's filename, not
        // A1B2C3D4-....png, which is what the on-disk history file is called.
        let source = try temporaryFile(named: "\(UUID().uuidString).png")
        let staging = URL.temporaryDirectory.appending(path: "stage-\(UUID().uuidString)")

        let staged = try #require(
            DragStaging.stage(source: source, name: "Screenshot 2025-09-05.png", in: staging)
        )
        #expect(staged.lastPathComponent == "Screenshot 2025-09-05.png")
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(try Data(contentsOf: staged) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Staging clears the previous drag, so a stale file cannot be picked up")
    func clearsPreviousStaging() throws {
        let staging = URL.temporaryDirectory.appending(path: "stage-\(UUID().uuidString)")
        let first = try temporaryFile()
        _ = DragStaging.stage(source: first, name: "First.png", in: staging)

        let second = try temporaryFile()
        _ = DragStaging.stage(source: second, name: "Second.png", in: staging)

        let contents = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        #expect(contents == ["Second.png"])
    }

    @Test("A missing source declines rather than staging an empty file")
    func missingSourceFails() {
        let staging = URL.temporaryDirectory.appending(path: "stage-\(UUID().uuidString)")
        let missing = URL.temporaryDirectory.appending(path: "does-not-exist-\(UUID().uuidString).png")
        #expect(DragStaging.stage(source: missing, name: "X.png", in: staging) == nil)
    }

    @Test("The staged name honours the user's template and format")
    func nameFollowsTemplate() {
        let moment = Date(timeIntervalSince1970: 1_757_030_400)
        let name = DragStaging.name(
            for: FilenameTemplate("Shot {unix}"), ext: "jpg", date: moment
        )
        #expect(name == "Shot 1757030400.jpg")
    }
}
