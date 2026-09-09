import Foundation

/// Reads and writes `config.json`.
///
/// Two properties matter beyond "it persists":
///
///   * **Atomic writes.** A truncated settings file loses every shortcut, so the write goes to a
///     sibling temp file and is swapped in.
///   * **Coalesced saves.** The Tauri Settings pane called save on every keystroke of the filename
///     template, and each save re-registered all four global hotkeys — thirty keystrokes meant
///     thirty full re-registrations. Here `save` is debounced, and the hotkey layer diffs by value
///     so a template edit cannot touch shortcuts at all.
public actor ConfigStore {
    private let fileURL: URL
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var cached: AppConfig

    public init(
        fileURL: URL,
        debounce: Duration = .milliseconds(400)
    ) {
        self.fileURL = fileURL
        self.debounce = debounce
        self.cached = Self.read(from: fileURL) ?? .default
    }

    public var current: AppConfig { cached }

    /// Decode, tolerating a missing or unreadable file. A settings file that cannot be parsed
    /// falls back to defaults in memory but is NOT overwritten, so a hand-edit with one typo is
    /// recoverable rather than silently destroyed.
    private static func read(from url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// True when a file exists but could not be decoded — the caller can warn instead of
    /// pretending the user had default settings all along.
    public static func isUnreadable(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && read(from: url) == nil
    }

    public func update(_ transform: @Sendable (inout AppConfig) -> Void) {
        var next = cached
        transform(&next)
        guard next != cached else { return } // nothing changed; don't touch the disk
        cached = next
        scheduleWrite()
    }

    private func scheduleWrite() {
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.writeNow()
        }
    }

    /// Force the pending write out — on quit, or before anything that reads the file back.
    public func flush() async {
        pending?.cancel()
        pending = nil
        await writeNow()
    }

    private func writeNow() async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cached) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Atomic: a crash mid-write leaves the previous file intact rather than a truncated one.
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Seed this store from another install's config — used once, so a user upgrading from the
    /// Tauri build keeps their settings, and so a development build can start from the real one.
    /// Never overwrites an existing file.
    public func importIfEmpty(from otherURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              let imported = Self.read(from: otherURL)
        else { return }
        cached = imported
        scheduleWrite()
    }
}
