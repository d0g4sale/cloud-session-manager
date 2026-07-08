import Foundation
import Testing
@testable import cloud_session_manager

/// Covers the menu bar status badge: which state each SSO condition maps to.
@MainActor
@Suite("Menu bar status badge")
struct MenuBarBadgeTests {

    private func makeState() throws -> AppState {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("awssso-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppState(config: AWSConfig(awsDirectory: dir), cliPath: nil, autostart: false)
    }

    @Test func noSessionHasNoBadge() throws {
        let app = try makeState()
        app.tokenStatus = .noSession
        #expect(app.menuBarBadge == nil)
    }

    @Test func signedInShowsSignedInBadge() throws {
        let app = try makeState()
        app.tokenStatus = .valid(expires: Date(timeIntervalSinceNow: 3600))
        #expect(app.menuBarBadge == .signedIn)
    }

    @Test func loggedOutShowsSignedOutBadge() throws {
        let app = try makeState()
        app.tokenStatus = .notLoggedIn
        #expect(app.menuBarBadge == .signedOut)
    }

    @Test func expiredWithoutAutoRenewNeedsAttention() throws {
        let app = try makeState()
        app.tokenStatus = .expired(since: Date(timeIntervalSinceNow: -60))
        app.canAutoRenew = false
        #expect(app.menuBarBadge == .attention)
    }

    @Test func expiredButAutoRenewableShowsWorking() throws {
        let app = try makeState()
        app.tokenStatus = .expired(since: Date(timeIntervalSinceNow: -60))
        app.canAutoRenew = true
        #expect(app.menuBarBadge == .working)
    }

    @Test func signingInShowsWorking() throws {
        let app = try makeState()
        app.tokenStatus = .notLoggedIn
        app.isLoggingIn = true
        #expect(app.menuBarBadge == .working)
    }

    /// Every badge maps to a `.circle.fill` symbol so it renders as a disc.
    @Test func badgeSymbolsAreCircleFills() {
        for badge in [MenuBarBadge.signedIn, .signedOut, .attention, .working] {
            #expect(badge.symbol.hasSuffix(".circle.fill"))
        }
    }
}
