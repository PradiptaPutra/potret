import CoreGraphics
import PotretCore

/// What a capture is aimed at.
///
/// Shared by the still-image path (`SCScreenshotManager`) and, from Phase 6, the recording path
/// (`SCStream`) — both build their `SCContentFilter` from the same target, so region selection,
/// window picking and self-window exclusion are written once.
public enum CaptureTarget: Equatable, Sendable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    /// Region in global screen coordinates, plus the display it belongs to.
    case region(CGRect, on: CGDirectDisplayID)
}
