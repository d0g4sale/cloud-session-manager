import SwiftUI

struct ProfileManagerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(state: state)
            Divider()
            if !state.awsCLIInstalled {
                CLIMissingBanner(state: state)
                Divider()
            }
            TabView {
                ProfilesTab(state: state)
                    .tabItem { Label("Profiles", systemImage: "person.crop.rectangle.stack") }
                SessionsTab(state: state)
                    .tabItem { Label("SSO Sessions", systemImage: "key.horizontal") }
                ShellSetupTab()
                    .tabItem { Label("Shell Setup", systemImage: "terminal") }
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

// MARK: - Status header

private struct StatusHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .help(state.statusDescription)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.defaultProfileName.map { "Default profile: \($0)" }
                     ?? "No default profile selected")
                    .font(.headline)
                Text(state.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if state.defaultProfileName != nil {
                Button {
                    state.copyExportCommand()
                } label: {
                    Label("Copy export", systemImage: "doc.on.doc")
                }
                .help("Copy “export AWS_PROFILE=\(state.defaultProfileName ?? "")” to the clipboard")
            }

            if state.loginNeeded {
                Button("Log In") { state.login() }
                    .disabled(state.isLoggingIn)
                    .buttonStyle(.borderedProminent)
            } else if !state.profiles.isEmpty {
                Button("Renew") { state.login() }
                    .disabled(state.isLoggingIn)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        if case .noSession = state.tokenStatus { return .secondary }
        if state.loginNeeded { return .orange }
        return .green
    }
}

// MARK: - AWS CLI missing banner

