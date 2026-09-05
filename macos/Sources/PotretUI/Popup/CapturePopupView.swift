import AppKit
import SwiftUI

/// Actions the Quick Access popup can perform. Closures rather than a delegate so the view stays
/// previewable in the mockup renderer with no coordinator attached.
///
/// Each is optional and a nil action hides its button. The editor and backdrop tool land in later
/// phases, and a visible button that answers "not yet" is worse than no button — the Tauri popup
/// advertised a Cmd+C shortcut in a tooltip that was never bound.
public struct CapturePopupActions {
    public var copy: (() -> Void)?
    public var save: (() -> Void)?
    public var annotate: (() -> Void)?
    public var pin: (() -> Void)?
    public var backdrop: (() -> Void)?
    public var dismiss: (() -> Void)?
    /// Stages the capture and returns a URL to drag out of the preview.
    public var dragURL: (() -> URL?)?
    /// Fired when a drag starts, so the auto-dismiss countdown can be held.
    public var dragBegan: (() -> Void)?
    /// Fired when the drag ends; `true` if something accepted the drop.
    public var dragEnded: ((Bool) -> Void)?

    public init() {}
}

/// What the popup renders.
public struct PopupPreview {
    public let image: NSImage
    public let pixelSize: CGSize
    /// 1 → full time remaining, 0 → about to dismiss.
    public var progress: Double
    /// Transient confirmation ("Copied", "Saved to Desktop"), shown in place of the action bar.
    public var flash: String?

    public init(image: NSImage, pixelSize: CGSize, progress: Double = 1, flash: String? = nil) {
        self.image = image
        self.pixelSize = pixelSize
        self.progress = progress
        self.flash = flash
    }
}

/// Toolbar button. `.accessoryBar` is the system's own toolbar-button style, so hover, pressed and
/// disabled states come from AppKit. The web app hand-rolled each of those and got them wrong: its
/// buttons reset to a different colour on mouse-leave than their base style, so every button
/// permanently darkened after being hovered once.
private struct IconButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                Image(systemName: symbol)
                    .imageScale(.medium)
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .tint(prominent ? Color.accentColor : nil)
            .help(help)
        }
    }
}

/// Remaining-time line. Accent-coloured rather than a bespoke amber, so it matches whatever the
/// user chose in System Settings.
private struct TimeRemaining: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 2)
    }
}

/// The Quick Access popup: preview on top, persistent action bar beneath.
///
/// Every action is visible at rest. The Tauri popup hid all six behind hover, so Pin and Backdrop
/// were effectively undiscoverable — you had to already know they were there to find them.
public struct CapturePopupView: View {
    let preview: PopupPreview
    let actions: CapturePopupActions

    public init(preview: PopupPreview, actions: CapturePopupActions = CapturePopupActions()) {
        self.preview = preview
        self.actions = actions
    }

    public static let width: CGFloat = 260
    public static let imageHeight: CGFloat = 132
    /// Image + divider + action bar + progress. Fixed, so the panel does not resize per capture —
    /// a popup that changes shape between screenshots reads as jitter.
    public static let height: CGFloat = imageHeight + 1 + 30 + 2

    public var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: preview.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.width, height: Self.imageHeight)
                .clipped()
                .accessibilityLabel("Capture preview. Drag to another app.")
                // An AppKit drag source rather than .onDrag. This view re-evaluates twenty times
                // a second for the countdown, and SwiftUI's drag tracking was reset on every one
                // of them before the gesture could cross its threshold — so the preview never
                // dragged at all. See FileDragSource.
                .overlay(
                    FileDragSource(
                        provideURL: { actions.dragURL?() },
                        dragImage: preview.image,
                        // Hold the countdown: a drag started at second four must not have its
                        // source dismissed mid-gesture.
                        onBegan: { actions.dragBegan?() },
                        onEnded: { accepted in actions.dragEnded?(accepted) }
                    )
                )

            Divider()

            ZStack {
                if let flash = preview.flash {
                    Text(flash)
                        .font(TypeRamp.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    HStack(spacing: Space.xs) {
                        IconButton(symbol: "doc.on.doc", help: "Copy", prominent: true,
                                   action: actions.copy)
                        IconButton(symbol: "square.and.arrow.down", help: "Save",
                                   action: actions.save)
                        IconButton(symbol: "pencil.tip.crop.circle", help: "Annotate",
                                   action: actions.annotate)
                        IconButton(symbol: "pin", help: "Pin to screen", action: actions.pin)
                        IconButton(symbol: "photo.on.rectangle.angled", help: "Add a backdrop",
                                   action: actions.backdrop)
                        Spacer(minLength: 0)
                        IconButton(symbol: "xmark", help: "Dismiss", action: actions.dismiss)
                    }
                    .padding(.horizontal, Space.s)
                }
            }
            .frame(height: 30)

            TimeRemaining(progress: preview.progress)
        }
        .frame(width: Self.width, height: Self.height)
        .potretSurface(.hud)
    }
}
