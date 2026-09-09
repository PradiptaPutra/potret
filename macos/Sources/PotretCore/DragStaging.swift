import Foundation

/// Prepares a capture for dragging into another app.
///
/// A history file on disk is named by UUID — `A1B2C3D4-….png` — which is what the receiving app
/// would show if we dragged it directly. Dropping a screenshot into Slack or a chat composer
/// should carry the name the user configured, so the file is copied into a staging directory
/// under its templated name first.
///
/// Staging eagerly, rather than promising the file and writing it on drop, is deliberate: a
/// promise requires the destination to implement `NSFilePromiseReceiver`, and several common drop
/// targets — text fields, chat composers, web views — accept only a plain file URL. A copy of a
/// screenshot is a few hundred kilobytes and takes microseconds.
public enum DragStaging {
    /// Cleared per drag, so a stale file cannot be picked up by the next one.
    public static var directory: URL {
        URL.temporaryDirectory.appending(path: "potret-drag", directoryHint: .isDirectory)
    }

    /// Copy `source` into the staging directory under `name`.
    ///
    /// - Returns: the staged URL, or nil if the copy failed — the caller then declines the drag
    ///   rather than offering something misleading.
    @discardableResult
    public static func stage(
        source: URL,
        name: String,
        in stagingDirectory: URL? = nil
    ) -> URL? {
        let directory = stagingDirectory ?? Self.directory
        do {
            // Recreate the directory each time: leftovers would otherwise accumulate, and a
            // same-named file from a previous drag would silently win.
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let destination = directory.appending(path: name)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// The filename a dragged capture should carry, from the user's template.
    public static func name(
        for template: FilenameTemplate,
        ext: String,
        date: Date = Date()
    ) -> String {
        template.render(ext: ext, date: date)
    }
}
