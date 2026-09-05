import AppKit
import Observation
import PotretCapture
import PotretCore
import ServiceManagement
import SwiftUI

/// State behind the Settings window.
///
/// Every mutation writes through `ConfigStore`, which debounces and coalesces. That is what stops
/// the Tauri behaviour where typing in the filename template called save on every keystroke — and
/// each save re-registered all four global hotkeys, so thirty characters meant thirty full
/// re-registrations. Here a template edit cannot touch shortcuts at all: they are a different
/// field, and the hotkey layer diffs by value.
@MainActor
@Observable
public final class SettingsModel {
    private let configStore: ConfigStore
    private let historyStore: HistoryStore
    private let applyShortcuts: ([ShortcutID: KeyCombo]) -> [ShortcutID: HotKeyError]

    public var shortcuts: [ShortcutID: KeyCombo] = [:]
    public var shortcutFailures: [ShortcutID: HotKeyError] = [:]
    /// Last refusal from the recorder, shown inline under the shortcut rows.
    public var rejection: ShortcutRejection?

    public var launchAtLogin = false {
        didSet { guard launchAtLogin != oldValue else { return }; updateLoginItem() }
    }
    public var cornerPopupEnabled = true {
        didSet {
            let value = cornerPopupEnabled
            write { $0.cornerPopupEnabled = value }
        }
    }
    public var format: AppConfig.ImageFormat = .png {
        didSet {
            let value = format
            write { $0.format = value }
        }
    }
    public var jpegQuality: Double = 90 {
        didSet {
            let value = Int(jpegQuality)
            write { $0.jpegQuality = value }
        }
    }
    public var filenameTemplate: String = "" {
        didSet {
            let value = filenameTemplate
            write { $0.filenameTemplate = value }
        }
    }
    public var retentionLimit: Int = 200 {
        didSet { applyRetention() }
    }
    public private(set) var savePath: String?
    public private(set) var permissionGranted = false
    public private(set) var historyBytes = 0

    public init(
        configStore: ConfigStore,
        historyStore: HistoryStore,
        applyShortcuts: @escaping ([ShortcutID: KeyCombo]) -> [ShortcutID: HotKeyError]
    ) {
        self.configStore = configStore
        self.historyStore = historyStore
        self.applyShortcuts = applyShortcuts
    }

    // MARK: Presentation

    public var saveDirectoryLabel: String {
        savePath.map { URL(filePath: $0).lastPathComponent }
            ?? "\(AppConfig.defaultSaveDirectory.lastPathComponent) (default)"
    }

    public var historySizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(historyBytes), countStyle: .file)
    }

    public var filenamePreview: String {
        FilenameTemplate(filenameTemplate).render(ext: format.rawValue)
    }

    // MARK: Loading

    public func refresh() {
        Task {
            let config = await configStore.current
            cornerPopupEnabled = config.cornerPopupEnabled
            format = config.format
            jpegQuality = Double(config.clampedJPEGQuality)
            filenameTemplate = config.filenameTemplate
            savePath = config.savePath
            shortcuts = LegacyShortcutMigration.migrate(config).combos
            permissionGranted = CapturePermission.isGranted
            launchAtLogin = SMAppService.mainApp.status == .enabled
            historyBytes = (try? historyStore.totalBytes()) ?? 0
        }
    }

    // MARK: Mutations

    public func setShortcut(_ combo: KeyCombo, for id: ShortcutID) {
        rejection = nil
        shortcuts[id] = combo
        shortcutFailures = applyShortcuts(shortcuts)
        let encoded = Self.legacyString(combo)
        write {
            switch id {
            case .captureArea: $0.shortcutArea = encoded
            case .captureWindow: $0.shortcutWindow = encoded
            case .captureFullscreen: $0.shortcutFullscreen = encoded
            case .recentCaptures: $0.shortcutHistory = encoded
            }
        }
    }

    public func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        savePath = path
        write { $0.savePath = path }
    }

    public func resetSaveDirectory() {
        savePath = nil
        write { $0.savePath = nil }
    }

    public func openPermissionSettings() {
        CapturePermission.request()
        NSWorkspace.shared.open(CapturePermission.settingsURL)
    }

    // MARK: Internals

    private func write(_ transform: @escaping @Sendable (inout AppConfig) -> Void) {
        Task { await configStore.update(transform) }
    }

    private func applyRetention() {
        let policy = retentionLimit == 0
            ? RetentionPolicy.unlimited
            : RetentionPolicy(maximumItems: retentionLimit)
        Task {
            _ = try? historyStore.prune(policy: policy)
            historyBytes = (try? historyStore.totalBytes()) ?? 0
        }
    }

    /// SMAppService replaces the LaunchAgent plist the Tauri autostart plugin wrote. That stale
    /// plist still points at the old bundle and is cleaned up separately at first launch.
    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.ui.error("login item change failed: \(error.localizedDescription, privacy: .public)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// Config on disk keeps the Tauri string format, so the two builds stay interchangeable during
    /// the migration and a downgrade does not lose the user's shortcuts.
    private static func legacyString(_ combo: KeyCombo) -> String {
        var parts: [String] = []
        if combo.modifiers.contains(.command) { parts.append("CommandOrControl") }
        if combo.modifiers.contains(.shift) { parts.append("Shift") }
        if combo.modifiers.contains(.option) { parts.append("Alt") }
        if combo.modifiers.contains(.control) { parts.append("Control") }
        parts.append(KeyCodes.name(for: combo.keyCode) ?? "")
        return parts.joined(separator: "+")
    }
}
