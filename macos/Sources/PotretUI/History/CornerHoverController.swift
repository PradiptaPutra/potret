import AppKit
import PotretCore
import SwiftUI

/// Recent captures on hovering the bottom-left corner of the screen.
///
/// The trigger is an invisible 4×4pt panel with an `NSTrackingArea`, not a polling loop. The Tauri
/// version ran a timer every 80ms for the life of the app, reading the cursor position and keeping
/// dwell counters and an "away ticks" watchdog in Rust — roughly 43,000 wake-ups an hour to notice
/// a corner the user touches a few times a day. A tracking area is a callback: zero cost at rest.
@MainActor
public final class CornerHoverController {
    /// The corner is also where the Dock, the Trash and window-minimise targets live, so an
    /// instant trigger fires constantly while merely passing through.
    private static let dwell: Duration = .milliseconds(120)
    /// Leaving is debounced so crossing the gap between hot zone and panel does not close it.
    private static let closeDelay: Duration = .milliseconds(260)
    private static let hotZone: CGFloat = 4

    private var hotPanel: OverlayPanel?
    private var listPanel: OverlayPanel?
    private var dwellTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private let model: HistoryModel
    private var actions: HistoryActions

    public var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? install() : uninstall()
        }
    }

    /// True while a drag started from a card is still in flight.
    private var dragging = false

    public init(model: HistoryModel, actions: HistoryActions) {
        self.model = model
        self.actions = actions
    }

    /// Replace the action set. Actions that need the coordinator itself are attached after
    /// initialisation, so this arrives once rather than being threaded through init.
    public func updateActions(_ actions: HistoryActions) {
        var actions = actions
        // Hold the stack open for the duration of a drag, then resume normal hide behaviour once
        // the pointer comes back or the session ends.
        actions.dragBegan = { [weak self] in
            guard let self else { return }
            self.dragging = true
            self.closeTask?.cancel()
            self.dragEndWatchdog()
        }
        // Deleting shrinks the stack, so the panel has to shrink with it. Left as it was, the
        // panel kept its old height with the cards re-laid out inside it — the "broken after
        // delete" state. And the shared model reloads without a limit, so the view must cap what
        // it shows itself.
        actions.dragEnded = { [weak self] accepted in
            guard let self else { return }
            self.dragging = false
            // Dropped somewhere: the card went where it was going, so the stack can go.
            if accepted { self.hide() } else { self.scheduleHide() }
        }
        let delete = actions.delete
        actions.delete = { [weak self] item in
            delete?(item)
            self?.relayoutAfterChange()
        }
        self.actions = actions
    }

    private func relayoutAfterChange() {
        guard let listPanel, listPanel.isVisible else { return }
        let count = min(model.items.count, CornerHoverView.itemCount)
        guard count > 0 else {
            hide()
            return
        }
        let size = CornerHoverView.panelSize(itemCount: count)
        listPanel.setFrame(
            PanelPlacement.clamped(PanelPlacement.bottomLeading(size: size), on: NSScreen.main),
            display: true
        )
    }

    /// A drag ends outside our control — there is no completion callback on the SwiftUI path — so
    /// the hold is released once no mouse button is down any more.
    private func dragEndWatchdog() {
        Task { [weak self] in
            while self?.dragging == true {
                try? await Task.sleep(for: .milliseconds(150))
                if NSEvent.pressedMouseButtons == 0 {
                    self?.dragging = false
                    self?.scheduleHide()
                    return
                }
            }
        }
    }

    public func install() {
        guard isEnabled, hotPanel == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: Self.hotZone,
            height: Self.hotZone
        )
        let panel = OverlayPanel(contentRect: frame, level: .statusBar)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0.01 // present for hit-testing, invisible to the eye

        let view = HotZoneView(frame: NSRect(origin: .zero, size: frame.size))
        view.onEnter = { [weak self] in self?.scheduleShow() }
        view.onExit = { [weak self] in self?.scheduleHide() }
        panel.contentView = view
        panel.present()
        hotPanel = panel
    }

    public func uninstall() {
        dwellTask?.cancel()
        closeTask?.cancel()
        hotPanel?.orderOut(nil)
        hotPanel = nil
        listPanel?.orderOut(nil)
        listPanel = nil
    }

    // MARK: Show / hide

    private func scheduleShow() {
        closeTask?.cancel()
        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func scheduleHide() {
        // Never pull the panel out from under an in-flight drag.
        guard !dragging else { return }
        dwellTask?.cancel()
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Force the stack open, for verification without a pointer.
    public func showNow() { show() }

    private func show() {
        model.load(limit: CornerHoverView.itemCount)
        // Nothing to show is not worth a panel. The Tauri version presented an empty 260×480
        // window in this case — an invisible but fully clickable rectangle over the corner.
        guard !model.items.isEmpty else { return }

        let size = CornerHoverView.panelSize(
            itemCount: min(model.items.count, CornerHoverView.itemCount)
        )
        let panel = existingListPanel(size: size)
        panel.setContentSize(size)
        panel.setFrame(
            PanelPlacement.clamped(
                PanelPlacement.bottomLeading(size: size),
                on: NSScreen.main
            ),
            display: false
        )
        panel.host(
            CornerHoverView(model: model, actions: actions)
                .onHover { [weak self] inside in
                    inside == true ? self?.closeTask?.cancel() : self?.scheduleHide()
                }
        )
        panel.present()
    }

    private func hide() {
        listPanel?.orderOut(nil)
    }

    private func existingListPanel(size: CGSize) -> OverlayPanel {
        if let listPanel { return listPanel }
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: .statusBar
        )
        // The cards carry their own shadows; a panel shadow would outline a rectangle around a
        // stack that is supposed to read as loose cards on the desktop.
        panel.hasShadow = false
        listPanel = panel
        return panel
    }

    /// Invisible hit target at the corner.
    private final class HotZoneView: NSView {
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    // .activeAlways — the app is never frontmost, so anything else gets nothing.
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) { onEnter?() }
        override func mouseExited(with event: NSEvent) { onExit?() }
    }
}

