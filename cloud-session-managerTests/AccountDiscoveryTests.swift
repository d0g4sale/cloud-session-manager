import Foundation
import Testing
@testable import cloud_session_manager

/// Covers the pure logic backing SSO account discovery: filtering discovered
/// accounts down to the ones that don't already have a profile, and the
/// account menu label. The network calls themselves aren't exercised here.
@MainActor
@Suite("SSO account discovery")
struct AccountDiscoveryTests {

    private func makeAWSDir(_ configContents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try configContents.write(
            to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        return dir
    }

    private func state(forAWSDir dir: URL) -> AppState {
        AppState(config: AWSConfig(awsDirectory: dir), cliPath: nil, autostart: false)
    }

    /// Accounts already backing a profile are hidden from the dropdown; the
    /// rest remain offered.
    @Test func filtersOutAccountsThatAlreadyHaveAProfile() throws {
        let dir = try makeAWSDir("""
        [profile dev]
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = Admin
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()
        app.discoveredAccounts["corp"] = [
            SSOAccount(accountID: "111111111111", accountName: "Dev", emailAddress: ""),
            SSOAccount(accountID: "222222222222", accountName: "Prod", emailAddress: ""),
        ]

        let available = app.accountsWithoutProfile(forSession: "corp")
        #expect(available.map(\.accountID) == ["222222222222"],
                "an account already used by a profile is excluded")
    }

    /// When editing a profile, its own account stays in the list so the
    /// dropdown can still show the current selection.
    @Test func editingProfileKeepsItsOwnAccount() throws {
        let dir = try makeAWSDir("""
        [profile dev]
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = Admin
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()
        app.discoveredAccounts["corp"] = [
            SSOAccount(accountID: "111111111111", accountName: "Dev", emailAddress: ""),
            SSOAccount(accountID: "222222222222", accountName: "Prod", emailAddress: ""),
        ]

        let available = app.accountsWithoutProfile(forSession: "corp", excluding: "111111111111")
        #expect(Set(available.map(\.accountID)) == ["111111111111", "222222222222"],
                "the edited profile's own account is not filtered out")
    }

    @Test func menuLabelFallsBackToIDWhenUnnamed() {
        #expect(SSOAccount(accountID: "123456789012", accountName: "Stridyn Dev",
                           emailAddress: "").menuLabel == "Stridyn Dev — 123456789012")
        #expect(SSOAccount(accountID: "123456789012", accountName: "",
                           emailAddress: "").menuLabel == "123456789012")
    }

    /// Discovery is refused (with a helpful error) when there's no valid,
    /// signed-in token for the session — it never reaches the network.
    @Test func discoveryWithoutTokenRecordsError() throws {
        let dir = try makeAWSDir("[profile dev]\nsso_session = corp\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()
        #expect(!app.canDiscoverAccounts(forSession: "corp"))

        app.discoverAccounts(forSession: "corp")
        #expect(app.accountsError["corp"] != nil, "records why the lookup can't run")
        #expect(!app.accountsLoading.contains("corp"), "no lookup left in flight")
    }
}
