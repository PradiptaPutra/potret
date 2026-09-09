import Foundation

/// Renders a user's filename template, mirroring `render_filename` in the Tauri backend so
/// existing templates keep producing the same names after the rewrite.
///
/// Tokens: `{date}` `{time}` `{unix}` `{seq}`.
public struct FilenameTemplate: Sendable {
    public let template: String

    public init(_ template: String) {
        self.template = template
    }

    public static let `default` = FilenameTemplate("Screenshot {date} at {time}")

    /// Characters that are illegal in a filename, or merely a bad idea. `/` is the path separator
    /// and `:` is how Finder still renders it, so leaving either in place would let a template
    /// write outside the intended directory.
    private static let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// - Parameters:
    ///   - ext: extension without the dot.
    ///   - date: injected rather than read from the clock, so this is testable.
    ///   - sequence: value for `{seq}`.
    public func render(
        ext: String,
        date: Date = Date(),
        sequence: Int = 0,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX") // stable regardless of user locale

        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH-mm-ss"
        let time = formatter.string(from: date)

        var name = template
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{unix}", with: String(Int(date.timeIntervalSince1970)))
            .replacingOccurrences(of: "{seq}", with: String(sequence))

        name = String(
            String.UnicodeScalarView(
                name.unicodeScalars.map { Self.illegal.contains($0) ? "-" : $0 }
            )
        )
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "Screenshot \(Int(date.timeIntervalSince1970))"
        }
        return "\(name).\(ext)"
    }

    /// A path in `directory` that does not already exist, appending `-1`, `-2`, … on collision.
    ///
    /// Capped so a pathological directory cannot spin: after `limit` attempts it falls back to a
    /// UUID suffix, which is guaranteed free and still readable.
    public func uniqueURL(
        in directory: URL,
        ext: String,
        date: Date = Date(),
        limit: Int = 1000,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let rendered = render(ext: ext, date: date)
        let base = String(rendered.dropLast(ext.count + 1)) // strip ".ext"

        let first = directory.appending(path: rendered)
        if !exists(first) { return first }

        for sequence in 1..<limit {
            let candidate = directory.appending(path: "\(base)-\(sequence).\(ext)")
            if !exists(candidate) { return candidate }
        }
        return directory.appending(path: "\(base)-\(UUID().uuidString).\(ext)")
    }
}
