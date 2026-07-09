import AppKit
import SwiftUI

@main
struct CloudSessionManagerApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

/// Launch-time behavior that must run whether or not the menu bar icon is
/// visible. The menu bar item can be pushed into the hidden overflow region
/// (a crowded menu bar / notch), in which case the SwiftUI label is never
/// rendered and its `onAppear` never fires — so anything hung off `onAppear`
/// silently doesn't happen. `applicationDidFinishLaunching` always fires.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirstRunIntro.showIfNeeded()
    }
}

/// On first launch the app has no Dock icon and no window, so it can look like
/// nothing happened — users report "it doesn't start." Show a one-time popover
/// that drops down from the menu bar icon, pointing the user right at it. Gated
/// on a UserDefaults flag so it only ever appears once.
enum FirstRunIntro {
    private static let didShowKey = "didShowMenuBarIntro"
    private static var controller: IntroPopoverController?

    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didShowKey) else { return }
        defaults.set(true, forKey: didShowKey)
        presentWhenReady(attempt: 0)
    }

    /// The SwiftUI `MenuBarExtra` status item may not be on screen yet on the
    /// first runloop pass, so we can't find its frame. Retry briefly, then fall
    /// back to the top-right corner of the primary screen.
    private static func presentWhenReady(attempt: Int) {
        if let rect = MenuBarStatusItem.frame() {
            present(anchoredTo: rect)
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentWhenReady(attempt: attempt + 1)
            }
        } else {
            present(anchoredTo: MenuBarStatusItem.topRightFallback())
        }
    }

    private static func present(anchoredTo rect: NSRect) {
        let controller = IntroPopoverController()
        self.controller = controller
        controller.present(anchoredTo: rect) { self.controller = nil }
    }
}

/// Shows the first-run popover anchored beneath the menu bar icon. It owns a
/// tiny transparent anchor window placed at the status item's frame — the
/// popover needs a real on-screen view to attach to — and tears it down when
/// the popover closes.
private final class IntroPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var anchorWindow: NSWindow?
    private var onClose: (() -> Void)?

    func present(anchoredTo rect: NSRect, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = NSWindow(contentRect: rect, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        let anchorView = NSView(frame: NSRect(origin: .zero, size: rect.size))
        window.contentView = anchorView
        window.orderFrontRegardless()
        anchorWindow = window

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: IntroPopoverView())
        popover.delegate = self

        NSApp.activate(ignoringOtherApps: true)
        // `.minY` places the popover below the anchor, arrow pointing up at the icon.
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
        onClose?()
        onClose = nil
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

/// Locates the app's own `MenuBarExtra` status item so the popover can anchor
/// beneath it. SwiftUI backs the item with an in-process `NSStatusBarWindow`
/// (one per display), so we can read its frame from `NSApp.windows` — a valid
/// Cocoa screen rect, no Screen Recording permission and no coordinate
/// conversion needed.
enum MenuBarStatusItem {
    /// The status item's frame in screen coordinates, if it's laid into a
    /// visible menu bar. Returns nil while the item is unplaced (SwiftUI parks
    /// it offscreen at the left edge until the system positions it) or hidden
    /// in the menu bar overflow — the caller retries, then falls back.
    static func frame() -> NSRect? {
        let candidates = NSApp.windows.filter { window in
            guard String(describing: type(of: window)) == "NSStatusBarWindow",
                  window.isVisible, window.frame.width > 0, window.frame.height > 0
            else { return false }
            // Only a window fully within a screen is actually on the menu bar;
            // an unplaced item sits offscreen (e.g. above the top edge).
            return NSScreen.screens.contains { $0.frame.contains(window.frame) }
        }
        guard !candidates.isEmpty else { return nil }
        if let main = NSScreen.main,
           let onMain = candidates.first(where: { main.frame.intersects($0.frame) }) {
            return onMain.frame
        }
        return candidates.first?.frame
    }

    /// A small anchor at the top-right of the primary screen, just under the
    /// menu bar — used when the status item can't be located (e.g. hidden in
    /// the menu bar overflow).
    static func topRightFallback() -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main ?? NSScreen.screens[0]
        return NSRect(x: screen.frame.maxX - 40, y: screen.frame.maxY - 24,
                      width: 24, height: 22)
    }
}

/// The menu bar icon (AWS logo plus an optional status badge). Also opens the
/// Profile Manager at launch when nothing is set up yet, on first render.
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
