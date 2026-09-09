import AppKit

/// The menu-bar aperture, drawn rather than rasterized.
///
/// Ported from `src-tauri/icons/tray-icon.svg`: six petals at 60° intervals, the three "back"
/// blades at 55% alpha for depth. Drawing it in code means no @1x/@2x PNG pair to generate and
/// keep in sync, and it stays sharp at any status-bar height. As a template image only the
/// alpha channel is read — AppKit tints it for light/dark menu bars and for the highlighted
/// state — so the SVG's white fill is irrelevant and the per-blade opacity is what carries.
public enum TrayIcon {
    /// 18pt, not 22pt: 22 is the menu bar's own height, so a glyph that size leaves no inset.
    public static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }

            // The source art is authored in a 44×44 box with the aperture centred.
            let scale = size / 44
            context.translateBy(x: size / 2, y: size / 2)
            context.scaleBy(x: scale, y: scale)

            for (index, angle) in stride(from: 0.0, to: 360.0, by: 60.0).enumerated() {
                // Back blades sit at 60/180/300° — the odd indices once 0° leads.
                let isBack = index % 2 == 1
                context.saveGState()
                context.rotate(by: angle * .pi / 180)
                context.setAlpha(isBack ? 0.55 : 1.0)
                context.setFillColor(NSColor.black.cgColor)
                context.addPath(bladePath())
                context.fillPath()
                context.restoreGState()
            }
            return true
        }
        // Template images are recoloured by AppKit to match the menu bar.
        image.isTemplate = true
        return image
    }

    /// One petal, pointing up. SVG y-down coordinates negated for AppKit's y-up space.
    private static func bladePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 4.5))
        path.addCurve(
            to: CGPoint(x: 0, y: 24),
            control1: CGPoint(x: 6, y: 9),
            control2: CGPoint(x: 7, y: 18)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 4.5),
            control1: CGPoint(x: -7, y: 18),
            control2: CGPoint(x: -6, y: 9)
        )
        path.closeSubpath()
        return path
    }
}
