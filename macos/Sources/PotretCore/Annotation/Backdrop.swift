import CoreGraphics
import Foundation

/// A backdrop to drop a capture onto, for sharing.
public struct Backdrop: Equatable, Sendable, Codable {
    /// Padding as a **fraction of the capture's shorter edge**, not an absolute point value.
    ///
    /// The Tauri tool used absolute pixels: 60px around a 3400px Retina screenshot is a hairline,
    /// while 60px around a 400px crop swallows it. A fraction looks the same at every size.
    public var paddingFraction: CGFloat
    /// Corner radius, also relative to the shorter edge, for the same reason.
    public var cornerFraction: CGFloat
    public var shadow: ShadowStyle?
    public var fill: Fill

    public init(
        paddingFraction: CGFloat = 0.06,
        cornerFraction: CGFloat = 0.012,
        shadow: ShadowStyle? = .default,
        fill: Fill = .gradient(.sunset)
    ) {
        self.paddingFraction = paddingFraction
        self.cornerFraction = cornerFraction
        self.shadow = shadow
        self.fill = fill
    }

    public enum Fill: Equatable, Sendable, Codable {
        case gradient(GradientPreset)
        case solid(InkColor)
        /// A user-supplied image, drawn aspect-fill and centred — never stretched, which is what
        /// the Tauri version did to every custom background regardless of its aspect ratio.
        case image(URL)
        case none
    }

    public struct ShadowStyle: Equatable, Sendable, Codable {
        public var radiusFraction: CGFloat
        public var opacity: CGFloat
        public var yOffsetFraction: CGFloat

        public init(radiusFraction: CGFloat, opacity: CGFloat, yOffsetFraction: CGFloat) {
            self.radiusFraction = radiusFraction
            self.opacity = opacity
            self.yOffsetFraction = yOffsetFraction
        }

        public static let `default` = ShadowStyle(
            radiusFraction: 0.03, opacity: 0.35, yOffsetFraction: 0.006
        )
    }

    // MARK: Geometry

    /// Absolute padding for a capture of this size.
    public func padding(for imageSize: CGSize) -> CGFloat {
        (min(imageSize.width, imageSize.height) * paddingFraction).rounded()
    }

    public func cornerRadius(for imageSize: CGSize) -> CGFloat {
        (min(imageSize.width, imageSize.height) * cornerFraction).rounded()
    }

    /// Total output size once the capture is padded.
    public func outputSize(for imageSize: CGSize) -> CGSize {
        let inset = padding(for: imageSize)
        return CGSize(width: imageSize.width + inset * 2, height: imageSize.height + inset * 2)
    }

    /// Where the capture sits inside the output.
    public func imageRect(for imageSize: CGSize) -> CGRect {
        let inset = padding(for: imageSize)
        return CGRect(origin: CGPoint(x: inset, y: inset), size: imageSize)
    }

    /// Aspect-fill rect for a background image of `sourceSize` covering `target`, centred.
    ///
    /// Overflow is split evenly so the middle of the backdrop stays in the middle. Stretching
    /// instead — what the old tool did — visibly distorts any photo whose aspect ratio differs.
    public static func aspectFill(source: CGSize, in target: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: target) }
        let scale = max(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: (target.width - size.width) / 2,
            y: (target.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// The gradient presets, carried over from the Tauri tool so existing outputs stay recognisable.
public enum GradientPreset: String, CaseIterable, Sendable, Codable {
    case sunset
    case ocean
    case mint
    case roseGold
    case lavender
    case peach
    case twilight
    case deepSpace
    case golden
    case midnight

    public var name: String {
        switch self {
        case .sunset: "Pink Sunset"
        case .ocean: "Ocean"
        case .mint: "Mint"
        case .roseGold: "Rose Gold"
        case .lavender: "Lavender"
        case .peach: "Peach"
        case .twilight: "Twilight"
        case .deepSpace: "Deep Space"
        case .golden: "Golden"
        case .midnight: "Midnight"
        }
    }

    public var stops: [InkColor] {
        switch self {
        case .sunset: [InkColor(hex: 0xF093FB), InkColor(hex: 0xF5576C)]
        case .ocean: [InkColor(hex: 0x4FACFE), InkColor(hex: 0x00F2FE)]
        case .mint: [InkColor(hex: 0x43E97B), InkColor(hex: 0x38F9D7)]
        case .roseGold: [InkColor(hex: 0xFA709A), InkColor(hex: 0xFEE140)]
        case .lavender: [InkColor(hex: 0xA18CD1), InkColor(hex: 0xFBC2EB)]
        case .peach: [InkColor(hex: 0xFCCB90), InkColor(hex: 0xD57EEB)]
        case .twilight: [InkColor(hex: 0x667EEA), InkColor(hex: 0x764BA2)]
        case .deepSpace: [InkColor(hex: 0x1A1A2E), InkColor(hex: 0x16213E), InkColor(hex: 0x0F3460)]
        case .golden: [InkColor(hex: 0xF7971E), InkColor(hex: 0xFFD200)]
        case .midnight: [InkColor(hex: 0x0F2027), InkColor(hex: 0x203A43), InkColor(hex: 0x2C5364)]
        }
    }

    /// Start and end as unit coordinates. Corner-to-corner for most; Deep Space runs top to
    /// bottom, as it did before.
    public var direction: (start: CGPoint, end: CGPoint) {
        switch self {
        case .deepSpace: (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1))
        default: (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        }
    }
}
