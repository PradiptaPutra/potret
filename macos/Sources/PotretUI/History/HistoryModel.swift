import AppKit
import Observation
import PotretCore

/// Backing store for the history panels.
///
/// Loading is explicitly three-state — idle, loaded, failed — because the Tauri frontend collapsed
/// every failure into an empty array with a comment reading "Backend command may not exist yet".
/// A history that failed to load was therefore indistinguishable from an empty one, and the user
/// was shown "No captures yet" over a directory full of their screenshots.
@MainActor
@Observable
public final class HistoryModel {
    public enum State {
        case loading
        case loaded([HistoryItem])
        case failed(String)
    }

    public private(set) var state: State = .loading
    private let store: HistoryStore
    private var thumbnails: [String: NSImage] = [:]

    public init(store: HistoryStore) {
        self.store = store
    }

    public func load(limit: Int? = nil) {
        do {
            state = .loaded(try store.list(limit: limit))
        } catch {
            Log.history.error("history load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public var items: [HistoryItem] {
        if case .loaded(let items) = state { return items }
        return []
    }

    /// Thumbnails are cached because a panel re-renders on every hover and decoding a PNG per
    /// frame is visible as stutter.
    public func thumbnail(for item: HistoryItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let image = NSImage(contentsOf: item.thumbnailURL) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    public func fullImage(for item: HistoryItem) -> NSImage? {
        NSImage(contentsOf: item.imageURL)
    }

    public func delete(_ item: HistoryItem) {
        do {
            try store.delete(id: item.id)
            thumbnails[item.id] = nil
            load()
        } catch {
            Log.history.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clearAll() {
        do {
            try store.clear()
            thumbnails.removeAll()
            load()
        } catch {
            Log.history.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func totalBytes() -> Int {
        (try? store.totalBytes()) ?? 0
    }
}

extension HistoryItem {
    /// "just now", "12 min ago", "Yesterday", "Mon 3" — the same shape the web app used, but from
    /// the system formatter, so it is localised and respects the user's settings.
    public var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    public var dimensions: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
