import AppKit
import PotretCore
import SwiftUI
import PotretRecord
import UniformTypeIdentifiers

/// What a history row can do. Optional, so actions that belong to later phases simply do not
/// appear rather than showing a button that apologises.
public struct HistoryActions {
    public var copy: ((HistoryItem) -> Void)?
    public var reveal: ((HistoryItem) -> Void)?
    public var delete: ((HistoryItem) -> Void)?
    public var annotate: ((HistoryItem) -> Void)?
    public var clearAll: (() -> Void)?
    /// Stages the capture under its templated name and returns the URL to drag. Nil means this
    /// surface does not support dragging.
    public var dragURL: ((HistoryItem) -> URL?)?
    /// Fired the moment a drag starts, so a surface that auto-hides can hold itself open.
    public var dragBegan: (() -> Void)?

    public init() {}

    /// A drag payload for `onDrag`, or an empty provider when staging failed — returning nil is
    /// not an option there, and an empty provider simply refuses the drop.
    func dragProvider(for item: HistoryItem) -> NSItemProvider {
        // Called at drag start. The corner stack auto-hides on mouse-exit, and the pointer leaves
        // it immediately once a drag begins — without this the panel would tear itself down
        // underneath the drag it just started.
        dragBegan?()
        guard let url = dragURL?(item) else { return NSItemProvider() }
        return Self.imageProvider(for: url)
    }

    /// Advertise the drag as a PNG, in two forms.
    ///
    /// `NSItemProvider(contentsOf:)` registers the item as `public.file-url`, so a destination
    /// that reads text — a chat composer, a web view — receives the string
    /// "file:///var/folders/.../Screenshot.png" instead of a picture. Registering the PNG type
    /// explicitly is what makes those destinations treat it as an image.
    ///
    /// Both a file and a data representation are registered because destinations differ: Finder
    /// and Slack want a file on disk to reference, while web-based composers want the bytes. The
    /// file representation is registered first, so a destination that can take either gets the
    /// one that preserves the filename.
    public static func imageProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        let type = UTType.png.identifier
        provider.suggestedName = url.lastPathComponent

        provider.registerFileRepresentation(
            forTypeIdentifier: type,
            fileOptions: [],
            visibility: .all
        ) { completion in
            // `false` for coordination: the staged file is ours and already written, so the
            // system may read it in place rather than making another copy.
            completion(url, false, nil)
            return nil
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: type,
            visibility: .all
        ) { completion in
            completion(try? Data(contentsOf: url), nil)
            return nil
        }

        return provider
    }
}

/// Recent captures, shown from the menu bar.
public struct HistoryPanelView: View {
    @Bindable private var model: HistoryModel
    private let actions: HistoryActions
    /// The user's actual capture shortcut, shown in the empty state. Hardcoding one would be
    /// wrong for anyone who has changed it — and most people have.
    private let captureHint: String?
    @State private var confirmingClear = false

    public init(model: HistoryModel, actions: HistoryActions, captureHint: String? = nil) {
        self.model = model
        self.actions = actions
        self.captureHint = captureHint
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 340, height: 420)
        .potretSurface(.popover)
    }

    private var header: some View {
        HStack {
            Text("Recent Captures")
                .font(TypeRamp.heading)
            Spacer()
            if !model.items.isEmpty, actions.clearAll != nil {
                Button("Clear All") { confirmingClear = true }
                    .buttonStyle(.link)
                    .font(TypeRamp.caption)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        // A real confirmation, replacing the Tauri app's unconfirmed Clear All — which deleted
        // every capture with one click and no undo.
        .confirmationDialog(
            "Delete all \(model.items.count) captures?",
            isPresented: $confirmingClear
        ) {
            Button("Delete All", role: .destructive) { actions.clearAll?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            centred {
                ProgressView().controlSize(.small)
            }
        case .failed(let message):
            // Distinct from empty, deliberately: the user needs to know their captures are still
            // there and something else went wrong.
            centred {
                VStack(spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(TypeRamp.title)
                        .foregroundStyle(.secondary)
                    Text("Couldn't read your history")
                        .font(TypeRamp.body)
                    Text(message)
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { model.load() }
                        .controlSize(.small)
                }
                .padding(Space.l)
            }
        case .loaded(let items) where items.isEmpty:
            centred {
                VStack(spacing: Space.s) {
                    Image(systemName: "camera")
                        .font(TypeRamp.title)
                        .foregroundStyle(.tertiary)
                    Text("No captures yet")
                        .font(TypeRamp.body)
                    if let captureHint {
                        Text("Press \(captureHint) to capture your screen")
                            .font(TypeRamp.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .loaded(let items):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        HistoryRow(item: item, model: model, actions: actions)
                        Divider().padding(.leading, Space.xxl + Space.xl)
                    }
                }
            }
        }
    }

    private func centred(@ViewBuilder _ content: () -> some View) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let model: HistoryModel
    let actions: HistoryActions
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: Space.m) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.relativeTime)
                    .font(TypeRamp.body)
                Text("\(item.dimensions) · \(item.formattedSize)")
                    .font(TypeRamp.mono)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hovering {
                rowActions
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { actions.annotate?(item) }
        .onDrag { actions.dragProvider(for: item) }
        .confirmationDialog("Delete this capture?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { actions.delete?(item) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.06))
            }
        }
        .frame(width: 64, height: 40)
        .overlay(alignment: .bottomTrailing) {
            // A recording is otherwise indistinguishable from a still in a list of thumbnails.
            if let duration = item.duration {
                Text(DurationFormat.clock(duration))
                    .font(TypeRamp.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.xs)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(2)
            }
        }
        .clipShape(Radius.shape(Radius.sm))
        .overlay(
            Radius.shape(Radius.sm)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var rowActions: some View {
        HStack(spacing: Space.xs) {
            if let copy = actions.copy {
                iconButton("doc.on.doc", "Copy") { copy(item) }
            }
            if let annotate = actions.annotate {
                iconButton("pencil.tip.crop.circle", "Annotate") { annotate(item) }
            }
            if let reveal = actions.reveal {
                iconButton("folder", "Show in Finder") { reveal(item) }
            }
            if actions.delete != nil {
                iconButton("trash", "Delete") { confirmingDelete = true }
            }
        }
    }

    private func iconButton(
        _ symbol: String,
        _ help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).imageScale(.small)
        }
        .buttonStyle(.accessoryBar)
        .help(help)
    }
}
