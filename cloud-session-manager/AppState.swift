import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [ProfileInfo] = []
    @Published var sessions: [SSOSessionInfo] = []
    @Published var defaultProfileName: String?
    /// State of the short-lived SSO access token in the CLI cache.
    @Published var tokenStatus: TokenStatus = .noSession
    /// Expiration of the default profile's resolved role credentials, as
    /// reported by `aws configure export-credentials`. Drives the countdown.
    @Published var credentialExpiration: Date?
    @Published var credentialProfileLabel: String = "default"
    @Published var credentialFetchError: String?
    @Published var canAutoRenew: Bool = false
    @Published var isRefreshingToken: Bool = false
    @Published var isLoggingIn: Bool = false
    @Published var lastError: String?

    /// The installed AWS CLI version (as `aws --version` reports it), or nil
    /// while detection is pending, it fails, or the CLI isn't installed.
    @Published var awsCLIVersion: String?

    /// The command we suggest for installing the CLI, and where the official
    /// AWS install instructions live.
    static let cliInstallCommand = "brew install awscli"
    static let cliInstallDocsURL = URL(
        string: "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html")!
    /// AWS's official macOS installer steps: download the pkg and install it.
    static let cliOfficialInstallCommand = """
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" && \
        sudo installer -pkg AWSCLIV2.pkg -target /
        """

    /// Whether the `aws` CLI is currently found on disk. The app can't sign in
    /// or resolve credentials without it. Re-checked each tick, so installing
    /// the CLI while the app runs clears the "not installed" state on its own.
    @Published private(set) var awsCLIInstalled: Bool = false

    /// True when the user has nothing usable set up yet — no CLI, or no
    /// profiles — so the app should open the Profile Manager at launch rather
    /// than leaving them staring at a menu bar icon with nothing behind it.
    var needsSetup: Bool { !awsCLIInstalled || profiles.isEmpty }

    /// Accounts discovered from the SSO Portal, keyed by sso-session name.
    @Published var discoveredAccounts: [String: [SSOAccount]] = [:]
    /// Roles discovered per account, keyed by `roleKey(session:accountID:)`.
    @Published var discoveredRoles: [String: [String]] = [:]
    /// sso-session names with an account lookup in flight.
    @Published var accountsLoading: Set<String> = []
    /// `roleKey` values with a role lookup in flight.
    @Published var rolesLoading: Set<String> = []
    /// Why the last account lookup for a session failed, if it did.
    @Published var accountsError: [String: String] = [:]

    /// Where the shared-config files live. Injectable so tests can use a
    /// temporary directory instead of the real `~/.aws`.
    let config: AWSConfig
    /// Path to the `aws` CLI, or nil when unavailable (also used by tests to
    /// keep credential fetching and login/logout from shelling out). A var so
    /// it can be refreshed at runtime as the CLI is installed or removed.
    private var cliPath: String?

    private var document: ConfigDocument = ConfigDocument()
    private var configModificationDate: Date?
    private var timer: Timer?

    /// Set when a token refresh is refused — the SSO session is truly over.
    private var sessionDead = false
    private var lastSeenTokenExpiry: Date?
    private var lastRefreshAttempt: Date?
    private var trackedSessionName = ""

    private var credentialFetchInFlight = false
    private var lastCredentialFetch: Date?
    private static let credentialPollInterval: TimeInterval = 60

    /// The sso-session whose token drives the menu bar status: the default
    /// profile's session if it has one, otherwise the first configured session.
    var activeSessionName: String {
        if let name = defaultProfileName,
           let profile = profiles.first(where: { $0.name == name }),
           !profile.ssoSession.isEmpty {
            return profile.ssoSession
        }
        return sessions.first?.name ?? ""
    }

    /// True when the only way forward is a fresh `aws sso login`.
    var loginNeeded: Bool {
        if sessionDead { return true }
        switch tokenStatus {
        case .valid: return false
        case .expired: return !canAutoRenew
        case .notLoggedIn: return true
        case .noSession: return false
        }
    }

    /// The status badge overlaid on the menu bar cloud, conveying the SSO state
    /// at a glance. `nil` when there's no session configured — there's no state
    /// to badge.
    var menuBarBadge: MenuBarBadge? {
        if isLoggingIn { return .working }               // signing in
        switch tokenStatus {
        case .noSession:
            return nil                                   // nothing configured
        case .notLoggedIn:
            return .signedOut                            // logged out
        case .expired:
            // An auto-renewable token recovers on its own; only flag when the
            // user actually has to sign in again.
            return canAutoRenew ? .working : .attention
        case .valid:
            // A refused refresh (session dead) leaves the cached token briefly
            // valid, but the session is over — surface it via loginNeeded.
            return loginNeeded ? .attention : .signedIn
        }
    }

    var statusDescription: String {
        let now = Date()
        if case .noSession = tokenStatus {
            return "No SSO session configured"
        }
        if let expiration = credentialExpiration, expiration > now {
            let when = Self.timeFormatter.string(from: expiration)
            var text = "Credentials (\(credentialProfileLabel)) valid until \(when)"
            if loginNeeded {
                text += " — sign in to renew"
            }
            return text
        }
        if loginNeeded {
            if case .notLoggedIn = tokenStatus { return "Not signed in to SSO" }
            return "SSO session ended — sign in again"
        }
        // Signed in, but there's no default profile whose credentials we can
        // track — export-credentials has nothing to resolve, so don't leave
        // the user on a "checking…" message that never resolves.
        if defaultProfileName == nil {
            return profiles.isEmpty
                ? "SSO signed in — add a profile to use it"
                : "SSO signed in — choose a default profile"
        }
        return "SSO signed in — checking credential expiry…"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    init(
        config: AWSConfig = .default,
        cliPath: String? = AppState.locateAWSCLI(),
        autostart: Bool = true
    ) {
        self.config = config
        self.cliPath = cliPath
        self.awsCLIInstalled = cliPath != nil
        guard autostart else { return }
        reloadConfig()
        refreshStatus()
        detectCLIVersion()
        fetchCredentials(force: true)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Scans the usual install locations for the `aws` CLI.
    nonisolated static func locateAWSCLI() -> String? {
        let candidates = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The environment for `aws` subprocesses, with profile-selecting variables
    /// stripped. The app always chooses the profile explicitly — via
    /// `--profile`, `--sso-session`, or the managed `[default]` section — so a
    /// stale `AWS_PROFILE` inherited from the launching shell (e.g. pointing at
    /// a since-renamed profile) must not leak in and break commands like
    /// `aws sso logout`, which otherwise fall back to it.
    nonisolated static func awsSubprocessEnvironment(
        _ base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env.removeValue(forKey: "AWS_PROFILE")
        env.removeValue(forKey: "AWS_DEFAULT_PROFILE")
        return env
    }

    private func tick() {
        refreshCLIAvailability()
        reloadConfigIfChanged()
        refreshStatus()
        fetchCredentials()
    }

    /// Re-locates the `aws` CLI so installing or removing it while the app is
    /// running is reflected without a relaunch. Cheap: a few executable-file
    /// checks. Re-reads the version only when its presence actually changes.
    private func refreshCLIAvailability() {
        let located = Self.locateAWSCLI()
        guard (located != nil) != awsCLIInstalled else { return }
        cliPath = located
        awsCLIInstalled = located != nil
        detectCLIVersion()
    }

    /// Records the installed AWS CLI version for display. Re-run whenever the
    /// CLI's presence changes (see `refreshCLIAvailability`).
    private func detectCLIVersion() {
        guard let cli = cliPath else {
            awsCLIVersion = nil
            return
        }
        Task {
            self.awsCLIVersion = await AWSCLIVersion.detect(cliPath: cli)
        }
    }

    // MARK: - Config

    func reloadConfig() {
        document = (try? config.load()) ?? ConfigDocument()
        configModificationDate = modificationDate(of: config.configURL)
        profiles = document.sections.compactMap(ProfileInfo.from(section:))
        sessions = document.sections.compactMap(SSOSessionInfo.from(section:))
        let previousDefault = defaultProfileName
        defaultProfileName = currentDefaultProfileName()
        let synced = reconcileDefaultDrift()
        if defaultProfileName != previousDefault || synced {
            credentialExpiration = nil
            fetchCredentials(force: true)
        }
        adoptSoleProfileAsDefault()
    }

    /// When there's exactly one profile and no [default] section at all, make
    /// that profile the default — there's no other sensible choice, and it
    /// spares the user a manual "Make Default" step right after creating their
    /// first profile. `setDefaultProfile` writes [default] and reloads, which
    /// re-enters here, but by then a [default] exists so this is a no-op.
    ///
    /// A hand-authored [default] (present but not matching a profile, so
    /// `defaultProfileName` is nil) is deliberately left alone — see
    /// `reconcileDefaultDrift` — so we key off the section's existence, not
    /// `defaultProfileName`.
    private func adoptSoleProfileAsDefault() {
        guard profiles.count == 1, document.section(named: "default") == nil else { return }
        setDefaultProfile(profiles[0])
    }

    /// If [default] was populated from a named profile (recorded by the
    /// `profile = <name>` marker) but that profile has since been edited
    /// elsewhere — e.g. by hand or another tool — re-copy the source
    /// profile's settings into [default] so plain `aws` commands keep
    /// resolving to the selected profile's current values.
    ///
    /// Only defaults carrying the marker are reconciled; a hand-authored
    /// [default] with no marker is left untouched. Returns whether a
    /// correcting write was made.
    @discardableResult
    private func reconcileDefaultDrift() -> Bool {
        guard document.reconcileDefaultFromMarker() else { return false }
        do {
            try config.save(document)
            configModificationDate = modificationDate(of: config.configURL)
            lastError = nil
        } catch {
            lastError = "Failed to sync [default] profile: \(error.localizedDescription)"
            return false
        }
        return true
    }

    private func reloadConfigIfChanged() {
        let current = modificationDate(of: config.configURL)
        if current != configModificationDate {
            reloadConfig()
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func currentDefaultProfileName() -> String? {
        guard let def = document.section(named: "default") else { return nil }
        if let marker = def.value(for: "profile"), profiles.contains(where: { $0.name == marker }) {
            return marker
        }
        // Fall back to matching account + role against a named profile.
        if let account = def.value(for: "sso_account_id"),
           let role = def.value(for: "sso_role_name") {
            return profiles.first { $0.accountID == account && $0.roleName == role }?.name
        }
        return nil
    }

    // MARK: - Status

    func refreshStatus() {
        let now = Date()
        let name = activeSessionName

        if name != trackedSessionName {
            trackedSessionName = name
            sessionDead = false
            lastSeenTokenExpiry = nil
            lastRefreshAttempt = nil
        }

        guard !name.isEmpty else {
            tokenStatus = .noSession
            canAutoRenew = false
            return
        }

        let token = SSOTokenCache.load(forSession: name)
        let newStatus = token?.status(now: now) ?? .notLoggedIn

        if case .valid(let expires) = newStatus {
            // A token newer than any we've seen after the session died means
            // the user signed in again (possibly outside the app).
            if sessionDead, let seen = lastSeenTokenExpiry, expires > seen {
                sessionDead = false
                fetchCredentials(force: true)
            }
            lastSeenTokenExpiry = expires
        }

        canAutoRenew = token?.refreshToken != nil && !sessionDead
        tokenStatus = newStatus
        maybeRefreshToken(token: token, status: newStatus, now: now)
    }

    // MARK: - Credential expiration (aws configure export-credentials)

    func fetchCredentials(force: Bool = false) {
        // With no signed-in SSO session there's no token to resolve credentials
        // from — calling the CLI just returns "Token … does not exist". Skip it
        // and clear any stale error so "not signed in" isn't shown as a failure.
        if loginNeeded {
            credentialFetchError = nil
            return
        }
        guard let cli = cliPath, !credentialFetchInFlight else { return }
        if case .noSession = tokenStatus, profiles.isEmpty { return }
        let now = Date()
        if !force, let last = lastCredentialFetch,
           now.timeIntervalSince(last) < Self.credentialPollInterval {
            return
        }
        credentialFetchInFlight = true
        lastCredentialFetch = now
        let profile = defaultProfileName
        Task {
            let outcome = await CredentialsFetcher.fetch(cliPath: cli, profile: profile)
            self.credentialFetchInFlight = false
            switch outcome {
            case .success(let expiration):
                self.credentialExpiration = expiration
                self.credentialProfileLabel = profile ?? "default"
                self.credentialFetchError = nil
            case .failure(let message):
                // Keep showing the previous expiration if those credentials
                // are still valid; just record why renewal isn't working.
                self.credentialFetchError = message
            }
        }
    }

    /// Renews the SSO access token with the refresh token shortly before (or
    /// after) it expires — the same thing the AWS CLI does on demand.
    private func maybeRefreshToken(token: SSOToken?, status: TokenStatus, now: Date) {
        guard let token, token.refreshToken != nil, !sessionDead, !isRefreshingToken else { return }
        let due: Bool
        switch status {
        case .valid(let expires): due = expires.timeIntervalSince(now) < 300
        case .expired: due = true
        default: due = false
        }
        guard due else { return }
        if let last = lastRefreshAttempt, now.timeIntervalSince(last) < 60 { return }
        lastRefreshAttempt = now
        isRefreshingToken = true
        Task {
            let result = await TokenRefresher.refresh(token)
            self.isRefreshingToken = false
            switch result {
            case .refreshed:
                self.lastError = nil
            case .sessionEnded:
                self.sessionDead = true
            case .transientFailure(let message):
                self.lastError = "Token renewal failed: \(message)"
            }
            self.refreshStatus()
        }
    }

    // MARK: - Actions

    /// Makes `profile` the default by copying its settings into [default],
    /// with a `profile = <name>` marker recording the selection.
    func setDefaultProfile(_ profile: ProfileInfo) {
        guard let source = document.section(named: "profile \(profile.name)") else { return }
        let def = document.ensureSection(named: "default")
        def.lines = ConfigDocument.defaultLines(markerName: profile.name, from: source)
        saveConfig()
    }

    func saveProfile(originalName: String?, _ profile: ProfileInfo) {
        let sectionName = "profile \(profile.name)"
        if let originalName, originalName != profile.name {
            document.removeSection(named: "profile \(originalName)")
        }
        let section = document.ensureSection(named: sectionName)
        let fields: [(String, String)] = [
            ("sso_session", profile.ssoSession),
            ("sso_account_id", profile.accountID),
            ("sso_role_name", profile.roleName),
            ("region", profile.region),
            ("output", profile.output),
        ]
        for (key, value) in fields {
            if value.isEmpty {
                section.remove(key)
            } else {
                section.set(key, to: value)
            }
        }
        if defaultProfileName == originalName ?? profile.name {
            // Keep [default] in sync with the edited profile.
            saveConfig()
            reloadConfig()
            if let updated = profiles.first(where: { $0.name == profile.name }) {
                setDefaultProfile(updated)
            }
            return
        }
        saveConfig()
    }

    func deleteProfile(named name: String) {
        document.removeSection(named: "profile \(name)")
        if defaultProfileName == name {
            document.section(named: "default")?.remove("profile")
        }
        saveConfig()
    }

    func saveSession(originalName: String?, _ session: SSOSessionInfo) {
        if let originalName, originalName != session.name {
            document.removeSection(named: "sso-session \(originalName)")
        }
        let section = document.ensureSection(named: "sso-session \(session.name)")
        section.set("sso_start_url", to: session.startURL)
        section.set("sso_region", to: session.region)
        if session.scopes.isEmpty {
            section.remove("sso_registration_scopes")
        } else {
            section.set("sso_registration_scopes", to: session.scopes)
        }
        saveConfig()
    }

    func deleteSession(named name: String) {
        document.removeSection(named: "sso-session \(name)")
        saveConfig()
    }

    private func saveConfig() {
        do {
            try config.save(document)
            lastError = nil
        } catch {
            lastError = "Failed to save ~/.aws/config: \(error.localizedDescription)"
        }
        reloadConfig()
        refreshStatus()
    }

    // MARK: - SSO login/logout

    func login() {
        let session = activeSessionName
        guard !session.isEmpty else {
            lastError = "No sso-session configured. Add one under Manage Profiles."
            return
        }
        runAWS(arguments: ["sso", "login", "--sso-session", session]) { [weak self] in
            self?.sessionDead = false
            self?.discoveredAccounts.removeValue(forKey: session)
            self?.discoveredRoles = [:]
            self?.accountsError.removeValue(forKey: session)
            self?.fetchCredentials(force: true)
        }
    }

    func logout() {
        runAWS(arguments: ["sso", "logout"]) { [weak self] in
            self?.credentialExpiration = nil
        }
    }

    private func runAWS(arguments: [String], onSuccess: (() -> Void)? = nil) {
        guard let cli = cliPath else {
            lastError = "AWS CLI not found. Install it with: brew install awscli"
            return
        }
        isLoggingIn = arguments.first == "sso" && arguments.dropFirst().first == "login"
        lastError = nil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = arguments
        process.environment = Self.awsSubprocessEnvironment()
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] proc in
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoggingIn = false
                if proc.terminationStatus == 0 {
                    onSuccess?()
                } else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                    self.lastError = "aws \(arguments.joined(separator: " ")) failed: \(message)"
                }
                self.refreshStatus()
            }
        }
        do {
            try process.run()
        } catch {
            isLoggingIn = false
            lastError = "Could not run aws: \(error.localizedDescription)"
        }
    }

    func copyExportCommand() {
        guard let name = defaultProfileName else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("export AWS_PROFILE=\(name)", forType: .string)
    }

    /// Copies the suggested Homebrew install command for the AWS CLI.
    func copyInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.cliInstallCommand, forType: .string)
    }

    /// Copies AWS's official pkg-based install command for the AWS CLI.
    func copyOfficialInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.cliOfficialInstallCommand, forType: .string)
    }

    /// Opens the official AWS CLI install instructions in the browser.
    func openInstallInstructions() {
        NSWorkspace.shared.open(Self.cliInstallDocsURL)
    }

    /// Builds the AWS access-portal deep link that opens the web console signed
    /// in as this profile's account + role, e.g.
    /// `https://acme.awsapps.com/start/#/console?account_id=…&role_name=…`.
    /// Returns nil when the profile lacks an account/role, or its SSO session
    /// has no start URL to anchor the portal.
    func consoleURL(for profile: ProfileInfo) -> URL? {
        guard !profile.accountID.isEmpty, !profile.roleName.isEmpty,
              let session = sessions.first(where: { $0.name == profile.ssoSession }) else { return nil }
        var base = session.startURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        // Normalize to the portal's `/start` root, dropping any existing
        // fragment or trailing slash the user may have entered.
        if let range = base.range(of: "/start") {
            base = String(base[..<range.upperBound])
        } else {
            if base.hasSuffix("/") { base.removeLast() }
            base += "/start"
        }
        // The query lives inside the SPA's hash fragment, so encode the role
        // ourselves rather than relying on URLComponents' query handling.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let role = profile.roleName
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? profile.roleName
        return URL(string: "\(base)/#/console?account_id=\(profile.accountID)&role_name=\(role)")
    }

    // MARK: - SSO account & role discovery

    func roleKey(session: String, accountID: String) -> String { "\(session)\t\(accountID)" }

    /// A valid, signed-in token is required to query the SSO Portal.
    func canDiscoverAccounts(forSession session: String) -> Bool {
        guard !session.isEmpty, let token = SSOTokenCache.load(forSession: session),
              token.accessToken != nil else { return false }
        if case .valid = token.status() { return true }
        return false
    }

    /// The accounts for a session that don't yet have a profile. `excluding`
    /// is the account of the profile currently being edited, so editing an
    /// existing profile still shows its own account.
    func accountsWithoutProfile(forSession session: String, excluding accountID: String? = nil)
        -> [SSOAccount]
    {
        let taken = Set(profiles.compactMap { $0.accountID.isEmpty ? nil : $0.accountID })
            .subtracting(accountID.map { [$0] } ?? [])
        return (discoveredAccounts[session] ?? []).filter { !taken.contains($0.accountID) }
    }

    /// Fetches the accounts the signed-in user can reach for `session`.
    /// No-op if a lookup is already in flight or (unless `force`) already loaded.
    func discoverAccounts(forSession session: String, force: Bool = false) {
        guard !session.isEmpty, !accountsLoading.contains(session) else { return }
        if !force, discoveredAccounts[session] != nil { return }
        guard let token = SSOTokenCache.load(forSession: session),
              let accessToken = token.accessToken, case .valid = token.status() else {
            accountsError[session] = "Sign in to “\(session)” to list accounts."
            return
        }
        let region = token.region ?? sessions.first { $0.name == session }?.region ?? "us-east-1"
        accountsLoading.insert(session)
        accountsError[session] = nil
        Task {
            let result = await SSOPortalClient.listAccounts(accessToken: accessToken, region: region)
            self.accountsLoading.remove(session)
            switch result {
            case .success(let accounts):
                self.discoveredAccounts[session] = accounts
            case .unauthorized:
                self.accountsError[session] = "Sign in to “\(session)” to list accounts."
            case .failure(let message):
                self.accountsError[session] = message
            }
        }
    }

    /// Fetches the roles available for one account within a session.
    func discoverRoles(forSession session: String, accountID: String, force: Bool = false) {
        guard !session.isEmpty, !accountID.isEmpty else { return }
        let key = roleKey(session: session, accountID: accountID)
        guard !rolesLoading.contains(key) else { return }
        if !force, discoveredRoles[key] != nil { return }
        guard let token = SSOTokenCache.load(forSession: session),
              let accessToken = token.accessToken, case .valid = token.status() else { return }
        let region = token.region ?? sessions.first { $0.name == session }?.region ?? "us-east-1"
        rolesLoading.insert(key)
        Task {
            let result = await SSOPortalClient.listAccountRoles(
                accessToken: accessToken, accountID: accountID, region: region)
            self.rolesLoading.remove(key)
            if case .success(let roles) = result {
                self.discoveredRoles[key] = roles
            }
        }
    }
}
