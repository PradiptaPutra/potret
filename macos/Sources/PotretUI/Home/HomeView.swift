import AppKit
import PotretCore
import SwiftUI

/// What the home window can do.
public struct HomeActions {
    public var captureArea: (() -> Void)?
    public var captureWindow: (() -> Void)?
    public var captureScreen: (() -> Void)?
    public var recordArea: (() -> Void)?
    public var recordWindow: (() -> Void)?
    public var recordScreen: (() -> Void)?
    public var openSettings: (() -> Void)?

    public init() {}
}

/// The app's main window: capture actions on the left, everything you have captured on the right.
///
/// The Tauri version's equivalent was built from inline styles — a hand-rolled sidebar whose hover
/// rule painted a background and a border on an element that had neither, left over from a design
/// that had been removed. This is a system sidebar, so hover, selection and Light/Dark come from
/// AppKit.
public struct HomeView: View {
    @Bindable var model: HistoryModel
    let actions: HomeActions
    let historyActions: HistoryActions
    /// Displayed next to each row, so the window teaches the shortcuts.
    let shortcuts: [ShortcutID: String]

    public init(
        model: HistoryModel,
        actions: HomeActions,
        historyActions: HistoryActions,
        shortcuts: [ShortcutID: String]
    ) {
        self.model = model
        self.actions = actions
        self.historyActions = historyActions
        self.shortcuts = shortcuts
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            HistoryPanelView(
                model: model,
                actions: historyActions,
                captureHint: shortcuts[.captureFullscreen]
            )
            .frame(minWidth: 420)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { model.load() }
    }

    private var sidebar: some View {
        List {
            Section("Capture") {
                row("Area", "viewfinder", shortcuts[.captureArea], actions.captureArea)
                row("Window", "macwindow", shortcuts[.captureWindow], actions.captureWindow)
                row("Screen", "display", shortcuts[.captureFullscreen], actions.captureScreen)
            }

            Section("Record") {
                row("Area", "record.circle", nil, actions.recordArea)
                row("Window", "macwindow.badge.plus", nil, actions.recordWindow)
                row("Screen", "display.and.arrow.down", nil, actions.recordScreen)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    actions.openSettings?()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.link)
                Spacer()
                Text(Self.version)
                    .font(TypeRamp.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
        }
    }

    private func row(
        _ title: String,
        _ symbol: String,
        _ shortcut: String?,
        _ action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer(minLength: Space.s)
                if let shortcut {
                    Text(shortcut)
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    static var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return "v\(value as? String ?? "dev")"
    }
}