/// Floating cards at the corner — no frame, no header, no background.
///
/// This is the shape the Tauri app shipped and the one CleanShot uses: the captures themselves
/// stacked at the corner, newest nearest it, each carrying its own shadow. An earlier attempt here
/// wrapped them in a bordered popover list, which read as a panel that happened to contain
/// pictures rather than as the pictures themselves.
///
/// A fanned or cascading arrangement is deliberately absent — it was built once and removed after
/// user feedback (issues #2/#3).
struct CornerHoverView: View {
    @Bindable var model: HistoryModel
    let actions: HistoryActions
    @State private var hovered: String?
    /// Pointer is over a card's action buttons; a click there must not also open the capture.
    @State private var overActions = false

    static let itemCount = 5
    static let cardWidth: CGFloat = 190
    static let cardHeight: CGFloat = cardWidth * 10 / 16
    static let spacing = Space.s
    static let padding = Space.m

    static func panelSize(itemCount: Int) -> CGSize {
        CGSize(
            width: cardWidth + padding * 2,
            height: CGFloat(itemCount) * cardHeight
                + CGFloat(max(0, itemCount - 1)) * spacing
                + padding * 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            // Reversed so the newest card sits at the bottom of the stack, closest to the corner
            // the pointer just came from.
            ForEach(model.items.prefix(Self.itemCount).reversed()) { item in
                card(for: item)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func card(for item: HistoryItem) -> some View {
        let isHovered = hovered == item.id
        return ZStack(alignment: .topTrailing) {
            Group {
                if let image = model.thumbnail(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.black.opacity(0.4))
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            // Drag out or click to open, through the AppKit drag source. The action buttons come
            // later in this ZStack, so they sit above it and keep their own clicks.
            .overlay(
                actions.dragSource(for: item, image: model.thumbnail(for: item)) {
                    Log.ui.info("corner card clicked")
                    actions.annotate?(item)
                }
            )

            if isHovered {
                HStack(spacing: Space.xs) {
                    // Annotate gets an explicit button as well as the click-through below.
                    // A bare click is not discoverable, and on macOS it also competes with the
                    // drag gesture on the same view.
                    action("pencil.tip.crop.circle", "Annotate") { actions.annotate?(item) }
                    action("doc.on.doc", "Copy") { actions.copy?(item) }
                    action("folder", "Show in Finder") { actions.reveal?(item) }
                    action("trash", "Delete") { actions.delete?(item) }
                }
                .padding(Space.xs)
                .onHover { overActions = $0 }
            }
        }
        .clipShape(Radius.shape(Radius.md))
        .overlay(
            Radius.shape(Radius.md)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        // Two shadows: a tight contact shadow keeps the card anchored to the desktop, a wide soft
        // one gives it height. One shadow alone reads as either floating or flat.
        .shadow(color: .black.opacity(isHovered ? 0.45 : 0.35),
                radius: isHovered ? 18 : 12, y: isHovered ? 10 : 6)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .scaleEffect(isHovered ? 1.02 : 1)
        .offset(y: isHovered ? -2 : 0)
        .animation(Motion.quick, value: isHovered)
        .onHover { hovered = $0 ? item.id : nil }
        .help("\(item.relativeTime) · \(item.dimensions) — click to annotate, or drag out")
    }

    private func action(
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
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
