import AppKit
import Observation
import PotretCore
import SwiftUI

/// What the user came to the selector to do. Decides which action the bar makes prominent and
/// which one Return triggers.
public enum SelectionIntent: Sendable, Equatable {
    case capture
    case record
}

/// State the options bar reads. One instance per selection session, shared by the bar on every
/// screen, so the size fields on whichever screen holds the selection stay in step.
@MainActor
@Observable
public final class SelectionBarModel {
    public var intent: SelectionIntent = .capture
    /// Pixel dimensions as text, because they are edited in place.
    public var widthText = ""
    public var heightText = ""
    public var aspectLocked = false
    /// "16:9" when the selection is a common ratio; shown beside the lock so the user knows
    /// what they are locking.
    public var aspectName: String?
    public var frozen = false
    /// Self-timer in seconds. Zero means capture immediately.
    public var delay = 0

    public init() {}

    /// Bring the fields in line with the selection, in pixels.
    public func reflect(pixelSize: CGSize) {
        widthText = String(Int(pixelSize.width.rounded()))
        heightText = String(Int(pixelSize.height.rounded()))
        aspectName = SelectionGeometry.namedAspect(of: pixelSize)
    }
}

/// What the bar can do. Closures rather than a delegate so the coordinator can wire them
/// without the bar knowing about panels or screens.
public struct SelectionBarActions {
    public var capture: () -> Void = {}
    public var record: () -> Void = {}
    public var toggleFreeze: () -> Void = {}
    public var toggleAspectLock: () -> Void = {}
    public var cancel: () -> Void = {}
    /// The user typed a size and pressed Return. Pixels.
    public var setSize: (Int, Int) -> Void = { _, _ in }
    /// Editing a field is over, one way or another: hand the keyboard back to the overlay so
    /// Return captures and Esc cancels again.
    public var endEditing: () -> Void = {}

    public init() {}
}

/// The strip under a finished selection: capture / record / timer / freeze, the size, cancel.
///
/// Icons only. It appears under every area selection, so it has to stay small enough not to
/// cover what was just selected; every button carries a tooltip with its key.
public struct SelectionBarView: View {
    @Bindable var model: SelectionBarModel
    let actions: SelectionBarActions
    @FocusState private var focused: Field?

    private enum Field { case width, height }

    public init(model: SelectionBarModel, actions: SelectionBarActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            tool(
                "camera.viewfinder", "Capture",
                key: model.intent == .capture ? "↩" : nil,
                primary: model.intent == .capture,
                perform: actions.capture
            )
            tool(
                "record.circle", "Record",
                key: model.intent == .record ? "↩" : nil,
                primary: model.intent == .record,
                perform: actions.record
            )
            timerMenu
            tool(
                "snowflake", model.frozen ? "Unfreeze screen" : "Freeze screen",
                key: "F", active: model.frozen, perform: actions.toggleFreeze
            )

            divider

            sizeField("W", text: $model.widthText, field: .width)
            Text("×")
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
            sizeField("H", text: $model.heightText, field: .height)
            aspectLock

            divider

            tool("xmark", "Cancel", key: "esc", quiet: true, perform: actions.cancel)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .potretSurface(.hud, radius: Radius.md)
        .fixedSize()
        .onChange(of: focused) { _, now in
            if now == nil { actions.endEditing() }
        }
    }

    // MARK: Pieces

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(width: 1, height: Space.l)
            .padding(.horizontal, Space.xs)
    }

    private func tool(
        _ symbol: String,
        _ title: String,
        key: String? = nil,
        primary: Bool = false,
        active: Bool = false,
        quiet: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            ToolGlyph(symbol: symbol, primary: primary, active: active, quiet: quiet)
        }
        .buttonStyle(.plain)
        .help(key.map { "\(title)  \($0)" } ?? title)
    }

    /// Self-timer. A menu rather than a toggle: the delay is a choice, and a badge on the icon
    /// shows the current one so the state is never hidden.
    private var timerMenu: some View {
        Menu {
            Button("No delay") { model.delay = 0 }
            Divider()
            ForEach([3, 5, 10], id: \.self) { seconds in
                Button("\(seconds) seconds") { model.delay = seconds }
            }
        } label: {
            ToolGlyph(symbol: "timer", active: model.delay > 0)
                .overlay(alignment: .bottomTrailing) {
                    if model.delay > 0 {
                        Text("\(model.delay)")
                            .font(TypeRamp.mono)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.delay > 0 ? "Self-timer: \(model.delay)s" : "Self-timer")
    }

    private func sizeField(_ label: String, text: Binding<String>, field: Field) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.plain)
            .font(TypeRamp.mono)
            .multilineTextAlignment(.trailing)
            .frame(width: Space.xxl + Space.m)
            .padding(.horizontal, Space.xs + 2)
            .padding(.vertical, 2)
            .background(.white.opacity(0.08), in: Radius.shape(Radius.sm))
            .overlay(
                Radius.shape(Radius.sm)
                    .strokeBorder(
                        focused == field ? Color.accentColor : .white.opacity(0.12),
                        lineWidth: focused == field ? 1 : 0.5
                    )
            )
            .focused($focused, equals: field)
            .onSubmit(submitSize)
            .onExitCommand { focused = nil }
    }

    private func submitSize() {
        if let width = Int(model.widthText), let height = Int(model.heightText),
           width > 0, height > 0 {
            actions.setSize(width, height)
        }
        focused = nil
    }

    private var aspectLock: some View {
        Button(action: actions.toggleAspectLock) {
            HStack(spacing: 2) {
                Image(systemName: model.aspectLocked ? "lock.fill" : "lock.open")
                if let name = model.aspectName {
                    Text(name)
                }
            }
            .font(TypeRamp.mono)
            .foregroundStyle(model.aspectLocked ? Color.accentColor : Color.secondary)
            .padding(.leading, Space.xs)
        }
        .buttonStyle(.plain)
        .help(model.aspectLocked ? "Unlock aspect ratio" : "Lock aspect ratio")
    }
}

/// One tool's glyph. `primary` is the action Return triggers; `active` a toggle that is on.
private struct ToolGlyph: View {
    let symbol: String
    var primary = false
    var active = false
    var quiet = false

    var body: some View {
        Image(systemName: symbol)
            .font(TypeRamp.body.weight(.medium))
            .foregroundStyle(
                primary ? Color.white : active ? Color.accentColor : quiet ? Color.secondary : Color.primary
            )
            .frame(width: Space.xl + Space.xs, height: Space.xl + Space.xs)
            .background(
                primary ? Color.accentColor : Color.clear,
                in: Radius.shape(Radius.sm)
            )
            .contentShape(Radius.shape(Radius.sm))
    }
}
