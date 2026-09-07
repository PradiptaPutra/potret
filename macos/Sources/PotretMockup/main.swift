import AVFoundation
import AppKit
import PotretCore
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
    // Offscreen windows have nothing behind them, so vibrancy has to sample within.
    window.contentView = NSHostingView(
        rootView: view.environment(\.surfaceBlending, .withinWindow)
    )
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
    progress: 0.62
)
let confirming = PopupPreview(
    image: sample,
    pixelSize: CGSize(width: 2880, height: 1800),
    progress: 0.62,
    flash: "Copied"
)

/// The popup in both of its states, on a backdrop, so the material has something to sample.
struct PopupSheet: View {
    let idle: PopupPreview
    let confirming: PopupPreview

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.55), .purple.opacity(0.45), .orange.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .top, spacing: Space.xl) {
                CapturePopupView(preview: idle)
                CapturePopupView(preview: confirming)
            }
            .padding(Space.xl)
        }
    }
}

let sheetCanvas = CGSize(width: 620, height: 220)

for (scheme, appearance) in [
    ("light", NSAppearance.Name.aqua),
    ("dark", NSAppearance.Name.darkAqua),
] {
    try renderPNG(
        PopupSheet(idle: idle, confirming: confirming),
        size: sheetCanvas, appearance: appearance, named: "popup-\(scheme)"
    )
}

/// Editor with a marker at a known document position.
///
/// Document space is y-down, so a rect at y = 0 must appear at the TOP of the canvas. If the
/// renderer and the view disagree about orientation it lands at the bottom instead — which is
/// exactly the double-flip bug this scene exists to catch.
@MainActor
func renderEditorOrientation() throws {
    let width = 400, height = 300
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }
    context.setFillColor(CGColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let source = context.makeImage() else { return }
    _ = source

    var document = AnnotationDocument(sourceSize: CGSize(width: width, height: height))
    let style = AnnotationElement.Style(color: AnnotationPalette.red, lineWidth: 6)
    // Marker hugging the TOP-LEFT of the document.
    document.elements = [
        AnnotationElement(kind: .rectangle(CGRect(x: 10, y: 10, width: 120, height: 60)), style: style),
        AnnotationElement(
            kind: .arrow(from: CGPoint(x: 20, y: 90), to: CGPoint(x: 200, y: 250)),
            style: AnnotationElement.Style(color: AnnotationPalette.green, lineWidth: 6)
        ),
        AnnotationElement(
            kind: .text(.init(string: "TOP", origin: CGPoint(x: 150, y: 16), fontSize: 34)),
            style: AnnotationElement.Style(color: AnnotationPalette.yellow, lineWidth: 3)
        ),
    ]

    // Use a real screenshot rather than a flat fill, so the render shows whether downscaled
    // detail survives — which is what "blurry in the editor" was about.
    guard
        let realSource = sample.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }
    document = AnnotationDocument(
        sourceSize: CGSize(width: realSource.width, height: realSource.height)
    )
    document.elements = [
        AnnotationElement(
            kind: .rectangle(CGRect(x: 40, y: 40, width: 400, height: 200)), style: style
        ),
        AnnotationElement(
            kind: .text(.init(string: "TOP-LEFT", origin: CGPoint(x: 460, y: 48), fontSize: 64)),
            style: AnnotationElement.Style(color: AnnotationPalette.yellow, lineWidth: 3)
        ),
    ]

    // With a backdrop, so the gradient, rounded corners and the drop shadow are all visible —
    // the shadow being the feature the old tool silently never drew.
    document.background = Backdrop(
        paddingFraction: 0.05, cornerFraction: 0.012, shadow: .default, fill: .gradient(.twilight)
    )

    let model = EditorModel(document: document, source: realSource) { _ in }
    try renderPNG(
        EditorView(model: model),
        size: CGSize(width: 760, height: 560), appearance: .darkAqua,
        named: "editor-orientation"
    )
}

try renderEditorOrientation()

// Tray glyph, at the size AppKit asks for.
try renderPNG(
    Image(nsImage: TrayIcon.image(size: 18)),
    size: CGSize(width: 18, height: 18), appearance: .aqua, named: "tray-icon-18"
)

// The post-selection options bar, over a real capture, in both intents. HUD chrome is dark in
// either appearance and the shipping panel pins `.darkAqua`, so one appearance is enough.
struct SelectionBarScene: View {
    let sample: NSImage
    let model: SelectionBarModel

    var body: some View {
        ZStack {
            Image(nsImage: sample).resizable().scaledToFill()
            Color.black.opacity(0.35)
            SelectionBarView(model: model, actions: SelectionBarActions())
        }
    }
}

let captureBar = SelectionBarModel()
captureBar.reflect(pixelSize: CGSize(width: 1920, height: 1080))
let recordBar = SelectionBarModel()
recordBar.intent = .record
recordBar.delay = 5
recordBar.frozen = true
recordBar.aspectLocked = true
recordBar.reflect(pixelSize: CGSize(width: 1000, height: 700))
for (name, model) in [("capture", captureBar), ("record", recordBar)] {
    try renderPNG(
        SelectionBarScene(sample: sample, model: model),
        size: CGSize(width: 520, height: 120), appearance: .darkAqua,
        named: "selection-bar-\(name)"
    )
}
