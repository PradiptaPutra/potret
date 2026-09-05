import CoreGraphics
import Foundation

/// One entry in the capture history.
public struct HistoryItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let imageURL: URL
    public let thumbnailURL: URL
    public let timestamp: Date
    public let pixelSize: CGSize
    public let fileSize: Int

    public init(
        id: String,
        imageURL: URL,
        thumbnailURL: URL,
        timestamp: Date,
        pixelSize: CGSize,
        fileSize: Int
    ) {
        self.id = id
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.timestamp = timestamp
        self.pixelSize = pixelSize
        self.fileSize = fileSize
    }
}

/// On-disk metadata. Field names match the Tauri app's sidecar JSON exactly, so an existing
/// history directory is readable with no migration step and no import screen.
struct HistoryMetadata: Codable {
    let id: String
    /// Unix seconds, as the Rust side wrote it.
    let timestamp: Int
    let width: Int
    let height: Int
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case width
        case height
        case fileSize = "file_size"
    }
}

/// How much history to keep.
///
/// The Tauri app had no policy at all: it wrote a full-resolution PNG plus a thumbnail for every
/// capture forever, while the UI only ever displayed the newest 50. A year of daily use left
/// hundreds of megabytes nobody could see or reach.
public struct RetentionPolicy: Sendable, Equatable {
    public var maximumItems: Int?
    public var maximumAge: TimeInterval?
    public var maximumBytes: Int?

    public init(maximumItems: Int? = 200, maximumAge: TimeInterval? = nil, maximumBytes: Int? = nil) {
        self.maximumItems = maximumItems
        self.maximumAge = maximumAge
        self.maximumBytes = maximumBytes
    }

    public static let unlimited = RetentionPolicy(maximumItems: nil)

    /// Which items to drop, given everything currently stored, newest first.
    func itemsToPrune(from items: [HistoryItem], now: Date = Date()) -> [HistoryItem] {
        var keep = items
        var drop: [HistoryItem] = []

        if let maximumAge {
            let cutoff = now.addingTimeInterval(-maximumAge)
            let expired = keep.filter { $0.timestamp < cutoff }
            drop.append(contentsOf: expired)
            keep.removeAll { $0.timestamp < cutoff }
        }
        if let maximumItems, keep.count > maximumItems {
            drop.append(contentsOf: keep[maximumItems...])
            keep = Array(keep[..<maximumItems])
        }
        if let maximumBytes {
            var running = 0
            var overflow: [HistoryItem] = []
            for item in keep {
                running += item.fileSize
                if running > maximumBytes { overflow.append(item) }
            }
            drop.append(contentsOf: overflow)
        }
        return drop
    }
}

/// Reads and writes the capture history directory.
///
/// Errors surface as thrown errors rather than being swallowed. The Tauri frontend caught every
/// failure into an empty array with a comment reading "Backend command may not exist yet", so a
/// history that failed to load looked exactly like a history that was empty — the user was shown
/// "No captures yet" over a directory full of their screenshots.
public struct HistoryStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Guard against a crafted id escaping the history directory. Ids are UUIDs; anything else is
    /// refused rather than sanitised, because there is no legitimate source of one.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    private func imageURL(_ id: String) -> URL { directory.appending(path: "\(id).png") }
    private func metadataURL(_ id: String) -> URL { directory.appending(path: "\(id).json") }
    private func thumbnailURL(_ id: String) -> URL { directory.appending(path: "\(id).thumb.png") }

    public func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Store a capture. Writes the same three files the Tauri app did, so both versions can read
    /// the directory during the migration period.
    @discardableResult
    public func save(
        imageData: Data,
        thumbnailData: Data,
        pixelSize: CGSize,
        now: Date = Date()
    ) throws -> HistoryItem {
        try createDirectoryIfNeeded()
        let id = UUID().uuidString

        try imageData.write(to: imageURL(id), options: .atomic)
        try thumbnailData.write(to: thumbnailURL(id), options: .atomic)

        let metadata = HistoryMetadata(
            id: id,
            timestamp: Int(now.timeIntervalSince1970),
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            fileSize: imageData.count
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL(id), options: .atomic)

        return HistoryItem(
            id: id,
            imageURL: imageURL(id),
            thumbnailURL: thumbnailURL(id),
            timestamp: now,
            pixelSize: pixelSize,
            fileSize: imageData.count
        )
    }

    /// Newest first. A single corrupt sidecar is skipped rather than failing the whole listing —
    /// one bad file should not hide the rest of someone's history.
    public func list(limit: Int? = nil) throws -> [HistoryItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        var items: [HistoryItem] = []
        for name in names where name.hasSuffix(".json") {
            let url = directory.appending(path: name)
            guard
                let data = try? Data(contentsOf: url),
                let metadata = try? JSONDecoder().decode(HistoryMetadata.self, from: data),
                FileManager.default.fileExists(atPath: imageURL(metadata.id).path)
            else { continue }

            items.append(
                HistoryItem(
                    id: metadata.id,
                    imageURL: imageURL(metadata.id),
                    thumbnailURL: thumbnailURL(metadata.id),
                    timestamp: Date(timeIntervalSince1970: TimeInterval(metadata.timestamp)),
                    pixelSize: CGSize(width: metadata.width, height: metadata.height),
                    fileSize: metadata.fileSize
                )
            )
        }

        items.sort { $0.timestamp > $1.timestamp }
        if let limit { items = Array(items.prefix(limit)) }
        return items
    }

    public func delete(id: String) throws {
        guard Self.isValidID(id) else { return }
        for url in [imageURL(id), metadataURL(id), thumbnailURL(id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Remove every capture. Only touches the three file types this store owns, so an unrelated
    /// file that ended up in the directory is left alone.
    public func clear() throws {
        for item in try list() {
            try delete(id: item.id)
        }
    }

    /// Apply a retention policy. Called after each save and on launch.
    @discardableResult
    public func prune(policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        let items = try list()
        let doomed = policy.itemsToPrune(from: items, now: now)
        for item in doomed {
            try delete(id: item.id)
        }
        return doomed.count
    }

    /// Total bytes on disk, so Settings can show what history actually costs.
    public func totalBytes() throws -> Int {
        try list().reduce(0) { $0 + $1.fileSize }
    }
}
