import AppKit
import PotretCore
import SwiftUI

/// Floating pinned captures.
///
/// A pin is a capture you keep on screen while you work. Each gets its own non-activating panel at
/// `.floating`, present on every Space, movable by dragging anywhere on it.
///
/// The Tauri version stored each pinned image as base64 in a Rust-side dictionary keyed by window
/// label, and the window pulled it back over IPC — several megabytes of string per pin, held for
/// the session. Here the panel holds an NSImage.
@MainActor
public final class PinnedController {
    private var panels: [OverlayPanel] = []
    private let onAnnotate: (CGImage, CGSize) -> Void

    public init(onAnnotate: @escaping (CGImage, CGSize) -> Void) {
        self.onAnnotate = onAnnotate
    }

    public func pin(image: CGImage, dragURL: (() -> URL?)? = nil) {
        // Cap the on-screen size: a full-resolution capture pinned at 1:1 would cover the display
        // it came from.
        let maximumWidth: CGFloat = 520
        let pixelSize = CGSize(width: image.width, height: image.height)
        let scale = min(1, maximumWidth / pixelSize.width)
        let size = CGSize(
            width: (pixelSize.width * scale).rounded(),
            height: (pixelSize.height * scale).rounded()
        )

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: .floating
        )
        panel.isMovableByWindowBackground = true
        panel.setFrame(
            PanelPlacement.clamped(
                PanelPlacement.topTrailing(size: size)
            ),
            display: false
        )

        panel.host(
            PinnedView(
                image: NSImage(cgImage: image, size: size),
                dragURL: dragURL,
                onAnnotate: { [weak self] in
                    self?.close(panel)
                    self?.onAnnotate(image, pixelSize)
                },
                onClose: { [weak self] in self?.close(panel) }
            )
        )
        panel.present()
        panels.append(panel)
    }

    public func closeAll() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func close(_ panel: OverlayPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}

/// A pinned capture: the image, with controls on hover.
struct PinnedView: View {
    let image: NSImage
    let dragURL: (() -> URL?)?
    let onAnnotate: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            if hovering {
                HStack(spacing: Space.xs) {
                    control("pencil.tip.crop.circle", "Annotate", action: onAnnotate)
                    control("xmark", "Close", action: onClose)
                }
                .padding(Space.xs)
            }
        }
        .clipShape(Radius.shape(Radius.md))
        .overlay(
            Radius.shape(Radius.md).strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .onHover { hovering = $0 }
        .onDrag {
            guard let url = dragURL?() else { return NSItemProvider() }
            return HistoryActions.imageProvider(for: url)
        }
        .help("Drag to another app · click the pencil to annotate")
    }

    private func control(
        _ symbol: String,
        _ help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
