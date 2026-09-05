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
    private static let itemCount = 5

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

    public init(model: HistoryModel, actions: HistoryActions) {
        self.model = model
        self.actions = actions
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
        dwellTask?.cancel()
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func show() {
        model.load(limit: Self.itemCount)
        // Nothing to show is not worth a panel. The Tauri version presented an empty 260×480
        // window in this case — an invisible but fully clickable rectangle over the corner.
        guard !model.items.isEmpty else { return }

        let size = CGSize(width: 300, height: 320)
        let panel = existingListPanel(size: size)
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

/// Compact list for the corner popup.
struct CornerHoverView: View {
    @Bindable var model: HistoryModel
    let actions: HistoryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xs)

            ForEach(model.items) { item in
                Button {
                    actions.copy?(item)
                } label: {
                    HStack(spacing: Space.s) {
                        if let image = model.thumbnail(for: item) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 34)
                                .clipShape(Radius.shape(Radius.sm))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.relativeTime).font(TypeRamp.caption)
                            Text(item.dimensions)
                                .font(TypeRamp.mono)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.accessoryBar)
                .padding(.horizontal, Space.s)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .potretSurface(.popover)
    }
}
