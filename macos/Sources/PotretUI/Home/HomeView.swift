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

    /// The collapsed rail has no room for words, so the tooltip carries them instead.
    var shortTitle: String {
        switch self {
        case .all: "All"
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

/// One day's captures. The grid used to be one undifferentiated wall of every capture ever
/// taken, and a hundred of those is a pile rather than a history.
private struct DaySection: Identifiable {
    let id: Date
    let title: String
    let items: [HistoryItem]
}

/// The app's main window: a gallery of everything captured, with a sidebar that collapses to a
/// rail when the captures matter more than the navigation.
public struct HomeView: View {
    @Bindable var model: HistoryModel
    let actions: HomeActions
    let historyActions: HistoryActions
    /// Shown beside each action in the capture menus, so the window still teaches the shortcuts.
    let shortcuts: [ShortcutID: String]

    @State private var filter: HomeFilter = .all
    @State private var search = ""
    @State private var newestFirst = true
    /// Whether the sidebar shows labels or collapses to icons.
    ///
    /// In UserDefaults rather than the app's config file: it is window state, it has to survive a
    /// relaunch, and it changes on a click — where `ConfigStore`'s debounced asynchronous write
    /// would be the wrong shape entirely.
    @AppStorage("home.sidebarExpanded") private var sidebarExpanded = true
    @State private var hoveringSidebar = false
    @FocusState private var searchFocused: Bool

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

    // MARK: Data

    private var visibleItems: [HistoryItem] {
        let matching = model.items.filter { filter.matches($0) && matchesSearch($0) }
        return newestFirst ? matching : matching.reversed()
    }

    /// Matches what the user can actually see on a card: when it was taken, how big it is, and
    /// whether it is a recording. There is no filename to search — captures are stored under a
    /// UUID — so offering to search one would find nothing.
    private func matchesSearch(_ item: HistoryItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        let haystack = [
            item.relativeTime,
            item.dimensions,
            Self.dayTitle(for: item.timestamp),
            item.isRecording ? "recording video" : "screenshot image",
        ].joined(separator: " ").lowercased()
        return haystack.contains(query)
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleItems) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return grouped.keys.sorted(by: newestFirst ? (>) : (<)).map { day in
            DaySection(id: day, title: Self.dayTitle(for: day), items: grouped[day] ?? [])
        }
    }

    static func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        // Within the last week a weekday is more use than a date; older than that it is not.
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateStyle = .medium
        }
        return formatter.string(from: date)
    }

    private func count(for filter: HomeFilter) -> Int {
        model.items.filter(filter.matches).count
    }

    // MARK: Layout

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.load() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The traffic lights sit on this material now, so the header starts below them.
            Spacer(minLength: 0)
                .frame(height: MainWindowController.titleBarHeight)

            // The aperture from the app's icon, drawn rather than rasterized, and without the
            // icon's glossy plate behind it: a Mac icon is lit and rounded because it sits in a
            // Dock, and that gloss reads as a sticker once it is dropped into flat sidebar
            // chrome. Same mark, same amber, no shine.
            HStack(spacing: Space.s) {
                Image(nsImage: TrayIcon.image(size: Space.l + Space.xs))
                    .renderingMode(.template)
                    .foregroundStyle(Brand.amber)
                if sidebarExpanded {
                    Text("Potret").font(TypeRamp.heading)
                    Spacer(minLength: 0)
                }
                collapseButton
            }
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .padding(.horizontal, sidebarExpanded ? Space.m : Space.s)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)

            if sidebarExpanded {
                Text("LIBRARY")
                    .font(TypeRamp.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Space.m)
                    .padding(.bottom, Space.xs)
            }

            VStack(spacing: 2) {
                ForEach(HomeFilter.allCases) { option in
                    filterRow(option)
                }
            }
            .padding(.horizontal, Space.s)

            Spacer(minLength: 0)
            Divider()

            Button {
                actions.openSettings?()
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "gearshape")
                        .frame(width: Space.l)
                    if sidebarExpanded {
                        Text("Settings").font(TypeRamp.body)
                        Spacer(minLength: 0)
                        Text(Self.version)
                            .font(TypeRamp.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sidebarExpanded ? "Settings" : "Settings \(Self.version)")
            .padding(.horizontal, sidebarExpanded ? Space.m : Space.s)
            .padding(.vertical, Space.s)
        }
        .frame(width: sidebarExpanded ? 208 : 60)
        .background(VisualEffect(.sidebar))
        .onHover { hoveringSidebar = $0 }
        .animation(Motion.standard, value: sidebarExpanded)
        .animation(Motion.quick, value: hoveringSidebar)
    }

    /// Collapse and expand, in the sidebar rather than the toolbar — it belongs to the thing it
    /// operates. Collapsed, it hides until the pointer is over the rail, so the mark is not
    /// competing with a control in a 60pt column.
    @ViewBuilder
    private var collapseButton: some View {
        if sidebarExpanded || hoveringSidebar {
            Button {
                sidebarExpanded.toggle()
            } label: {
                Image(systemName: sidebarExpanded ? "sidebar.leading" : "sidebar.trailing")
                    .foregroundStyle(.secondary)
                    .frame(width: Space.l, height: Space.l)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sidebarExpanded ? "Hide sidebar" : "Show sidebar")
        }
    }

    private func filterRow(_ option: HomeFilter) -> some View {
        let selected = filter == option
        return Button {
            filter = option
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: option.symbol)
                    .frame(width: Space.l)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                if sidebarExpanded {
                    Text(option.shortTitle).font(TypeRamp.body)
                    Spacer(minLength: 0)
                    Text("\(count(for: option))")
                        .font(TypeRamp.mono)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 2)
            .background(
                selected ? Color.accentColor.opacity(0.16) : .clear,
                in: Radius.shape(Radius.sm)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sidebarExpanded ? option.title : "\(option.title) · \(count(for: option))")
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Space.s) {
            // The primary actions are real buttons here rather than rows buried in a list, and
            // each menu carries its shortcut, so nothing is lost by moving them out of the
            // sidebar.
            Menu {
                menuItem("Area", shortcuts[.captureArea], actions.captureArea)
                menuItem("Window", shortcuts[.captureWindow], actions.captureWindow)
                menuItem("Screen", shortcuts[.captureFullscreen], actions.captureScreen)
            } label: {
                Label("New Capture", systemImage: "plus")
            } primaryAction: {
                actions.captureArea?()
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .fixedSize()

            Menu {
                menuItem("Area", nil, actions.recordArea)
                menuItem("Window", nil, actions.recordWindow)
                menuItem("Screen", nil, actions.recordScreen)
            } label: {
                Label("Record", systemImage: "record.circle")
            } primaryAction: {
                actions.recordArea?()
            }
            .menuStyle(.button)
            .fixedSize()

            Spacer(minLength: Space.m)

            searchField

            Button {
                newestFirst.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .help(newestFirst ? "Newest first" : "Oldest first")
        }
        .padding(.horizontal, Space.m)
        // Clears the traffic lights, which now sit on the window's own material rather than on a
        // separate strip above it.
        .padding(.top, MainWindowController.titleBarHeight - Space.xs)
        .padding(.bottom, Space.s)
    }

    private func menuItem(
        _ title: String, _ shortcut: String?, _ perform: (() -> Void)?
    ) -> some View {
        Button {
            perform?()
        } label: {
            if let shortcut {
                Text("\(title)   \(shortcut)")
            } else {
                Text(title)
            }
        }
        .disabled(perform == nil)
    }

    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(TypeRamp.body)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs + 1)
        .frame(width: 200)
        .background(Color.primary.opacity(0.07), in: Radius.shape(Radius.sm))
        .overlay(
            Radius.shape(Radius.sm).strokeBorder(
                searchFocused ? Color.accentColor : .clear, lineWidth: 1
            )
        )
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
                centred { emptyState }
            } else {
                grid
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        // A search that found nothing is not the same as having nothing, and saying "No captures
        // yet" over a full library would be a lie.
        if !search.isEmpty {
            VStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(TypeRamp.title)
                    .foregroundStyle(.tertiary)
                Text("Nothing matches \u{201C}\(search)\u{201D}").font(TypeRamp.body)
                Button("Clear Search") { search = "" }.controlSize(.small)
            }
        } else {
            VStack(spacing: Space.s) {
                Image(systemName: filter.symbol)
                    .font(TypeRamp.title)
                    .foregroundStyle(.tertiary)
                Text(filter.emptyMessage).font(TypeRamp.body)
                if let hint = shortcuts[.captureArea] {
                    Text("Press \(hint) to capture an area")
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.l, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 190), spacing: Space.m)],
                            spacing: Space.m
                        ) {
                            ForEach(section.items) { item in
                                HomeCard(item: item, model: model, actions: historyActions)
                            }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(section.title).font(TypeRamp.heading)
                            Text("\(section.items.count)")
                                .font(TypeRamp.caption)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.xs)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .padding(Space.l)
        }
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
        .onHover { hovering = $0 }
        .confirmationDialog("Delete this capture?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { actions.delete?(item) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            // Fits inside the card rather than filling it. Filling meant a 77x80 capture was
            // blown up into a 16:10 hole and cropped, so a small capture was unrecognisable and
            // a tall one lost its top and bottom.
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    if let image = model.thumbnail(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            // A card shows a whole screen at about a ninth of its size, so the
                            // resampling quality is the difference between small text reading as
                            // text and reading as smear. The default is cheaper and looks it.
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .padding(Space.xs)
                    } else {
                        Image(systemName: item.isRecording ? "video" : "photo")
                            .font(TypeRamp.title)
                            .foregroundStyle(.tertiary)
                    }
                }
                .background(Color.primary.opacity(0.06))
                // Drag out, or click to open. The buttons below sit above this in the ZStack and
                // keep their own clicks.
                .overlay(
                    actions.dragSource(for: item, image: model.thumbnail(for: item)) {
                        actions.annotate?(item)
                    }
                )

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
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.08), radius: hovering ? 10 : 3, y: 2)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(Motion.quick, value: hovering)
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
