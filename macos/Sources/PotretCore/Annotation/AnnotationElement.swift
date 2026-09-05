import CoreGraphics
import Foundation

/// One annotation.
///
/// A real enum with associated values, not the Tauri app's single struct with eleven optional
/// fields where a `pen` carried unused `x/y/w/h` and a `rect` carried an unused `points` array.
/// The compiler now enforces that every kind is handled everywhere.
public struct AnnotationElement: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var kind: Kind
    public var style: Style

    public init(id: UUID = UUID(), kind: Kind, style: Style) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    public enum Kind: Equatable, Codable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case freehand([CGPoint])
        case highlight([CGPoint])
        case text(TextContent)
        case step(center: CGPoint, number: Int)
        case pixelate(CGRect)
        case blur(CGRect)

        /// Whether this kind is an image effect rather than ink. Effects composite into a cached
        /// layer, so moving a shape does not force them to recompute.
        public var isEffect: Bool {
            switch self {
            case .pixelate, .blur: true
            default: false
            }
        }
    }

    public struct TextContent: Equatable, Codable, Sendable {
        public var string: String
        /// Top-left of the text box, in document coordinates.
        public var origin: CGPoint
        /// Point size in **document** units, so a 24pt label is 24pt whether the capture is 1x or
        /// 2x. The Tauri editor hardcoded 30px on the canvas while its input rendered at 12px.
        public var fontSize: CGFloat

        public init(string: String, origin: CGPoint, fontSize: CGFloat) {
            self.string = string
            self.origin = origin
            self.fontSize = fontSize
        }
    }

    public struct Style: Equatable, Codable, Sendable {
        public var color: InkColor
        /// Stroke width in document points. The Tauri editor fixed this at 3 with no UI, while its
        /// data model carried a lineWidth field and its arrowheads scaled off it.
        public var lineWidth: CGFloat
        public var opacity: CGFloat

        public init(color: InkColor, lineWidth: CGFloat = 3, opacity: CGFloat = 1) {
            self.color = color
            self.lineWidth = lineWidth
            self.opacity = opacity
        }
    }
}

/// Annotation colour.
///
/// Lives in Core, and is the one place outside the theme allowed to name literal colours: ink is
/// document data that has to serialize and reopen identically, not themeable chrome. A red arrow
/// must stay the same red in Light mode, Dark mode and in the exported PNG.
public struct InkColor: Equatable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// The palette offered in the editor — Apple's system accent colours, which is what the Tauri
/// editor used too.
public enum AnnotationPalette {
    public static let red = InkColor(hex: 0xFF453A)
    public static let orange = InkColor(hex: 0xFF9F0A)
    public static let yellow = InkColor(hex: 0xFFD60A)
    public static let green = InkColor(hex: 0x32D74B)
    public static let blue = InkColor(hex: 0x0A84FF)
    public static let purple = InkColor(hex: 0xBF5AF2)
    public static let white = InkColor(hex: 0xFFFFFF)
    public static let black = InkColor(hex: 0x000000)

    /// Eight, so the swatch grid divides evenly. The Tauri editor offered seven in a four-column
    /// grid, leaving a ragged last row.
    public static let all: [InkColor] = [
        red, orange, yellow, green, blue, purple, white, black,
    ]

    public static let `default` = red
}
