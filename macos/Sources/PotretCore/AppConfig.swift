import Foundation

/// User settings.
///
/// The wire format is deliberately identical to the Tauri app's `config.json` — same keys, same
/// snake_case — so an existing install's settings are read as-is with no conversion step. Every
/// field has a default, which is what lets an older file (or a newer one written by a future
/// version) decode instead of throwing: a settings file that fails to parse would otherwise reset
/// someone's shortcuts.
public struct AppConfig: Codable, Equatable, Sendable {
    public var shortcutArea: String
    public var shortcutWindow: String
    public var shortcutFullscreen: String
    public var shortcutHistory: String
    public var savePath: String?
    public var format: ImageFormat
    public var jpegQuality: Int
    public var filenameTemplate: String
    public var cornerPopupEnabled: Bool
    /// How many captures to keep; 0 keeps everything. New to the native app — the Tauri build kept
    /// everything forever — so it is absent from older files and defaults.
    public var retentionLimit: Int
    /// Draw the pointer into recordings. Off is right for a UI walkthrough where the pointer is
    /// noise, on for a demo where it is the whole point — so it is a setting, not a guess.
    /// Stills never include the pointer.
    public var recordingShowsCursor: Bool
    /// Draw a ring at each click, into the recording only.
    public var recordingHighlightsClicks: Bool
    /// Seconds counted down before a recording starts, so there is time to arrange the window
    /// being demonstrated. Zero starts immediately.
    public var recordingCountdown: Int

    public enum ImageFormat: String, Codable, Sendable, CaseIterable {
        case png
        case jpg
    }

    private enum CodingKeys: String, CodingKey {
        case shortcutArea = "shortcut_area"
        case shortcutWindow = "shortcut_window"
        case shortcutFullscreen = "shortcut_fullscreen"
        case shortcutHistory = "shortcut_history"
        case savePath = "save_path"
        case format
        case jpegQuality = "jpeg_quality"
        case filenameTemplate = "filename_template"
        case cornerPopupEnabled = "corner_popup_enabled"
        case retentionLimit = "retention_limit"
        case recordingShowsCursor = "recording_shows_cursor"
        case recordingHighlightsClicks = "recording_highlight_clicks"
        case recordingCountdown = "recording_countdown"
    }

    // NOT Cmd+Shift+3/4/5: macOS owns those for its own screenshot tools and swallows the
    // keypress before any app sees it. The Tauri app shipped them as defaults, had to add a
    // migration to move existing users off them, and then reintroduced them through a
    // "Reset to defaults" button that wrote a stale constant.
    public static let `default` = AppConfig(
        shortcutArea: "CommandOrControl+Alt+4",
        shortcutWindow: "CommandOrControl+Alt+5",
        shortcutFullscreen: "CommandOrControl+Alt+3",
        shortcutHistory: "CommandOrControl+Shift+H",
        savePath: nil,
        format: .png,
        jpegQuality: 90,
        filenameTemplate: FilenameTemplate.default.template,
        cornerPopupEnabled: true,
        retentionLimit: 200,
        recordingShowsCursor: true,
        recordingHighlightsClicks: true,
        recordingCountdown: 3
    )

    public init(
        shortcutArea: String,
        shortcutWindow: String,
        shortcutFullscreen: String,
        shortcutHistory: String,
        savePath: String?,
        format: ImageFormat,
        jpegQuality: Int,
        filenameTemplate: String,
        cornerPopupEnabled: Bool,
        retentionLimit: Int = 200,
        recordingShowsCursor: Bool = true,
        recordingHighlightsClicks: Bool = true,
        recordingCountdown: Int = 3
    ) {
        self.shortcutArea = shortcutArea
        self.shortcutWindow = shortcutWindow
        self.shortcutFullscreen = shortcutFullscreen
        self.shortcutHistory = shortcutHistory
        self.savePath = savePath
        self.format = format
        self.jpegQuality = jpegQuality
        self.filenameTemplate = filenameTemplate
        self.cornerPopupEnabled = cornerPopupEnabled
        self.retentionLimit = retentionLimit
        self.recordingShowsCursor = recordingShowsCursor
        self.recordingHighlightsClicks = recordingHighlightsClicks
        self.recordingCountdown = recordingCountdown
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        func string(_ key: CodingKeys, _ fallback: String) -> String {
            ((try? container.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? fallback
        }
        shortcutArea = string(.shortcutArea, fallback.shortcutArea)
        shortcutWindow = string(.shortcutWindow, fallback.shortcutWindow)
        shortcutFullscreen = string(.shortcutFullscreen, fallback.shortcutFullscreen)
        shortcutHistory = string(.shortcutHistory, fallback.shortcutHistory)
        savePath = try? container.decodeIfPresent(String.self, forKey: .savePath)
        format = (try? container.decodeIfPresent(ImageFormat.self, forKey: .format))
            .flatMap { $0 } ?? fallback.format
        jpegQuality = (try? container.decodeIfPresent(Int.self, forKey: .jpegQuality))
            .flatMap { $0 } ?? fallback.jpegQuality
        filenameTemplate = string(.filenameTemplate, fallback.filenameTemplate)
        cornerPopupEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .cornerPopupEnabled))
            .flatMap { $0 } ?? fallback.cornerPopupEnabled
        retentionLimit = (try? container.decodeIfPresent(Int.self, forKey: .retentionLimit))
            .flatMap { $0 } ?? fallback.retentionLimit
        recordingShowsCursor =
            (try? container.decodeIfPresent(Bool.self, forKey: .recordingShowsCursor))
            .flatMap { $0 } ?? fallback.recordingShowsCursor
        recordingHighlightsClicks =
            (try? container.decodeIfPresent(Bool.self, forKey: .recordingHighlightsClicks))
            .flatMap { $0 } ?? fallback.recordingHighlightsClicks
        recordingCountdown =
            (try? container.decodeIfPresent(Int.self, forKey: .recordingCountdown))
            .flatMap { $0 } ?? fallback.recordingCountdown
    }

    /// Clamped so a hand-edited config cannot leave the user staring at a countdown.
    public var clampedRecordingCountdown: Int { min(max(recordingCountdown, 0), 10) }

    /// The retention policy the user chose. This used to be hardcoded to 200 at launch and after
    /// every capture, so the Settings control changed nothing that lasted past a relaunch.
    public var retentionPolicy: RetentionPolicy {
        retentionLimit <= 0 ? .unlimited : RetentionPolicy(maximumItems: retentionLimit)
    }

    /// Clamped so a hand-edited config cannot produce an encoder error at capture time.
    public var clampedJPEGQuality: Int { min(max(jpegQuality, 1), 100) }

    /// Where a capture goes when the user has not chosen a folder.
    ///
    /// One function, one answer. The Tauri app had two independent fallbacks — the Rust side wrote
    /// to `~/Desktop` while Settings displayed "Default (App Support)" — so the UI told users
    /// something the code did not do.
    public static var defaultSaveDirectory: URL {
        URL.desktopDirectory
    }

    public var saveDirectory: URL {
        savePath.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultSaveDirectory
    }
}
