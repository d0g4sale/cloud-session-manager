import AppKit
import SwiftUI

@main
struct CloudSessionManagerApp: App {
    @StateObject private var state = AppState()

    init() {
        // Menu-bar-only app: no Dock icon. (Also set via LSUIElement in the
        // bundle's Info.plist; this covers running the bare binary.)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Window("AWS Profiles", id: "profile-manager") {
            ProfileManagerView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 480)
    }
}

/// The menu bar icon (AWS logo plus an optional status badge). Also the hook
/// for opening the Profile Manager at launch when nothing is set up yet — the
/// label is rendered as soon as the menu bar item appears, so its `onAppear`
/// is a reliable "app finished launching" signal that has `openWindow`.
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var didAutoOpen = false

    var body: some View {
        Image(nsImage: MenuBarIcon.image(badge: state.menuBarBadge))
            .onAppear {
                guard !didAutoOpen else { return }
                didAutoOpen = true
                if state.needsSetup {
                    openWindow(id: "profile-manager")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
