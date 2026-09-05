import AppKit
import CoreGraphics
import PotretCore

/// Puts an image on the pasteboard.
///
/// One implementation, three lines. The Tauri app had two: the Rust side wrote a temp PNG and
/// shelled out to `osascript` with an AppleScript `«class PNGf»` coercion — which also required
/// an NSAppleEventsUsageDescription and an Automation permission prompt — while the Background
/// tool separately used the browser's navigator.clipboard API.
public enum ClipboardWriter {
    /// Writes PNG plus TIFF. Both, because some older apps only look for TIFF, and the pasteboard
    /// hands each receiver whichever it prefers.
    @MainActor
    public static func write(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
