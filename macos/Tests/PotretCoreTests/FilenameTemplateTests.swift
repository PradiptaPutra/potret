import Foundation
import Testing
@testable import PotretCore

@Suite("Filename template")
struct FilenameTemplateTests {
    // Fixed instant so nothing here depends on when the suite runs.
    let moment = Date(timeIntervalSince1970: 1_757_030_400) // 2025-09-05 00:00:00 UTC
    let utc = TimeZone(identifier: "UTC")!

    private func render(_ template: String, ext: String = "png", sequence: Int = 0) -> String {
        FilenameTemplate(template)
            .render(ext: ext, date: moment, sequence: sequence, timeZone: utc)
    }

    @Test("Substitutes every token")
    func tokens() {
        #expect(render("{date}") == "2025-09-05.png")
        #expect(render("{time}") == "00-00-00.png")
        #expect(render("{unix}") == "1757030400.png")
        #expect(render("{seq}", sequence: 7) == "7.png")
    }

    @Test("The shipped default renders the same shape as the Tauri backend")
    func defaultTemplate() {
        let name = FilenameTemplate.default.render(ext: "png", date: moment, timeZone: utc)
        #expect(name == "Screenshot 2025-09-05 at 00-00-00.png")
    }

    @Test("Illegal filename characters become dashes")
    func sanitising() {
        // A template containing a path separator must not be able to escape the directory.
        #expect(render("a/b") == "a-b.png")
        #expect(render(#"x:y*z?"<>|w"#) == "x-y-z-----w.png")
    }

    @Test("A template that renders to nothing falls back rather than producing a dotfile")
    func emptyFallback() {
        #expect(render("") == "Screenshot 1757030400.png")
        #expect(render("   ") == "Screenshot 1757030400.png")
        // A template of only illegal characters sanitises to dashes, which is not empty —
        // it should survive as dashes rather than being thrown away.
        #expect(render("//") == "--.png")
    }

    @Test("Surrounding whitespace is trimmed")
    func trimming() {
        #expect(render("  shot  ") == "shot.png")
    }

    @Test("Extension is honoured")
    func extensions() {
        #expect(render("x", ext: "jpg") == "x.jpg")
    }

    @Test("Collisions get -1, -2, … suffixes")
    func collisionSuffixes() {
        let directory = URL(filePath: "/tmp/potret-test", directoryHint: .isDirectory)
        let taken: Set<String> = [
            "/tmp/potret-test/shot.png",
            "/tmp/potret-test/shot-1.png",
        ]
        let url = FilenameTemplate("shot").uniqueURL(
            in: directory,
            ext: "png",
            date: moment,
            exists: { taken.contains($0.path) }
        )
        #expect(url.lastPathComponent == "shot-2.png")
    }

    @Test("A directory full of collisions falls back to a unique name instead of spinning")
    func collisionCeiling() {
        let directory = URL(filePath: "/tmp/potret-test", directoryHint: .isDirectory)
        let url = FilenameTemplate("shot").uniqueURL(
            in: directory,
            ext: "png",
            date: moment,
            limit: 5,
            exists: { _ in true } // every candidate is taken
        )
        #expect(url.lastPathComponent.hasPrefix("shot-"))
        #expect(url.lastPathComponent.hasSuffix(".png"))
        #expect(url.lastPathComponent.count > "shot-5.png".count)
    }
}
