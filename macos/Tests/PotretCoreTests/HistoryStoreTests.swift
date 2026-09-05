import CoreGraphics
import Foundation
import Testing
@testable import PotretCore

@Suite("History store")
struct HistoryStoreTests {
    private func makeStore() -> HistoryStore {
        let directory = URL.temporaryDirectory.appending(path: "potret-history-\(UUID().uuidString)")
        return HistoryStore(directory: directory)
    }

    private func save(
        _ store: HistoryStore,
        at date: Date,
        bytes: Int = 16
    ) throws -> HistoryItem {
        try store.save(
            imageData: Data(repeating: 0xAB, count: bytes),
            thumbnailData: Data(repeating: 0xCD, count: 4),
            pixelSize: CGSize(width: 100, height: 50),
            now: date
        )
    }

    @Test("A missing directory lists as empty rather than throwing")
    func missingDirectory() throws {
        #expect(try makeStore().list().isEmpty)
    }

    @Test("Saving writes the same three files the Tauri app expects")
    func savesTauriLayout() throws {
        let store = makeStore()
        let item = try save(store, at: Date(timeIntervalSince1970: 1_757_030_400))

        #expect(FileManager.default.fileExists(atPath: item.imageURL.path))
        #expect(FileManager.default.fileExists(atPath: item.thumbnailURL.path))
        #expect(item.imageURL.lastPathComponent == "\(item.id).png")
        #expect(item.thumbnailURL.lastPathComponent == "\(item.id).thumb.png")

        // The sidecar must decode with the Rust field names, or an existing install's history
        // becomes invisible.
        let sidecar = store.directory.appending(path: "\(item.id).json")
        let raw = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any]
        )
        #expect(raw["file_size"] as? Int == 16)
        #expect(raw["timestamp"] as? Int == 1_757_030_400)
        #expect(raw["width"] as? Int == 100)
    }

    @Test("Listing is newest first and honours a limit")
    func ordering() throws {
        let store = makeStore()
        let old = try save(store, at: Date(timeIntervalSince1970: 1000))
        let middle = try save(store, at: Date(timeIntervalSince1970: 2000))
        let new = try save(store, at: Date(timeIntervalSince1970: 3000))

        #expect(try store.list().map(\.id) == [new.id, middle.id, old.id])
        #expect(try store.list(limit: 2).map(\.id) == [new.id, middle.id])
    }

    @Test("A corrupt sidecar is skipped, not fatal")
    func corruptSidecarIsSkipped() throws {
        // One bad file must not hide the rest of someone's history.
        let store = makeStore()
        let good = try save(store, at: Date(timeIntervalSince1970: 1000))
        try "not json".write(
            to: store.directory.appending(path: "broken.json"),
            atomically: true,
            encoding: .utf8
        )
        #expect(try store.list().map(\.id) == [good.id])
    }

    @Test("An entry whose image is gone is not listed")
    func orphanedSidecarIsSkipped() throws {
        let store = makeStore()
        let item = try save(store, at: Date(timeIntervalSince1970: 1000))
        try FileManager.default.removeItem(at: item.imageURL)
        #expect(try store.list().isEmpty)
    }

    @Test("Delete removes all three files")
    func deleteIsComplete() throws {
        let store = makeStore()
        let item = try save(store, at: Date())
        try store.delete(id: item.id)

        #expect(!FileManager.default.fileExists(atPath: item.imageURL.path))
        #expect(!FileManager.default.fileExists(atPath: item.thumbnailURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: store.directory.appending(path: "\(item.id).json").path
            )
        )
    }

    @Test("Ids that could escape the directory are refused")
    func rejectsPathTraversal() {
        #expect(HistoryStore.isValidID("A1B2-C3D4"))
        #expect(!HistoryStore.isValidID("../../etc/passwd"))
        #expect(!HistoryStore.isValidID("id with spaces"))
        #expect(!HistoryStore.isValidID(""))
    }

    @Test("Clear removes captures but leaves unrelated files alone")
    func clearIsScoped() throws {
        let store = makeStore()
        _ = try save(store, at: Date())
        let bystander = store.directory.appending(path: "notes.txt")
        try "keep me".write(to: bystander, atomically: true, encoding: .utf8)

        try store.clear()
        #expect(try store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: bystander.path))
    }

    @Test("Retention prunes by count, keeping the newest")
    func prunesByCount() throws {
        let store = makeStore()
        var ids: [String] = []
        for second in 1...5 {
            ids.append(try save(store, at: Date(timeIntervalSince1970: TimeInterval(second))).id)
        }
        let pruned = try store.prune(policy: RetentionPolicy(maximumItems: 2))
        #expect(pruned == 3)
        #expect(try store.list().map(\.id) == [ids[4], ids[3]])
    }

    @Test("Retention prunes by age")
    func prunesByAge() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 10_000)
        let stale = try save(store, at: now.addingTimeInterval(-5000))
        let fresh = try save(store, at: now.addingTimeInterval(-10))

        let pruned = try store.prune(
            policy: RetentionPolicy(maximumItems: nil, maximumAge: 1000),
            now: now
        )
        #expect(pruned == 1)
        #expect(try store.list().map(\.id) == [fresh.id])
        #expect(!FileManager.default.fileExists(atPath: stale.imageURL.path))
    }

    @Test("Retention prunes by total size, oldest first")
    func prunesBySize() throws {
        let store = makeStore()
        _ = try save(store, at: Date(timeIntervalSince1970: 1), bytes: 100)
        let newer = try save(store, at: Date(timeIntervalSince1970: 2), bytes: 100)

        // Budget fits one item; the newest survives.
        let pruned = try store.prune(
            policy: RetentionPolicy(maximumItems: nil, maximumBytes: 150)
        )
        #expect(pruned == 1)
        #expect(try store.list().map(\.id) == [newer.id])
    }

    @Test("Total bytes reports what history actually costs")
    func totalBytes() throws {
        let store = makeStore()
        _ = try save(store, at: Date(timeIntervalSince1970: 1), bytes: 400)
        _ = try save(store, at: Date(timeIntervalSince1970: 2), bytes: 600)
        #expect(try store.totalBytes() == 1000)
    }
}
