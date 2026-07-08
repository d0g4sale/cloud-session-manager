import Foundation
import Testing
@testable import cloud_session_manager

/// Exercises the AppState glue around drift reconciliation — writing the
/// corrected [default] to disk and, crucially, not rewriting it again on the
/// next reload (which would otherwise loop with the file-change watcher).
@MainActor
@Suite("AppState default drift reconciliation")
struct AppStateDriftTests {

    /// Makes a throwaway `.aws` directory containing `config` with the given
    /// contents, and returns (awsDir, configURL). Cleaned up by the caller.
    private func makeAWSDir(_ configContents: String) throws -> (dir: URL, configURL: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config")
        try configContents.write(to: configURL, atomically: true, encoding: .utf8)
        return (dir, configURL)
    }

    private func state(forAWSDir dir: URL) -> AppState {
        // cliPath: nil keeps credential fetch / login from shelling out;
        // autostart: false skips the timer so we drive reloadConfig() directly.
        AppState(config: AWSConfig(awsDirectory: dir), cliPath: nil, autostart: false)
    }

    /// A [default] that drifted from its marked source profile is corrected on
    /// disk when the app reloads config, and the fix converges: a second reload
    /// makes no further write (no rewrite loop with the mtime watcher).
    @Test func driftIsPersistedAndConverges() throws {
        let (dir, configURL) = try makeAWSDir("""
        [default]
        profile = dev
        sso_account_id = 111111111111
        sso_role_name = ReadOnly
        region = us-east-1

        [profile dev]
        sso_account_id = 111111111111
        sso_role_name = Admin
        region = us-west-2
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()

        // The on-disk [default] now mirrors the source profile.
        let written = ConfigDocument.parse(try String(contentsOf: configURL, encoding: .utf8))
        let def = try #require(written.section(named: "default"))
        #expect(def.value(for: "sso_role_name") == "Admin")
        #expect(def.value(for: "region") == "us-west-2")
        #expect(def.value(for: "profile") == "dev", "marker preserved")
        #expect(app.defaultProfileName == "dev")

        // A correcting write happened — save() leaves a backup behind.
        let backupURL = dir.appendingPathComponent("config.awssso.bak")
        #expect(FileManager.default.fileExists(atPath: backupURL.path), "first reload rewrote config")

        // Convergence: delete the backup, reload again — nothing should be
        // rewritten now that [default] already matches its source.
        try FileManager.default.removeItem(at: backupURL)
        app.reloadConfig()
        #expect(!FileManager.default.fileExists(atPath: backupURL.path),
                "second reload must not rewrite an already-synced config")
    }

    /// An already-synced config is never rewritten on reload (no backup is
    /// produced), confirming reconcile is a true no-op in the common case.
    @Test func inSyncConfigIsNotRewritten() throws {
        let (dir, _) = try makeAWSDir("""
        [default]
        profile = dev
        sso_account_id = 111111111111
        region = us-west-2

        [profile dev]
        sso_account_id = 111111111111
        region = us-west-2
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()

        let backupURL = dir.appendingPathComponent("config.awssso.bak")
        #expect(!FileManager.default.fileExists(atPath: backupURL.path),
                "in-sync config must not be rewritten")
        #expect(app.defaultProfileName == "dev")
    }

    /// A lone profile with no [default] section is adopted as the default
    /// automatically — [default] is written to mirror it, marker included.
    @Test func soleProfileBecomesDefaultWhenNoDefaultExists() throws {
        let (dir, configURL) = try makeAWSDir("""
        [profile dev]
        sso_account_id = 111111111111
        sso_role_name = Admin
        region = us-west-2
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()

        #expect(app.defaultProfileName == "dev")
        let after = ConfigDocument.parse(try String(contentsOf: configURL, encoding: .utf8))
        let def = after.section(named: "default")
        #expect(def?.value(for: "profile") == "dev")
        #expect(def?.value(for: "region") == "us-west-2")
    }

    /// With more than one profile and no default, none is adopted — the choice
    /// is genuinely the user's.
    @Test func multipleProfilesAreNotAutoDefaulted() throws {
        let (dir, configURL) = try makeAWSDir("""
        [profile dev]
        sso_account_id = 111111111111
        sso_role_name = Admin

        [profile prod]
        sso_account_id = 222222222222
        sso_role_name = Admin
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()

        #expect(app.defaultProfileName == nil)
        let after = ConfigDocument.parse(try String(contentsOf: configURL, encoding: .utf8))
        #expect(after.section(named: "default") == nil)
    }

    /// A hand-authored [default] with no marker is left untouched on disk.
    @Test func unmarkedDefaultIsNotRewritten() throws {
        let (dir, configURL) = try makeAWSDir("""
        [default]
        sso_account_id = 111111111111
        region = us-east-1

        [profile dev]
        sso_account_id = 111111111111
        region = us-west-2
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let app = state(forAWSDir: dir)
        app.reloadConfig()

        let backupURL = dir.appendingPathComponent("config.awssso.bak")
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        let after = ConfigDocument.parse(try String(contentsOf: configURL, encoding: .utf8))
        #expect(after.section(named: "default")?.value(for: "region") == "us-east-1")
    }
}
