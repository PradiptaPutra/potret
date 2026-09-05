import AppKit
import PotretCore
import SwiftUI

/// Records a global shortcut.
///
/// Reads `event.keyCode` — the physical key — never the character. On macOS, holding Option
/// rewrites the character a key produces: ⌥4 arrives as "¢" and ⌥A as "å". The Tauri recorder
/// validated `event.key`, which is why it could not record the ⌘⌥ defaults the app itself shipped,
/// and why it happily wrote punctuation its own Rust parser could not understand — bricking every
/// global hotkey until the config was hand-edited.
///
/// Validation happens here, before a combo can be committed, so an unusable shortcut never
/// reaches disk in the first place.
struct ShortcutRecorderField: NSViewRepresentable {
    let id: ShortcutID
    let combo: KeyCombo?
    let existing: [ShortcutID: KeyCombo]
    let onRecord: (KeyCombo) -> Void
    let onReject: (ShortcutRejection) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.configure(id: id, combo: combo, existing: existing,
                       onRecord: onRecord, onReject: onReject)
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.configure(id: id, combo: combo, existing: existing,
                       onRecord: onRecord, onReject: onReject)
    }

    final class RecorderView: NSView {
        private var id: ShortcutID = .captureArea
        private var combo: KeyCombo?
        private var existing: [ShortcutID: KeyCombo] = [:]
        private var onRecord: ((KeyCombo) -> Void)?
        private var onReject: ((ShortcutRejection) -> Void)?
        private var recording = false
        private let label = NSTextField(labelWithString: "")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = Radius.sm
            layer?.cornerCurve = .continuous

            label.alignment = .center
            label.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular
            )
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        func configure(
            id: ShortcutID,
            combo: KeyCombo?,
            existing: [ShortcutID: KeyCombo],
            onRecord: @escaping (KeyCombo) -> Void,
            onReject: @escaping (ShortcutRejection) -> Void
        ) {
            self.id = id
            self.combo = combo
            self.existing = existing
            self.onRecord = onRecord
            self.onReject = onReject
            refresh()
        }

        override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 22) }
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            recording.toggle()
            if recording { window?.makeFirstResponder(self) }
            refresh()
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            refresh()
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else {
                super.keyDown(with: event)
                return
            }
            // Esc abandons recording rather than being reported as an unusable key.
            if event.keyCode == 53 {
                recording = false
                window?.makeFirstResponder(nil)
                refresh()
                return
            }

            let candidate = KeyCombo(
                keyCode: event.keyCode,
                modifiers: Self.modifiers(from: event.modifierFlags)
            )
            // A key we have no name for cannot be displayed or registered; say so rather than
            // storing something that will silently fail later.
            guard KeyCodes.name(for: candidate.keyCode) != nil else {
                onReject?(.needsModifier)
                return
            }
            if let rejection = ShortcutValidator.validate(candidate, for: id, existing: existing) {
                onReject?(rejection)
                return
            }

            combo = candidate
            recording = false
            window?.makeFirstResponder(nil)
            refresh()
            onRecord?(candidate)
        }

        /// Modifier-only presses must not end recording — the user is still reaching for the key.
        override func flagsChanged(with event: NSEvent) {
            super.flagsChanged(with: event)
        }

        private static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
            var result: KeyCombo.Modifiers = []
            if flags.contains(.command) { result.insert(.command) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.control) { result.insert(.control) }
            return result
        }

        private func refresh() {
            label.stringValue = recording
                ? "Press keys…"
                : (combo?.displayString ?? "Not set")
            label.textColor = recording ? .secondaryLabelColor : .labelColor
            layer?.backgroundColor = recording
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                : NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
            layer?.borderWidth = recording ? 1 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            needsDisplay = true
        }
    }
}
