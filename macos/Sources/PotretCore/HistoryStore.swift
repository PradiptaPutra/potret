import CoreGraphics
import Foundation

/// One entry in the capture history.
public struct HistoryItem: Sendable, Equatable, Identifiable {
    public let id: String
    /// The capture itself: a PNG for a still, an MP4 for a recording.
    public let imageURL: URL
    public let thumbnailURL: URL
    public let timestamp: Date
    public let pixelSize: CGSize
    public let fileSize: Int
    /// Present only for recordings, which is also how the two are told apart.
    public let duration: TimeInterval?

    public init(
        id: String,
        imageURL: URL,
        thumbnailURL: URL,
        timestamp: Date,
        pixelSize: CGSize,
        fileSize: Int,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.timestamp = timestamp
        self.pixelSize = pixelSize
        self.fileSize = fileSize
        self.duration = duration
    }

    public var isRecording: Bool { duration != nil }
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
    /// Recordings only. Absent in every file the Tauri app wrote, hence optional — its presence
    /// is what marks an entry as video.
    let duration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case width
        case height
        case fileSize = "file_size"
        case duration
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
/// What can go wrong operating on a specific entry.
public enum HistoryError: Error, LocalizedError {
    case invalidID
    case notFound

    public var errorDescription: String? {
        switch self {
        case .invalidID: "That capture's identifier is not valid."
        case .notFound: "That capture is no longer in your history."
        }
    }
}

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
    private func videoURL(_ id: String) -> URL { directory.appending(path: "\(id).mp4") }
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
            fileSize: imageData.count,
            duration: nil
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

    /// Store a finished recording. The video is moved rather than copied — it is already written
    /// to a temp file, and copying a large MP4 twice is pure cost.
    @discardableResult
    public func saveRecording(
        videoURL source: URL,
        thumbnailData: Data,
        pixelSize: CGSize,
        duration: TimeInterval,
        now: Date = Date()
    ) throws -> HistoryItem {
        try createDirectoryIfNeeded()
        let id = UUID().uuidString
        let destination = videoURL(id)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
        try thumbnailData.write(to: thumbnailURL(id), options: .atomic)

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = (attributes?[.size] as? Int) ?? 0

        let metadata = HistoryMetadata(
            id: id,
            timestamp: Int(now.timeIntervalSince1970),
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            fileSize: fileSize,
            duration: duration
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL(id), options: .atomic)

        return HistoryItem(
            id: id,
            imageURL: destination,
            thumbnailURL: thumbnailURL(id),
            timestamp: now,
            pixelSize: pixelSize,
            fileSize: fileSize,
            duration: duration
        )
    }

    /// Swap a stored recording's video for an edited one, keeping its id, its place in the
    /// timeline, and its thumbnail slot.
    ///
    /// Trimming used to write the shortened file to the user's save folder and leave history
    /// holding the original, so the grid kept showing — and re-opening — the full-length take.
    /// The edit is applied to the library entry as well, which is what makes it stick.
    @discardableResult
    public func replaceRecording(
        id: String,
        videoURL source: URL,
        thumbnailData: Data,
        duration: TimeInterval
    ) throws -> HistoryItem {
        guard Self.isValidID(id) else { throw HistoryError.invalidID }
        guard let existing = try list().first(where: { $0.id == id }) else {
            throw HistoryError.notFound
        }

        let destination = videoURL(id)
        // Replace in place. The source is a temp file we own, so moving is safe and avoids
        // writing a second full copy of a video that may be hundreds of megabytes.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
        try thumbnailData.write(to: thumbnailURL(id), options: .atomic)

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = (attributes?[.size] as? Int) ?? 0

        // Timestamp is deliberately preserved: this is the same capture, edited, and re-dating it
        // would jump it to the top of a grid the user is already looking at.
        let metadata = HistoryMetadata(
            id: id,
            timestamp: Int(existing.timestamp.timeIntervalSince1970),
            width: Int(existing.pixelSize.width),
            height: Int(existing.pixelSize.height),
            fileSize: fileSize,
            duration: duration
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL(id), options: .atomic)

        return HistoryItem(
            id: id,
            imageURL: destination,
            thumbnailURL: thumbnailURL(id),
            timestamp: existing.timestamp,
            pixelSize: existing.pixelSize,
            fileSize: fileSize,
            duration: duration
        )
    }

    /// Delete files this store could have written that no longer belong to any entry.
    ///
    /// Two ways they appear: a crash between writing the media and writing its sidecar, and the
    /// trimmer, which used to write `trimmed-<uuid>.mp4` and `<uuid>.gif` straight into this
    /// directory and never remove them. Nothing could reach those files — `list` only reads
    /// `.json`, so delete, clear, retention and the size readout all skipped them — and they
    /// accumulated with every edit.
    ///
    /// Conservative on purpose: only names this store's own code produces are considered, so a
    /// file a user dropped in here by hand is still left alone.
    @discardableResult
    public func sweepOrphans() throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let known = Set(try list().map(\.id))
        var removed = 0

        for name in names {
            let url = directory.appending(path: name)
            let doomed: Bool

            if name.hasPrefix("trimmed-"), name.hasSuffix(".mp4") {
                // Always a leftover: a kept trim is moved over the entry it belongs to.
                doomed = true
            } else if name.hasSuffix(".gif") {
                doomed = true
            } else if let id = Self.ownedFileID(name) {
                doomed = !known.contains(id)
            } else {
                doomed = false
            }

            if doomed, (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// The entry id a file belongs to, if the name is one this store writes.
    private static func ownedFileID(_ name: String) -> String? {
        for suffix in [".thumb.png", ".png", ".mp4", ".json"] where name.hasSuffix(suffix) {
            let id = String(name.dropLast(suffix.count))
            return isValidID(id) ? id : nil
        }
        return nil
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
                let metadata = try? JSONDecoder().decode(HistoryMetadata.self, from: data)
            else { continue }

            // A recording's media is the MP4; a still's is the PNG.
            let media = metadata.duration == nil ? imageURL(metadata.id) : videoURL(metadata.id)
            guard FileManager.default.fileExists(atPath: media.path) else { continue }

            items.append(
                HistoryItem(
                    id: metadata.id,
                    imageURL: media,
                    thumbnailURL: thumbnailURL(metadata.id),
                    timestamp: Date(timeIntervalSince1970: TimeInterval(metadata.timestamp)),
                    pixelSize: CGSize(width: metadata.width, height: metadata.height),
                    fileSize: metadata.fileSize,
                    duration: metadata.duration
                )
            )
        }

        items.sort { $0.timestamp > $1.timestamp }
        if let limit { items = Array(items.prefix(limit)) }
        return items
    }

    public func delete(id: String) throws {
        guard Self.isValidID(id) else { return }
        for url in [imageURL(id), videoURL(id), metadataURL(id), thumbnailURL(id)] {
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
