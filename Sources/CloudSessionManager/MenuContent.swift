import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.statusDescription)
        if state.isLoggingIn {
            Text("Signing in… complete the browser prompt")
        }
        if let error = state.lastError {
            Text(error)
        }
        if state.loginNeeded, let error = state.credentialFetchError {
            Text(error)
        }

        Divider()

        if state.loginNeeded {
            Button("Log In to SSO") { state.login() }
                .disabled(state.isLoggingIn)
        } else if case .noSession = state.tokenStatus {
            EmptyView()
        } else {
            Button("Renew SSO Login") { state.login() }
            Button("Log Out of SSO") { state.logout() }
        }

        Divider()

        Section("Default Profile") {
            ForEach(state.profiles) { profile in
                Toggle(isOn: Binding(
                    get: { state.defaultProfileName == profile.name },
                    set: { selected in if selected { state.setDefaultProfile(profile) } }
                )) {
                    Text(profileLabel(profile))
                }
            }
        }

        if state.defaultProfileName != nil {
            Button("Copy “export AWS_PROFILE=\(state.defaultProfileName ?? "")”") {
                state.copyExportCommand()
            }
        }

        Divider()

        Button("Manage Profiles…") {
            openWindow(id: "profile-manager")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        awsCLISection

        Divider()

        Button("Quit Cloud Session Manager") {
            NSApp.terminate(nil)
        }
    }

    /// Shows the installed AWS CLI version, or — when it's missing — how to
    /// install it via Homebrew or the official AWS instructions.
    @ViewBuilder
    private var awsCLISection: some View {
        if !state.awsCLIInstalled {
            Text("AWS CLI not installed")
            Button("Copy “\(AppState.cliInstallCommand)”") {
                state.copyInstallCommand()
            }
            Button("Copy Official Installer Command") {
                state.copyOfficialInstallCommand()
            }
            Button("Install Instructions…") {
                state.openInstallInstructions()
            }
        } else if let version = state.awsCLIVersion {
            Text("AWS CLI \(version)")
        } else {
            Text("AWS CLI installed")
        }
    }

    private func profileLabel(_ profile: ProfileInfo) -> String {
        profile.region.isEmpty ? profile.name : "\(profile.name) (\(profile.region))"
    }
}
