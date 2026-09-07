import AppKit
import SwiftUI

// The only file in the project allowed to hold a numeric or colour literal for chrome.
// scripts/lint-design.sh enforces that. The Tauri app had a complete set of design tokens in
// src/index.css that roughly half its components ignored, which is how it accumulated twelve
// corner radii, eight font sizes, two greens and two different toggle designs.

/// 4pt grid. Every gap, pad and inset comes from here.
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Three radii, not twelve. Always `.continuous` — a circular corner is the clearest tell of a
/// non-native Mac app, because every macOS surface uses the squircle.
public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14

    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// Semantic type roles. Five, replacing the eight ad-hoc sizes the web app used.
/// Never `.system(size:)` — these scale with the user's text-size settings, fixed points don't.
public enum TypeRamp {
    public static let title = Font.title2.weight(.semibold)
    public static let heading = Font.headline
    public static let body = Font.body
    public static let secondary = Font.callout
    public static let caption = Font.caption
    /// Dimensions, file sizes, filenames — anything where digits should not jitter.
    public static let mono = Font.caption.monospacedDigit()
    /// The self-timer digit. The one fixed size: it has to be legible from across the room,
    /// not track the reading-text setting.
    public static let countdown = Font.system(size: 88, weight: .bold, design: .rounded)
        .monospacedDigit()

    /// Ink: text whose size comes from the document, not from the design system. An annotation's
    /// point size is data the user chose and the renderer honours, so it cannot come from the
    /// ramp — but it still goes through here, so Theme stays the only place fonts are built.
    public static func ink(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// AppKit equivalents, for the surfaces drawn with CGContext and NSAttributedString rather
    /// than SwiftUI — the selector overlay repaints per mouse-move and draws its text directly.
    /// NSFont is not Sendable, so these are computed rather than stored — an NSFont held in a
    /// static `let` is a shared mutable global as far as strict concurrency is concerned. They are
    /// cheap: the font cache makes each call a lookup.
    @MainActor
    public enum AppKit {
        /// Dimension readout. Monospaced digits so the numbers do not jitter as a drag resizes.
        public static var badge: NSFont {
            NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }
        /// Instructional text on an overlay.
        public static var hint: NSFont {
            NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        /// A menu section label. System sizes, so it tracks the user's menu-bar text size.
        public static var menuSectionHeader: NSFont {
            NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        }

        /// A shortcut glyph shown on the right of a menu row.
        public static var menuShortcut: NSFont {
            NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
    }
}

public enum Motion {
    /// Every animation goes through here so Reduce Motion is honoured in exactly one place.
    private static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static var quick: Animation? { reduced ? nil : .easeOut(duration: 0.15) }
    public static var standard: Animation? { reduced ? nil : .easeInOut(duration: 0.22) }
    public static var spring: Animation? {
        reduced ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }
}

/// Named materials, so surfaces are chosen by role rather than by picking a blur radius.
/// The web app used backdrop-filter at 8, 10, 12, 14, 16 and 20px across different windows and
/// omitted it entirely on one — none of it real macOS vibrancy.
public enum Surface {
    case popover
    case hud
    case sidebar
    case window

    var material: NSVisualEffectView.Material {
        switch self {
        case .popover: .popover
        case .hud: .hudWindow
        case .sidebar: .sidebar
        case .window: .underWindowBackground
        }
    }
}

/// Real `NSVisualEffectView`, which is the thing a webview cannot have.
///
/// `blendingMode` matters: `.behindWindow` samples the desktop behind the window and is what
/// shipping panels use. `.withinWindow` samples sibling views in the same window — which is how
/// the mockup renderer gets a truthful material over a stand-in backdrop, since an offscreen
/// window has nothing behind it to sample.
public struct VisualEffect: NSViewRepresentable {
    private let surface: Surface
    private let blending: NSVisualEffectView.BlendingMode

    public init(_ surface: Surface, blending: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.surface = surface
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = surface.material
        view.blendingMode = blending
        view.state = .active // stay vivid even when the app is not frontmost
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = surface.material
        view.blendingMode = blending
    }
}

/// How vibrancy blends, overridable from the environment.
///
/// Shipping panels sample the desktop behind the window (`.behindWindow`). An offscreen render
/// has nothing behind it, so the mockup renderer flips this to `.withinWindow` and puts a stand-in
/// desktop in the same window — which means mockups show the real material rather than a flat
/// approximation, and view code never has to know a mockup exists.
private struct SurfaceBlendingKey: EnvironmentKey {
    static let defaultValue: NSVisualEffectView.BlendingMode = .behindWindow
}

extension EnvironmentValues {
    public var surfaceBlending: NSVisualEffectView.BlendingMode {
        get { self[SurfaceBlendingKey.self] }
        set { self[SurfaceBlendingKey.self] = newValue }
    }
}

private struct SurfaceModifier: ViewModifier {
    @Environment(\.surfaceBlending) private var blending
    let surface: Surface
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(VisualEffect(surface, blending: blending))
            .clipShape(Radius.shape(radius))
            .overlay(
                Radius.shape(radius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Standard treatment for a floating panel: material, squircle, hairline border.
    public func potretSurface(_ surface: Surface, radius: CGFloat = Radius.lg) -> some View {
        modifier(SurfaceModifier(surface: surface, radius: radius))
    }
}
