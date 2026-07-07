import Foundation
import Testing
@testable import CloudSessionManager

/// Covers `needsSetup` — the condition that opens the Profile Manager at
/// launch: no AWS CLI, or no profiles configured.
@MainActor
@Suite("Setup prompt condition")
struct SetupPromptTests {

    private func makeAWSDir(_ configContents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try configContents.write(
            to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        return dir
    }

    private func state(dir: URL, cliPath: String?) -> AppState {
        let app = AppState(config: AWSConfig(awsDirectory: dir), cliPath: cliPath, autostart: false)
        app.reloadConfig()
        return app
    }

    @Test func promptsWhenCLIMissingAndNoProfiles() throws {
        let dir = try makeAWSDir("")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(state(dir: dir, cliPath: nil).needsSetup)
    }

    @Test func promptsWhenCLIPresentButNoProfiles() throws {
        let dir = try makeAWSDir("")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(state(dir: dir, cliPath: "/opt/homebrew/bin/aws").needsSetup)
    }

    @Test func promptsWhenProfilesExistButCLIMissing() throws {
        let dir = try makeAWSDir("""
        [profile dev]
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = Admin
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(state(dir: dir, cliPath: nil).needsSetup)
    }

    @Test func doesNotPromptWhenCLIPresentAndProfilesExist() throws {
        let dir = try makeAWSDir("""
        [profile dev]
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = Admin
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!state(dir: dir, cliPath: "/opt/homebrew/bin/aws").needsSetup)
    }
}
