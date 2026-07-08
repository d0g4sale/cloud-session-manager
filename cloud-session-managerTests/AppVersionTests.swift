import Foundation
import Testing
@testable import cloud_session_manager

/// Covers how the menu's version string is derived from the bundle's Info.plist
/// values across release builds, the default plist, and un-stamped dev builds.
@Suite("App version display")
struct AppVersionTests {

    @Test func showsMarketingVersionAlone() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "1"]
        #expect(AppVersion.display(from: info) == "1.2.3")
    }

    @Test func appendsDistinctBuildNumber() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "42"]
        #expect(AppVersion.display(from: info) == "1.2.3 (42)")
    }

    @Test func fallsBackToDevWhenUnstamped() {
        #expect(AppVersion.display(from: nil) == "dev")
        #expect(AppVersion.display(from: [:]) == "dev")
        #expect(AppVersion.display(from: ["CFBundleShortVersionString": ""]) == "dev")
    }

    @Test func omitsBuildNumberWhenItMatchesMarketing() {
        let info: [String: Any] = ["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "2.0.0"]
        #expect(AppVersion.display(from: info) == "2.0.0")
    }
}
