import Foundation
import Testing
@testable import PotretCore

// swift-testing, not XCTest — XCTest.framework ships only with Xcode, and this project builds
// with the Command Line Tools alone. See TESTING.md.
@Suite("App identity")
struct AppIdentityTests {
    @Test("Release bundle id matches the Tauri app so the TCC grant carries over")
    func releaseBundleIDIsUnchanged() {
        #expect(AppIdentity.releaseBundleID == "com.potret.app")
    }

    @Test("Development builds use a distinct id so they cannot disturb the shipped app")
    func developmentBundleIDIsSeparate() {
        #expect(AppIdentity.developmentBundleID != AppIdentity.releaseBundleID)
        #expect(AppIdentity.developmentBundleID.hasPrefix(AppIdentity.releaseBundleID))
    }

    @Test("History and config resolve inside the directory the Tauri app already uses")
    func storagePathsMatchTauriLayout() {
        let support = AppIdentity.applicationSupportDirectory()
        #expect(support.lastPathComponent == "com.potret.app")
        #expect(AppIdentity.historyDirectory().path().hasSuffix("com.potret.app/history/"))
        #expect(AppIdentity.configFile().lastPathComponent == "config.json")
    }
}
