import CoreGraphics
import Foundation
import Testing
@testable import PotretRecord

@Suite("Recording settings")
struct RecordingSettingsTests {
    @Test("Bitrate scales with the recorded area")
    func bitrateScalesWithArea() {
        // A fixed bitrate that looks fine on a small window turns a 4K display to mush, and one
        // tuned for 4K wastes an order of magnitude on a small region.
        let settings = RecordingSettings(quality: .standard)
        let small = settings.bitrate(for: CGSize(width: 640, height: 480))
        let large = settings.bitrate(for: CGSize(width: 3840, height: 2160))
        #expect(large > small * 20)
    }

    @Test("A full screen gets a bitrate screen text survives")
    func bitrateIsEnoughForText() {
        // Screen content is thin strokes and small type on flat fields, and it falls apart at
        // rates that look fine for camera footage. The original 4 Mbit/megapixel put a
        // 1920x1200 recording near 9 Mbps, where glyph edges visibly smeared.
        let screen = CGSize(width: 1920, height: 1200)
        let standard = RecordingSettings(quality: .standard).bitrate(for: screen)
        let high = RecordingSettings(quality: .high).bitrate(for: screen)

        #expect(standard >= 15_000_000)
        #expect(high >= 30_000_000)
        #expect(high > standard)
    }

    @Test("A tiny region still gets a usable bitrate")
    func bitrateHasAFloor() {
        // Without a floor, a 100x100 region computes a bitrate low enough to be unwatchable.
        let settings = RecordingSettings()
        #expect(settings.bitrate(for: CGSize(width: 100, height: 100)) >= 400_000)
    }

    @Test("High quality is meaningfully higher than standard")
    func qualityLevelsDiffer() {
        let size = CGSize(width: 1920, height: 1080)
        #expect(
            RecordingSettings(quality: .high).bitrate(for: size)
                > RecordingSettings(quality: .standard).bitrate(for: size)
        )
    }

    @Test("Durations format like a stopwatch")
    func durationFormatting() {
        #expect(DurationFormat.clock(0) == "0:00")
        #expect(DurationFormat.clock(7) == "0:07")
        #expect(DurationFormat.clock(62) == "1:02")
        #expect(DurationFormat.clock(3723) == "1:02:03")
        // Negative can arrive from a clock adjustment mid-recording; it must not render "-1:-3".
        #expect(DurationFormat.clock(-5) == "0:00")
    }
}
