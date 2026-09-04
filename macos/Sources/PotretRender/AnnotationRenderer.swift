import CoreGraphics
import PotretCore

/// Draws a document into a `CGContext`.
///
/// Deliberately one function serving both the on-screen view and the export path. The Tauri
/// version rendered the canvas for display and re-derived the export separately, which is how
/// annotations ended up landing in a different place on export than where they were drawn.
public enum AnnotationRenderer {
    /// Fills the context with an opaque backdrop. Phase 3 replaces this with the real
    /// document draw; it exists now so the target compiles and is under test from day one.
    public static func drawPlaceholder(into context: CGContext, size: CGSize) {
        context.saveGState()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }
}
