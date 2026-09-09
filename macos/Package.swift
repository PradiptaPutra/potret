// swift-tools-version: 6.0
import PackageDescription

// Potret — native macOS screenshot & annotation app.
//
// The dependency chain is deliberately linear so it cannot cycle:
//   Potret -> PotretUI -> {PotretCapture, PotretRender} -> PotretCore
//
// PotretCore imports Foundation and CoreGraphics ONLY — no AppKit, no SwiftUI. That boundary is
// what lets the bulk of the logic be tested headless, with no display, no run loop and no TCC
// grant, and it mechanically stops view concerns leaking into the model.
//
// Tests use swift-testing (`import Testing`), NOT XCTest: XCTest.framework is not shipped in the
// Command Line Tools SDK, and this project is built without Xcode. See TESTING.md.
let package = Package(
    name: "Potret",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PotretCore"),
        .target(name: "PotretCapture", dependencies: ["PotretCore"]),
        .target(name: "PotretRender", dependencies: ["PotretCore"]),
        // Screen recording: SCStream feeding AVAssetWriter, plus trimming and GIF export.
        // Separate from PotretCapture because it pulls in AVFoundation and has a session
        // lifecycle, where capture is a single async call.
        .target(name: "PotretRecord", dependencies: ["PotretCore", "PotretCapture"]),
        .target(
            name: "PotretUI",
            dependencies: ["PotretCore", "PotretCapture", "PotretRender", "PotretRecord"]
        ),
        .executableTarget(name: "Potret", dependencies: ["PotretUI"]),
        // Renders views offscreen to PNG. Stands in for the SwiftUI previews we don't get
        // without Xcode, and later generates the golden images for the render tests.
        .executableTarget(name: "PotretMockup", dependencies: ["PotretUI"]),
        .testTarget(
            name: "PotretCoreTests",
            dependencies: ["PotretCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PotretRenderTests", dependencies: ["PotretRender"]),
        .testTarget(name: "PotretRecordTests", dependencies: ["PotretRecord"]),
    ]
)
