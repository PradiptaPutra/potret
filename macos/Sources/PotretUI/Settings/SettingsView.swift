import AppKit
import PotretCapture
import PotretCore
import SwiftUI

/// Everything the app can be configured to do.
///
/// A system `Form` with `.grouped` style, so it looks and behaves like System Settings: correct
/// row metrics, correct Light/Dark, correct focus ring, correct behaviour under Increase Contrast.
/// The Tauri Settings pane rebuilt all of that by hand from inline styles, and ended up with two
/// different toggle designs and a `div[tabIndex]` standing in for a button.
public struct SettingsView: View {
    @Bindable var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Toggle("Show recent captures on hover", isOn: $model.cornerPopupEnabled)
            } header: {
                Text("General")
            } footer: {
                Text("Hover the bottom-left corner of the screen to see your last few captures.")
                    .font(TypeRamp.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ForEach(ShortcutID.allCases, id: \.self) { id in
                    shortcutRow(id)
                }
                if let rejection = model.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.triangle")
                        .font(TypeRamp.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.saveDirectoryLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { model.chooseSaveDirectory() }
                        if model.savePath != nil {
                            Button("Reset") { model.resetSaveDirectory() }
                        }
                    }
                }
                Picker("Format", selection: $model.format) {
                    Text("PNG").tag(AppConfig.ImageFormat.png)
                    Text("JPEG").tag(AppConfig.ImageFormat.jpg)
                }
                .pickerStyle(.segmented)

                if model.format == .jpg {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $model.jpegQuality, in: 10...100, step: 5)
                            Text("\(Int(model.jpegQuality))")
                                .font(TypeRamp.mono)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }

                LabeledContent("Filename") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        TextField("Template", text: $model.filenameTemplate)
                        Text(model.filenamePreview)
                            .font(TypeRamp.mono)
                            .foregroundStyle(.secondary)
                        Text("{date} {time} {unix} {seq}")
                            .font(TypeRamp.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                Toggle("Show the pointer", isOn: $model.recordingShowsCursor)
                Toggle("Highlight clicks", isOn: $model.recordingHighlightsClicks)
                LabeledContent("Countdown") {
                    Picker("", selection: $model.recordingCountdown) {
                        Text("None").tag(0)
                        Text("3 seconds").tag(3)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Recording")
            } footer: {
                Text("A ring marks every click in the video without appearing on your screen. The countdown gives you time to arrange the window you are demonstrating. Screenshots never include the pointer.")
                    .font(TypeRamp.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Keep") {
                    Picker("", selection: $model.retentionLimit) {
                        Text("Last 50").tag(50)
                        Text("Last 200").tag(200)
                        Text("Last 1000").tag(1000)
                        Text("Everything").tag(0)
                    }
                    .labelsHidden()
                }
                LabeledContent("On disk", value: model.historySizeLabel)
            } header: {
                Text("History")
            } footer: {
                // The Tauri app kept every capture forever while showing only the newest 50, so
                // this number was invisible and unbounded.
                Text("Older captures are removed automatically.")
                    .font(TypeRamp.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permission") {
                LabeledContent("Screen Recording") {
                    HStack(spacing: Space.s) {
                        Label(
                            model.permissionGranted ? "Granted" : "Not granted",
                            systemImage: model.permissionGranted
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(model.permissionGranted ? .green : .orange)
                        if !model.permissionGranted {
                            Button("Open Settings") { model.openPermissionSettings() }
                        }
                    }
                }
                if !model.permissionGranted {
                    Text("Potret cannot capture anything until this is granted. "
                         + "macOS applies the change after the app is relaunched.")
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear { model.refresh() }
    }

    private func shortcutRow(_ id: ShortcutID) -> some View {
        LabeledContent(id.label) {
            HStack(spacing: Space.s) {
                if let failure = model.shortcutFailures[id] {
                    // A hotkey another app already owns is otherwise invisible until you press it.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(failure.message)
                }
                ShortcutRecorderField(
                    id: id,
                    combo: model.shortcuts[id],
                    existing: model.shortcuts,
                    onRecord: { model.setShortcut($0, for: id) },
                    onReject: { model.rejection = $0 }
                )
                .frame(width: 110, height: 22)
            }
        }
    }
}
