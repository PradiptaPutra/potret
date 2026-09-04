import AppKit
import PotretUI

// Offscreen renderer. Xcode isn't installed, so there are no SwiftUI previews — this is how a
// surface gets looked at before it is built, and later how the render tests' golden images are
// produced. Usage: PotretMockup <output-directory>
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
    : URL.currentDirectory()

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

/// Writes an NSImage to disk as PNG at its natural size.
func writePNG(_ image: NSImage, named name: String) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw MockupError.encodingFailed(name)
    }
    let url = outputDirectory.appending(path: "\(name).png")
    try png.write(to: url)
    print("wrote \(url.path)")
}

enum MockupError: Error { case encodingFailed(String) }

// Phase 0 smoke test: prove the offscreen pipeline works end to end by rendering the tray glyph
// at the two sizes AppKit would ask for.
try writePNG(TrayIcon.image(size: 18), named: "tray-icon-18")
try writePNG(TrayIcon.image(size: 36), named: "tray-icon-36")
