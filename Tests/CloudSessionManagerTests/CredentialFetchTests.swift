import Foundation
import Testing
@testable import CloudSessionManager

/// Covers the guard that keeps credential fetching from running — and
/// surfacing "Token … does not exist" — when there's no signed-in session.
@MainActor
@Suite("Credential fetch gating")
struct CredentialFetchTests {

    private func makeState() throws -> AppState {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppState(config: AWSConfig(awsDirectory: dir), cliPath: nil, autostart: false)
    }

    @Test func clearsStaleErrorAndSkipsWhenNotSignedIn() throws {
        let app = try makeState()
        app.tokenStatus = .notLoggedIn          // loginNeeded == true
        app.credentialFetchError = "aws: [ERROR]: Error loading SSO Token: …"

        app.fetchCredentials(force: true)

        #expect(app.credentialFetchError == nil)
    }

    @Test func clearsErrorWhenSessionExpiredAndNotRenewable() throws {
        let app = try makeState()
        app.tokenStatus = .expired(since: Date(timeIntervalSinceNow: -60))
        app.canAutoRenew = false                // loginNeeded == true
        app.credentialFetchError = "stale"

        app.fetchCredentials(force: true)

        #expect(app.credentialFetchError == nil)
    }
}