/// A prominent warning shown across the whole window when the `aws` CLI isn't
/// installed. Without it the app can't sign in or resolve credentials, so the
/// banner offers both install paths (Homebrew and AWS's official pkg) plus a
/// link to the full instructions.
private struct CLIMissingBanner: View {
    @ObservedObject var state: AppState
    @State private var copiedBrew = false
    @State private var copiedOfficial = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 8) {
                Text("AWS CLI not installed")
                    .font(.headline)
                Text("This app drives the `aws` command to sign in and read credentials. Install it, then Cloud Session Manager will pick it up automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        state.copyInstallCommand()
                        copiedBrew = true
                        copiedOfficial = false
                    } label: {
                        Label(copiedBrew ? "Copied Homebrew command" : "Copy “\(AppState.cliInstallCommand)”",
                              systemImage: copiedBrew ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        state.copyOfficialInstallCommand()
                        copiedOfficial = true
                        copiedBrew = false
                    } label: {
                        Label(copiedOfficial ? "Copied installer command" : "Copy official installer command",
                              systemImage: copiedOfficial ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        state.openInstallInstructions()
                    } label: {
                        Label("Install instructions", systemImage: "arrow.up.forward.square")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Profiles

private struct ProfilesTab: View {
    @ObservedObject var state: AppState
    @State private var selection: String?
    @State private var draft = ProfileInfo(name: "", ssoSession: "", accountID: "", roleName: "", region: "", output: "")
    @State private var editingOriginalName: String?
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if state.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Profiles", systemImage: "person.crop.rectangle.stack")
                    } description: {
                        Text("Add a profile to switch your AWS default without touching the shell.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(state.profiles) { profile in
                            ProfileRow(profile: profile,
                                       isDefault: state.defaultProfileName == profile.name)
                                .tag(profile.name)
                        }
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button {
                        selection = nil
                        beginNewProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a profile")
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Delete the selected profile")
                    .disabled(selection == nil)
                    Spacer()
                    Text("\(state.profiles.count) profile\(state.profiles.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, maxWidth: 280)

            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: selection) { _, newValue in
            if let name = newValue, let profile = state.profiles.first(where: { $0.name == name }) {
                draft = profile
                editingOriginalName = name
                refreshDiscovery()
            }
        }
        .onChange(of: draft.ssoSession) { _, _ in
            refreshDiscovery()
        }
        .onChange(of: draft.accountID) { _, newValue in
            if !draft.ssoSession.isEmpty, !newValue.isEmpty {
                state.discoverRoles(forSession: draft.ssoSession, accountID: newValue)
            }
        }
        .onAppear {
            if let first = state.profiles.first {
                selection = first.name
            } else {
                beginNewProfile()
            }
            refreshDiscovery()
        }
        .confirmationDialog(
            "Delete profile “\(selection ?? "")”?",
            isPresented: $confirmDelete
        ) {
            Button("Delete", role: .destructive) {
                if let name = selection {
                    state.deleteProfile(named: name)
                    selection = state.profiles.first?.name
                }
            }
        } message: {
            Text("This removes the profile from ~/.aws/config. A backup is kept at ~/.aws/config.awssso.bak.")
        }
    }

    private var isDefault: Bool {
        editingOriginalName != nil && state.defaultProfileName == editingOriginalName
    }

    private var accountIDValid: Bool {
        let id = draft.accountID.trimmingCharacters(in: .whitespaces)
        return id.isEmpty || (id.count == 12 && id.allSatisfy(\.isNumber))
    }

    /// True when the draft differs from what's saved. A brand-new profile
    /// (no original to compare against) always counts as having changes.
    private var hasChanges: Bool {
        guard let name = editingOriginalName,
              let original = state.profiles.first(where: { $0.name == name }) else {
            return true
        }
        return draft != original
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && accountIDValid && hasChanges
    }

    private func beginNewProfile() {
        draft = ProfileInfo(
            name: "",
            ssoSession: state.sessions.first?.name ?? "",
            accountID: "",
            roleName: "",
            region: state.sessions.first?.region ?? "us-east-1",
            output: ""
        )
        editingOriginalName = nil
    }

    /// Kicks off SSO account/role lookups for the draft's current session and
    /// account. Both are no-ops when already loaded or when not signed in.
    private func refreshDiscovery() {
        guard !draft.ssoSession.isEmpty else { return }
        state.discoverAccounts(forSession: draft.ssoSession)
        if !draft.accountID.isEmpty {
            state.discoverRoles(forSession: draft.ssoSession, accountID: draft.accountID)
        }
    }

    /// When the profile name is still blank, derive one from the account name
    /// (e.g. "Stridyn Dev" → "stridyn-dev"). Leaves a user-entered name alone.
    private func suggestName(from account: SSOAccount) {
        guard draft.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !account.accountName.isEmpty else { return }
        let slug = account.accountName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partial, ch in
                if ch == "-", partial.last == "-" { return }
                partial.append(ch)
            }
        draft.name = String(slug.drop(while: { $0 == "-" })).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private var editor: some View {
        Form {
            Section {
                TextField("Profile name", text: $draft.name, prompt: Text("e.g. stridyn-dev"))
            } header: {
                HStack {
                    Text(editingOriginalName == nil ? "New Profile" : "Edit Profile")
                    if isDefault {
                        Spacer()
                        Label("Default", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
            }

            Section("Identity Center") {
                Picker("SSO session", selection: $draft.ssoSession) {
                    Text("None").tag("")
                    ForEach(state.sessions) { session in
                        Text(session.name).tag(session.name)
                    }
                }
                AccountField(
                    state: state,
                    session: draft.ssoSession,
                    originalAccountID: state.profiles.first { $0.name == editingOriginalName }?.accountID,
                    accountID: $draft.accountID,
                    onPick: { account in
                        suggestName(from: account)
                        draft.roleName = ""
                        state.discoverRoles(forSession: draft.ssoSession, accountID: account.accountID)
                    })
                if !accountIDValid {
                    Text("Account ID must be exactly 12 digits.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                RoleField(
                    state: state,
                    session: draft.ssoSession,
                    accountID: draft.accountID,
                    roleName: $draft.roleName)
            }

            Section("CLI Defaults") {
                RegionPicker(title: "Region",
                             selection: $draft.region,
                             emptyOption: "Inherit from SSO session")
                OutputFormatPicker(selection: $draft.output)
            }

            Section {
                HStack {
                    Button(editingOriginalName == nil ? "Add Profile" : "Save Changes") {
                        state.saveProfile(originalName: editingOriginalName, draft)
                        selection = draft.name
                        editingOriginalName = draft.name
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)

                    if let name = editingOriginalName, state.defaultProfileName != name {
                        Button("Make Default") {
                            if let profile = state.profiles.first(where: { $0.name == name }) {
                                state.setDefaultProfile(profile)
                            }
                        }
                        .help("Copy this profile into [default] so plain `aws` commands use it")
                    }
                    Spacer()
                }
                if let error = state.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileRow: View {
    let profile: ProfileInfo
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isDefault {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .help("Default profile")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        [profile.accountID, profile.region]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Account / role discovery fields

/// The account control: a dropdown of accounts the signed-in user can reach
/// (from the SSO Portal, minus accounts that already have a profile) when SSO
/// data is available, with an escape hatch to type a 12-digit ID by hand.
private struct AccountField: View {
    @ObservedObject var state: AppState
    let session: String
    /// Account of the profile being edited, so it isn't filtered out of its
    /// own dropdown.
    let originalAccountID: String?
    @Binding var accountID: String
    var onPick: (SSOAccount) -> Void

    @State private var manual = false

    private var available: [SSOAccount] {
        state.accountsWithoutProfile(forSession: session, excluding: originalAccountID)
    }
    private var loading: Bool { state.accountsLoading.contains(session) }
    private var canDiscover: Bool { state.canDiscoverAccounts(forSession: session) }
    private var hasData: Bool { state.discoveredAccounts[session] != nil }

    var body: some View {
        // Fall back to plain text entry when the user opts in, when there's no
        // session yet, or when SSO can't be queried and nothing was loaded.
        if manual || session.isEmpty || (!canDiscover && !hasData) {
            TextField("Account ID", text: $accountID, prompt: Text("12-digit account number"))
            if !session.isEmpty, canDiscover || hasData {
                Button("Choose from SSO") { manual = false }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        } else {
            HStack {
                Picker("Account", selection: accountSelection) {
                    Text(loading ? "Loading accounts…" : "Choose an account…").tag("")
                    if !accountID.isEmpty,
                       !available.contains(where: { $0.accountID == accountID }) {
                        Text("\(accountID) (current)").tag(accountID)
                    }
                    ForEach(available) { account in
                        Text(account.menuLabel).tag(account.accountID)
                    }
                }
                if loading { ProgressView().controlSize(.small) }
                Button {
                    state.discoverAccounts(forSession: session, force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh accounts from SSO")
                .disabled(loading || !canDiscover)
            }
            if let error = state.accountsError[session] {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else if hasData, available.isEmpty {
                Text("Every account you can access already has a profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Enter account ID manually") { manual = true }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var accountSelection: Binding<String> {
        Binding(
            get: { accountID },
            set: { newValue in
                accountID = newValue
                if let account = state.discoveredAccounts[session]?
                    .first(where: { $0.accountID == newValue }) {
                    onPick(account)
                }
            }
        )
    }
}

/// The role control: a dropdown of roles the account grants (from the SSO
/// Portal) once an account is chosen, otherwise a text field.
private struct RoleField: View {
    @ObservedObject var state: AppState
    let session: String
    let accountID: String
    @Binding var roleName: String

    @State private var manual = false

    private var key: String { state.roleKey(session: session, accountID: accountID) }
    private var roles: [String]? { state.discoveredRoles[key] }
    private var loading: Bool { state.rolesLoading.contains(key) }

    var body: some View {
        if manual || accountID.isEmpty || (roles?.isEmpty ?? true) && !loading {
            TextField("Role name", text: $roleName, prompt: Text("e.g. AdministratorAccess"))
            if let roles, !roles.isEmpty {
                Button("Choose from SSO") { manual = false }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        } else {
            HStack {
                Picker("Role", selection: $roleName) {
                    Text(loading ? "Loading roles…" : "Choose a role…").tag("")
                    if !roleName.isEmpty, !(roles ?? []).contains(roleName) {
                        Text("\(roleName) (current)").tag(roleName)
                    }
                    ForEach(roles ?? [], id: \.self) { role in
                        Text(role).tag(role)
                    }
                }
                if loading { ProgressView().controlSize(.small) }
            }
            Button("Enter role name manually") { manual = true }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

// MARK: - SSO Sessions

private struct SessionsTab: View {
    @ObservedObject var state: AppState
    @State private var selection: String?
    @State private var draft = SSOSessionInfo(name: "", startURL: "", region: "us-east-1", scopes: "sso:account:access")
    @State private var editingOriginalName: String?
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if state.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No SSO Sessions", systemImage: "key.horizontal")
                    } description: {
                        Text("An SSO session holds your Identity Center start URL and region.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(state.sessions) { session in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                if !session.region.isEmpty {
                                    Text(session.region)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(session.name)
                        }
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button {
                        selection = nil
                        beginNewSession()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add an SSO session")
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Delete the selected session")
                    .disabled(selection == nil)
                    Spacer()
                    Text("\(state.sessions.count) session\(state.sessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, maxWidth: 280)

            Form {
                Section(editingOriginalName == nil ? "New SSO Session" : "Edit SSO Session") {
                    TextField("Session name", text: $draft.name, prompt: Text("e.g. aws-sso"))
                    TextField("Start URL", text: $draft.startURL, prompt: Text("https://…awsapps.com/start"))
                    RegionPicker(title: "SSO region", selection: $draft.region, emptyOption: nil)
                    TextField("Registration scopes", text: $draft.scopes)
                }
                Section {
                    HStack {
                        Button(editingOriginalName == nil ? "Add Session" : "Save Changes") {
                            state.saveSession(originalName: editingOriginalName, draft)
                            selection = draft.name
                            editingOriginalName = draft.name
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || draft.startURL.trimmingCharacters(in: .whitespaces).isEmpty
                                  || !hasChanges)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: selection) { _, newValue in
            if let name = newValue, let session = state.sessions.first(where: { $0.name == name }) {
                draft = session
                editingOriginalName = name
            }
        }
        .onAppear {
            if let first = state.sessions.first {
                selection = first.name
            } else {
                beginNewSession()
            }
        }
        .confirmationDialog(
            "Delete SSO session “\(selection ?? "")”?",
            isPresented: $confirmDelete
        ) {
            Button("Delete", role: .destructive) {
                if let name = selection {
                    state.deleteSession(named: name)
                    selection = state.sessions.first?.name
                }
            }
        } message: {
            Text("Profiles that reference this session will stop working until reassigned.")
        }
    }

    /// True when the draft differs from what's saved. A brand-new session
    /// (no original to compare against) always counts as having changes.
    private var hasChanges: Bool {
        guard let name = editingOriginalName,
              let original = state.sessions.first(where: { $0.name == name }) else {
            return true
        }
        return draft != original
    }

    private func beginNewSession() {
        draft = SSOSessionInfo(name: "", startURL: "", region: "us-east-1", scopes: "sso:account:access")
        editingOriginalName = nil
    }
}

// MARK: - Shell Setup

/// Explains how to make the shell's `AWS_PROFILE` track the default profile
/// this app records, for tools that read the environment variable rather than
/// the `[default]` section of ~/.aws/config.
private struct ShellSetupTab: View {
    @State private var copied = false

    private static let snippet = """
    # AWS_PROFILE tracks the `profile = <name>` marker under [default] in
    # ~/.aws/config (written by the Cloud Session Manager menu bar app). A precmd hook re-reads
    # it before each prompt, so switching the default profile in the app takes
    # effect on your next command without re-sourcing.
    _sync_aws_profile() {
      local p
      p=$(awk '
        /^\\[default\\]/     { in_default=1; next }
        /^\\[/              { in_default=0 }
        in_default && /^[[:space:]]*profile[[:space:]]*=/ {
          sub(/^[[:space:]]*profile[[:space:]]*=[[:space:]]*/, "")
          gsub(/[[:space:]]+$/, "")
          print; exit
        }
      ' ~/.aws/config 2>/dev/null)
      [[ -n $p ]] && export AWS_PROFILE=$p
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _sync_aws_profile
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep AWS_PROFILE in sync (zsh)")
                    .font(.title3.bold())

                Text("""
                Switching the default profile here updates the `[default]` section of \
                `~/.aws/config`, so plain `aws` commands follow along automatically. \
                Some tools instead read the `AWS_PROFILE` environment variable. To make \
                your shell keep that variable pointed at the current default, add the \
                snippet below to your `~/.zshrc`.
                """)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("It re-reads the `profile = <name>` marker before each prompt, so a switch in this app takes effect on your next command — no re-sourcing needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal) {
                        Text(Self.snippet)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(Self.snippet, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy snippet",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }

                Text("After adding it, restart your terminal or run `source ~/.zshrc`. Using bash? The same `awk` command works — wrap it in a `PROMPT_COMMAND` function instead of a precmd hook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
