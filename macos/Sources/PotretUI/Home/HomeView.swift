import AppKit
import PotretCore
import PotretRecord
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

/// Which captures the grid is showing.
enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case recordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Captures"
        case .screenshots: "Screenshots"
        case .recordings: "Recordings"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .screenshots: "photo"
        case .recordings: "video"
        }
    }

    func matches(_ item: HistoryItem) -> Bool {
        switch self {
        case .all: true
        case .screenshots: !item.isRecording
        case .recordings: item.isRecording
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "No captures yet"
        case .screenshots: "No screenshots yet"
        case .recordings: "No recordings yet"
        }
    }
}

/// The app's main window: sources on the left, captures in a grid.
public struct HomeView: View {
    @Bindable var model: HistoryModel
    let actions: HomeActions
    let historyActions: HistoryActions
    /// Shown beside each action, so the window teaches the shortcuts.
    let shortcuts: [ShortcutID: String]

    @State private var filter: HomeFilter = .all

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

    private var visibleItems: [HistoryItem] {
        model.items.filter(filter.matches)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.load() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $filter) {
            Section("Library") {
                ForEach(HomeFilter.allCases) { option in
                    Label(option.title, systemImage: option.symbol)
                        .tag(option)
                }
            }

            Section("Capture") {
                action("Area", "viewfinder", shortcuts[.captureArea], actions.captureArea)
                action("Window", "macwindow", shortcuts[.captureWindow], actions.captureWindow)
                action("Screen", "display", shortcuts[.captureFullscreen], actions.captureScreen)
            }

            Section("Record") {
                action("Area", "record.circle", nil, actions.recordArea)
                action("Window", "macwindow.on.rectangle", nil, actions.recordWindow)
                action("Screen", "rectangle.dashed.badge.record", nil, actions.recordScreen)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 210)
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

    /// An action row. Not selectable, unlike the library rows above it — clicking runs it.
    private func action(
        _ title: String,
        _ symbol: String,
        _ shortcut: String?,
        _ perform: (() -> Void)?
    ) -> some View {
        Button {
            perform?()
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer(minLength: Space.s)
                if let shortcut {
                    Text(shortcut)
                        .font(TypeRamp.mono)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(perform == nil)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            centred { ProgressView().controlSize(.small) }
        case .failed(let message):
            // Distinct from empty: the captures are still there and something else went wrong.
            centred {
                VStack(spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(TypeRamp.title)
                        .foregroundStyle(.secondary)
                    Text("Couldn't read your captures").font(TypeRamp.body)
                    Text(message)
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { model.load() }.controlSize(.small)
                }
                .padding(Space.xl)
            }
        case .loaded:
            if visibleItems.isEmpty {
                centred {
                    VStack(spacing: Space.s) {
                        Image(systemName: filter.symbol)
                            .font(TypeRamp.title)
                            .foregroundStyle(.tertiary)
                        Text(filter.emptyMessage).font(TypeRamp.body)
                        if let hint = shortcuts[.captureFullscreen] {
                            Text("Press \(hint) to capture your screen")
                                .font(TypeRamp.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: Space.m)],
                spacing: Space.m
            ) {
                ForEach(visibleItems) { item in
                    HomeCard(item: item, model: model, actions: historyActions)
                }
            }
            .padding(Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centred(@ViewBuilder _ content: () -> some View) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return "v\(value as? String ?? "dev")"
    }
}

/// One capture in the grid.
private struct HomeCard: View {
    let item: HistoryItem
    let model: HistoryModel
    let actions: HistoryActions
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            thumbnail
            HStack(spacing: Space.xs) {
                Text(item.relativeTime)
                    .font(TypeRamp.caption)
                Spacer(minLength: 0)
                Text(item.dimensions)
                    .font(TypeRamp.mono)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        // See CornerHoverController: .onDrag consumes the mouse-down, so the click that opens a
        // capture has to be a simultaneous gesture rather than .onTapGesture.
        .onDrag { actions.dragProvider(for: item) }
        .simultaneousGesture(TapGesture().onEnded { actions.annotate?(item) })
        .onHover { hovering = $0 }
        .confirmationDialog("Delete this capture?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { actions.delete?(item) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = model.thumbnail(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.primary.opacity(0.06))
                }
            }
            .frame(height: 124)
            .frame(maxWidth: .infinity)
            .clipped()

            if hovering {
                HStack(spacing: Space.xs) {
                    button(
                        item.isRecording ? "scissors" : "pencil.tip.crop.circle",
                        item.isRecording ? "Trim" : "Annotate"
                    ) { actions.annotate?(item) }
                    button("doc.on.doc", "Copy") { actions.copy?(item) }
                    button("folder", "Show in Finder") { actions.reveal?(item) }
                    button("trash", "Delete") { confirmingDelete = true }
                }
                .padding(Space.xs)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // A recording is otherwise indistinguishable from a still in a grid of thumbnails.
            if let duration = item.duration {
                Label(DurationFormat.clock(duration), systemImage: "video.fill")
                    .font(TypeRamp.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(Space.xs)
            }
        }
        .clipShape(Radius.shape(Radius.md))
        .overlay(
            Radius.shape(Radius.md)
                .strokeBorder(
                    hovering ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: hovering ? 2 : 0.5
                )
        )
    }

    private func button(
        _ symbol: String,
        _ help: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(TypeRamp.caption)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
