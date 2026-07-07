import Testing
@testable import CloudSessionManager

@Suite("Default profile drift reconciliation")
struct DefaultDriftTests {

    /// The scenario from the feature request: [default] was copied from a
    /// named profile, then that source profile is edited elsewhere. Reload
    /// should re-sync [default] to the profile's current values.
    @Test func driftInSourceProfileResyncsDefault() throws {
        let doc = ConfigDocument.parse("""
        [default]
        profile = dev
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = ReadOnly
        region = us-east-1

        [profile dev]
        sso_session = corp
        sso_account_id = 111111111111
        sso_role_name = Admin
        region = us-west-2
        """)

        #expect(doc.reconcileDefaultFromMarker(), "drifted default should be corrected")

        let def = try #require(doc.section(named: "default"))
        #expect(def.value(for: "profile") == "dev", "marker is preserved")
        #expect(def.value(for: "sso_role_name") == "Admin", "role re-synced from source")
        #expect(def.value(for: "region") == "us-west-2", "region re-synced from source")
    }

    /// A newly added key on the source profile should appear in [default],
    /// and a stale key that no longer exists on the source should be dropped.
    @Test func addedAndRemovedKeysAreReconciled() throws {
        let doc = ConfigDocument.parse("""
        [default]
        profile = dev
        sso_account_id = 111111111111
        output = json

        [profile dev]
        sso_account_id = 111111111111
        region = eu-central-1
        """)

        #expect(doc.reconcileDefaultFromMarker())

        let def = try #require(doc.section(named: "default"))
        #expect(def.value(for: "region") == "eu-central-1", "new key copied in")
        #expect(def.value(for: "output") == nil, "stale key dropped")
        #expect(def.value(for: "profile") == "dev")
    }

    /// When [default] already matches its source profile, reconcile is a
    /// no-op and reports no change (so no needless config rewrite happens).
    @Test func inSyncDefaultIsNoOp() {
        let doc = ConfigDocument.parse("""
        [default]
        profile = dev
        sso_account_id = 111111111111
        region = us-west-2

        [profile dev]
        sso_account_id = 111111111111
        region = us-west-2
        """)

        #expect(!doc.reconcileDefaultFromMarker(), "matching default needs no rewrite")
    }

    /// A hand-authored [default] with no `profile =` marker must be left
    /// entirely alone, even if it happens to resemble a named profile.
    @Test func unmarkedDefaultIsUntouched() throws {
        let doc = ConfigDocument.parse("""
        [default]
        sso_account_id = 111111111111
        region = us-east-1

        [profile dev]
        sso_account_id = 111111111111
        region = us-west-2
        """)

        #expect(!doc.reconcileDefaultFromMarker(), "unmarked default is not managed")
        let def = try #require(doc.section(named: "default"))
        #expect(def.value(for: "region") == "us-east-1", "hand-authored value preserved")
    }

    /// A marker pointing at a profile that no longer exists is not actionable
    /// and must not throw away the existing [default].
    @Test func markerForMissingProfileIsNoOp() {
        let doc = ConfigDocument.parse("""
        [default]
        profile = ghost
        sso_account_id = 111111111111

        [profile dev]
        sso_account_id = 222222222222
        """)

        #expect(!doc.reconcileDefaultFromMarker(), "missing source profile → no change")
    }

    /// Comments and unknown keys elsewhere in the file survive a reconcile +
    /// serialize round-trip (the app's stated safety guarantee).
    @Test func reconcilePreservesCommentsAndUnknownKeys() {
        let doc = ConfigDocument.parse("""
        # my aws config
        [default]
        profile = dev
        region = us-east-1

        [profile dev]
        # primary dev role
        sso_account_id = 111111111111
        region = us-west-2
        custom_tool_setting = keep-me
        """)

        #expect(doc.reconcileDefaultFromMarker())
        let out = doc.serialize()
        #expect(out.contains("# my aws config"), "preamble comment preserved")
        #expect(out.contains("# primary dev role"), "in-section comment preserved")
        #expect(out.contains("custom_tool_setting = keep-me"), "unknown key preserved")
    }
}
