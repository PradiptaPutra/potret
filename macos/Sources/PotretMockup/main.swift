import AppKit
import PotretUI
import SwiftUI

// Offscreen renderer. Xcode isn't installed, so there are no SwiftUI previews — this is how a
// surface gets looked at before it is built, and later how the render tests' golden images are
// produced.
//
// Usage: PotretMockup <output-directory> [sample-image]
//
// Rendering goes through a real (offscreen) NSWindow rather than SwiftUI's ImageRenderer, because
// ImageRenderer cannot draw NSViewRepresentable — and NSVisualEffectView is exactly the thing
// being evaluated. The panels use .withinWindow blending here so the material samples the mock
// desktop backdrop placed behind them in the same window; shipping panels use .behindWindow,
// which samples the real desktop.

let arguments = CommandLine.arguments
let outputDirectory = arguments.count > 1
    ? URL(filePath: arguments[1], directoryHint: .isDirectory)
    : URL.currentDirectory()
let samplePath = arguments.count > 2 ? arguments[2] : "../docs/home.png"

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

enum MockupError: Error {
    case encodingFailed(String)
    case sampleImageMissing(String)
}

@MainActor
func renderPNG<Content: View>(
    _ view: Content,
    size: CGSize,
    appearance: NSAppearance.Name,
    named name: String
) throws {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: appearance)
    window.backgroundColor = .clear
    window.contentView = NSHostingView(rootView: view)
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    guard
        let contentView = window.contentView,
        let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
    else {
        throw MockupError.encodingFailed(name)
    }
    contentView.cacheDisplay(in: contentView.bounds, to: rep)

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw MockupError.encodingFailed(name)
    }
    let url = outputDirectory.appending(path: "\(name).png")
    try png.write(to: url)
    print("wrote \(url.lastPathComponent)  \(Int(size.width))×\(Int(size.height))pt")
}

/// Stands in for the desktop behind a floating panel, so the vibrancy has something to sample and
/// the panel is judged the way it will actually be seen — not against flat grey.
struct MockDesktop<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.55), .purple.opacity(0.45), .orange.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: Space.m) {
                Text(title)
                    .font(TypeRamp.caption)
                    .foregroundStyle(.white.opacity(0.85))
                content
            }
            .padding(Space.xl)
        }
    }
}

// MARK: - Scenes

guard let sample = NSImage(contentsOfFile: samplePath) else {
    throw MockupError.sampleImageMissing(samplePath)
}

let idle = PopupPreview(
    image: sample,
    pixelSize: CGSize(width: 2880, height: 1800),
    progress: 0.62,
    hovering: false
)
let hovered = PopupPreview(
    image: sample,
    pixelSize: CGSize(width: 2880, height: 1800),
    progress: 0.62,
    hovering: true
)

/// All the candidates on one backdrop, so they are compared against each other rather than
/// remembered one file at a time.
struct PopupContactSheet: View {
    let idle: PopupPreview
    let hovered: PopupPreview

    private func labelled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: Space.s) {
            content()
            Text(title)
                .font(TypeRamp.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.55), .purple.opacity(0.45), .orange.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .top, spacing: Space.xl) {
                labelled("A — persistent action bar") { CapturePopupBarVariant(preview: idle) }
                labelled("B — hover reveal (at rest)") { CapturePopupHoverVariant(preview: idle) }
                labelled("B — hovered") { CapturePopupHoverVariant(preview: hovered) }
                labelled("C — trailing action rail") { CapturePopupRailVariant(preview: idle) }
            }
            .padding(Space.xl)
        }
    }
}

let sheetCanvas = CGSize(width: 1220, height: 250)

for (scheme, appearance) in [
    ("light", NSAppearance.Name.aqua),
    ("dark", NSAppearance.Name.darkAqua),
] {
    try renderPNG(
        PopupContactSheet(idle: idle, hovered: hovered),
        size: sheetCanvas, appearance: appearance, named: "popup-variants-\(scheme)"
    )
}

// Tray glyph, at the size AppKit asks for.
try renderPNG(
    Image(nsImage: TrayIcon.image(size: 18)),
    size: CGSize(width: 18, height: 18), appearance: .aqua, named: "tray-icon-18"
)
