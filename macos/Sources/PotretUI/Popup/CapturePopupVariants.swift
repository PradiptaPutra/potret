import AppKit
import SwiftUI

// Three directions for the Quick Access popup — the panel that appears bottom-left after every
// capture. Rendered side by side by PotretMockup so the choice is made by looking, not guessing.
//
// Constraints all three share, inherited from how the panel actually behaves:
//   * It is a non-activating NSPanel, so it never takes focus and has no keyboard shortcuts of
//     its own. Every action must be reachable by mouse alone.
//   * The preview image is the drag source for drag-out, so it can never be fully covered by
//     chrome that would eat the drag.
//   * It auto-dismisses after 5s, pausing while hovered or dragged, so the remaining time has to
//     be legible without being loud.

/// What the popup renders. The real panel gets this from the capture pipeline.
public struct PopupPreview {
    public let image: NSImage
    public let pixelSize: CGSize
    /// 1 → full time remaining, 0 → about to dismiss.
    public let progress: Double
    public let hovering: Bool

    public init(image: NSImage, pixelSize: CGSize, progress: Double, hovering: Bool) {
        self.image = image
        self.pixelSize = pixelSize
        self.progress = progress
        self.hovering = hovering
    }

    var dimensions: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }
}

/// Shared icon button. `.accessoryBar` is the system's own toolbar-button style, so it picks up
/// hover, pressed and disabled states for free — the web app had to hand-roll each of those, and
/// got them wrong (its buttons reset to a different colour on mouse-leave than their base style,
/// so they permanently darkened after first hover).
private struct IconButton: View {
    let symbol: String
    let help: String
    var prominent = false

    var body: some View {
        Button {
        } label: {
            Image(systemName: symbol)
                .imageScale(.medium)
                .frame(width: Space.l, height: Space.l)
        }
        .buttonStyle(.accessoryBar)
        .tint(prominent ? Color.accentColor : nil)
        .help(help)
    }
}

/// A thin remaining-time line. Deliberately the accent colour rather than a custom amber, so it
/// matches whatever the user picked in System Settings.
private struct TimeRemaining: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Variant A — persistent action bar

/// Everything visible at all times: preview on top, a system-style action bar beneath.
/// Nothing is hidden behind hover, which is the main complaint about the current popup — new
/// users never discover Pin or Backdrop because they only appear on mouseover.
public struct CapturePopupBarVariant: View {
    let preview: PopupPreview
    public init(preview: PopupPreview) { self.preview = preview }

    public var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: preview.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 132)
                .clipped()

            Divider()

            HStack(spacing: Space.xs) {
                IconButton(symbol: "doc.on.doc", help: "Copy", prominent: true)
                IconButton(symbol: "square.and.arrow.down", help: "Save")
                IconButton(symbol: "pencil.tip.crop.circle", help: "Annotate")
                IconButton(symbol: "pin", help: "Pin to screen")
                IconButton(symbol: "photo.on.rectangle.angled", help: "Add a backdrop")
                Spacer(minLength: 0)
                IconButton(symbol: "xmark", help: "Dismiss")
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)

            TimeRemaining(progress: preview.progress)
        }
        .frame(width: 260)
        .potretSurface(.hud, blending: .withinWindow)
    }
}

// MARK: - Variant B — hover reveal

/// Closest to the shipping popup: a clean preview that reveals its actions on hover.
/// Quietest at rest, and the preview stays a clean drag target — but every action is undiscovered
/// until the pointer lands on it.
public struct CapturePopupHoverVariant: View {
    let preview: PopupPreview
    public init(preview: PopupPreview) { self.preview = preview }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(nsImage: preview.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 146)
                    .clipped()

                if preview.hovering {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: Space.s) {
                                HStack {
                                    IconButton(symbol: "pin", help: "Pin to screen")
                                    Spacer()
                                    IconButton(symbol: "xmark", help: "Dismiss")
                                }
                                Spacer()
                                HStack(spacing: Space.s) {
                                    Button("Copy") {}
                                        .buttonStyle(.borderedProminent)
                                    Button("Save") {}
                                        .buttonStyle(.bordered)
                                }
                                Spacer()
                                HStack {
                                    IconButton(symbol: "pencil.tip.crop.circle", help: "Annotate")
                                    Spacer()
                                    IconButton(
                                        symbol: "photo.on.rectangle.angled",
                                        help: "Add a backdrop"
                                    )
                                }
                            }
                            .padding(Space.s)
                        }
                }
            }

            TimeRemaining(progress: preview.progress)
        }
        .frame(width: 260)
        .potretSurface(.hud, blending: .withinWindow)
    }
}

// MARK: - Variant C — preview with trailing rail

/// Preview and a vertical action rail, with a footer carrying the dimensions.
/// Densest of the three and the only one that tells you what you actually captured — useful when
/// the thumbnail is too small to judge a region crop.
public struct CapturePopupRailVariant: View {
    let preview: PopupPreview
    public init(preview: PopupPreview) { self.preview = preview }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(nsImage: preview.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 212, height: 128)
                    .clipped()

                Divider()

                VStack(spacing: Space.xs) {
                    IconButton(symbol: "doc.on.doc", help: "Copy", prominent: true)
                    IconButton(symbol: "square.and.arrow.down", help: "Save")
                    IconButton(symbol: "pencil.tip.crop.circle", help: "Annotate")
                    IconButton(symbol: "pin", help: "Pin to screen")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.xs)
            }

            Divider()

            HStack(spacing: Space.s) {
                Text(preview.dimensions)
                    .font(TypeRamp.mono)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "hand.draw")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .help("Drag the preview into another app")
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)

            TimeRemaining(progress: preview.progress)
        }
        .frame(width: 260)
        .potretSurface(.hud, blending: .withinWindow)
    }
}
