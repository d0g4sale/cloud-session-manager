import Foundation
import Testing
@testable import cloud_session_manager

/// Covers the menu/header status line, especially the signed-in-but-nothing-
/// to-track cases that used to hang on "checking credential expiry…".
@MainActor
@Suite("Status description")
struct StatusDescriptionTests {

    private func makeState() throws -> AppState {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppState(config: AWSConfig(awsDirectory: dir), cliPath: nil, autostart: false)
    }

    @Test func signedInWithoutDefaultButWithProfilesPromptsToChoose() throws {
        let app = try makeState()
        app.tokenStatus = .valid(expires: Date(timeIntervalSinceNow: 3600))
        app.profiles = [ProfileInfo(name: "dev", ssoSession: "corp", accountID: "111111111111",
                                    roleName: "Admin", region: "us-east-1", output: "")]
        app.defaultProfileName = nil
        app.credentialExpiration = nil
        #expect(app.statusDescription == "SSO signed in — choose a default profile")
    }

    @Test func signedInWithoutAnyProfilePromptsToAddOne() throws {
        let app = try makeState()
        app.tokenStatus = .valid(expires: Date(timeIntervalSinceNow: 3600))
        app.profiles = []
        app.defaultProfileName = nil
        app.credentialExpiration = nil
        #expect(app.statusDescription == "SSO signed in — add a profile to use it")
    }

    @Test func signedInWithDefaultStillChecksWhileExpiryPending() throws {
        let app = try makeState()
        app.tokenStatus = .valid(expires: Date(timeIntervalSinceNow: 3600))
        app.defaultProfileName = "dev"
        app.credentialExpiration = nil
        #expect(app.statusDescription == "SSO signed in — checking credential expiry…")
    }

    @Test func showsCredentialCountdownWhenExpiryKnown() throws {
        let app = try makeState()
        app.tokenStatus = .valid(expires: Date(timeIntervalSinceNow: 3600))
        app.defaultProfileName = "dev"
        app.credentialProfileLabel = "dev"
        app.credentialExpiration = Date(timeIntervalSinceNow: 3600)
        #expect(app.statusDescription.hasPrefix("Credentials (dev) valid until "))
    }
}
