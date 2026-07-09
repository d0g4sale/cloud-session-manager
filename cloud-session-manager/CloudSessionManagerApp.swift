import AppKit
import SwiftUI

@main
struct CloudSessionManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI is a menu-bar status item plus an AppKit-managed window, both
        // owned by the delegate. A no-op Settings scene satisfies App's Scene
        // requirement without opening a window at launch.
        Settings { EmptyView() }
    }
}

/// Owns the app's AppKit surface: the menu-bar status item, the "AWS Profiles"
/// window, and the single `AppState`. Menu-bar-only, so it drives everything
/// from `applicationDidFinishLaunching` rather than a SwiftUI scene.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var menuController: MenuBarController?
    private var profileWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon. (Also set via LSUIElement in the
        // bundle's Info.plist; this covers running the bare binary.)
        NSApp.setActivationPolicy(.accessory)

        let controller = MenuBarController(state: state) { [weak self] in
            self?.showProfileWindow()
        }
        menuController = controller

        // On first launch nothing is configured, so open the editor straight
        // away — otherwise the app looks like it did nothing.
        if state.needsSetup {
            showProfileWindow()
        }
        FirstRunIntro.showIfNeeded(anchoredTo: controller.statusButton)
    }

    /// The app has no Dock icon, so closing the window shouldn't quit it — the
    /// status item is the way back in.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opens (or re-focuses) the profile editor. Managed in AppKit so it can be
    /// summoned from the menu, which isn't a SwiftUI scene.
    private func showProfileWindow() {
        if let window = profileWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: ProfileManagerView(state: state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "AWS Profiles"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        profileWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// On first launch the app has no Dock icon and no window, so it can look like
/// nothing happened — users report "it doesn't start." Show a one-time popover
/// that drops down from the menu bar icon, pointing the user right at it. Gated
/// on a UserDefaults flag so it only ever appears once.
enum FirstRunIntro {
    private static let didShowKey = "didShowMenuBarIntro"
    private static var popover: NSPopover?

    @MainActor
    static func showIfNeeded(anchoredTo button: NSStatusBarButton?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didShowKey), let button else { return }
        defaults.set(true, forKey: didShowKey)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: IntroPopoverView())
        self.popover = popover

        NSApp.activate(ignoringOtherApps: true)
        // `.minY` places the popover below the button, arrow pointing up at it.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

private struct IntroPopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AWS Sessions lives up here")
                .font(.headline)
            Text("""
            There's no Dock icon or window. Click this menu bar icon anytime to \
            sign in, switch profiles, and check your session status.
            """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 260)
    }
}
