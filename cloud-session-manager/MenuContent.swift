import AppKit
import Combine

/// Owns the menu-bar `NSStatusItem` and builds its `NSMenu` in AppKit.
///
/// This is AppKit rather than SwiftUI's `MenuBarExtra` on purpose: the profile
/// rows use **alternate menu items** (`NSMenuItem.isAlternate`) so holding ⌥
/// live-swaps a profile from "make default" to "open in the AWS console" — the
/// same mechanism the system Window menu uses for "Minimize → Minimize All".
/// SwiftUI's menu doesn't expose `isAlternate`, so the menu is built by hand.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let state: AppState
    /// Opens the "AWS Profiles" window (owned by the app delegate).
    private let openProfileWindow: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    /// The last badge rendered into the button, so the icon is only recomposed
    /// when it actually changes (the state publishes far more often than that).
    /// The outer optional distinguishes "never drawn" from "drawn as no badge".
    private var lastBadge: MenuBarBadge??

    /// The status-bar button, so the first-run popover can anchor beneath it.
    var statusButton: NSStatusBarButton? { statusItem.button }

    init(state: AppState, openProfileWindow: @escaping () -> Void) {
        self.state = state
        self.openProfileWindow = openProfileWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        // Manage enabled state ourselves — auto-enabling would light up items
        // (e.g. "Log In" while signing in) that we deliberately disable.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        refreshIcon()
        // The badge tracks credential/session status, refreshed on AppState's
        // 1-second poll. Re-render the icon whenever that state changes.
        state.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in self?.refreshIcon() }
            }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        let badge = state.menuBarBadge
        if let last = lastBadge, last == badge { return }
        lastBadge = .some(badge)
        statusItem.button?.image = MenuBarIcon.image(badge: badge)
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(state.statusDescription))
        if state.isLoggingIn {
            menu.addItem(disabled("Signing in… complete the browser prompt"))
        }
        if let error = state.lastError {
            menu.addItem(disabled(error))
        }
        if state.loginNeeded, let error = state.credentialFetchError {
            menu.addItem(disabled(error))
        }

        appendSeparator(menu)

        if state.loginNeeded {
            let item = action("Log In to SSO", #selector(login))
            item.isEnabled = !state.isLoggingIn
            menu.addItem(item)
        } else if case .noSession = state.tokenStatus {
            // Nothing to renew or sign out of yet.
        } else {
            menu.addItem(action("Renew SSO Login", #selector(login)))
            menu.addItem(action("Log Out of SSO", #selector(logout)))
        }

        appendSeparator(menu)
        addProfileItems(to: menu)

        appendSeparator(menu)
        if let name = state.defaultProfileName {
            menu.addItem(action("Copy “export AWS_PROFILE=\(name)”", #selector(copyExport)))
        }

        appendSeparator(menu)
        menu.addItem(action("Manage Profiles…", #selector(manageProfiles)))

        appendSeparator(menu)
        addCLISection(to: menu)

        appendSeparator(menu)
        menu.addItem(disabled("Version \(AppVersion.displayString)"))
        menu.addItem(action("Quit AWS Sessions", #selector(quit)))
    }

    private func addProfileItems(to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Default Profile"))

        var anyConsole = false
        for profile in state.profiles {
            let checked = state.defaultProfileName == profile.name

            // Custom-view rows so a link icon can be right-justified — standard
            // menu items can't trail an arbitrary image. A click makes the
            // profile the default.
            let primary = NSMenuItem()
            primary.title = profileLabel(profile)   // for VoiceOver / type-select
            primary.view = ProfileRowView(title: profileLabel(profile), checked: checked,
                                          showLink: false) { [weak self] in
                self?.state.setDefaultProfile(profile)
            }
            menu.addItem(primary)

            // The ⌥ alternate is an identical row plus the trailing link icon.
            // Same (empty) key equivalent + an .option modifier mask makes AppKit
            // swap it in live while ⌥ is held; it must immediately follow its
            // primary to be grouped. A click opens the console instead.
            guard state.consoleURL(for: profile) != nil else { continue }
            anyConsole = true
            let alternate = NSMenuItem()
            alternate.title = profileLabel(profile)
            alternate.isAlternate = true
            alternate.keyEquivalentModifierMask = .option
            alternate.view = ProfileRowView(title: profileLabel(profile), checked: checked,
                                            showLink: true) { [weak self] in
                guard let url = self?.state.consoleURL(for: profile) else { return }
                NSWorkspace.shared.open(url)
            }
            menu.addItem(alternate)
        }

        if anyConsole {
            menu.addItem(hint("Hold ⌥ to open a profile in the AWS console"))
        }
    }

    private func addCLISection(to menu: NSMenu) {
        if !state.awsCLIInstalled {
            menu.addItem(disabled("AWS CLI not installed"))
            menu.addItem(action("Copy “\(AppState.cliInstallCommand)”", #selector(copyInstall)))
            menu.addItem(action("Copy Official Installer Command", #selector(copyOfficialInstall)))
            menu.addItem(action("Install Instructions…", #selector(installInstructions)))
        } else if let version = state.awsCLIVersion {
            menu.addItem(disabled("AWS CLI \(version)"))
        } else {
            menu.addItem(disabled("AWS CLI installed"))
        }
    }

    // MARK: - Item helpers

    private func profileLabel(_ profile: ProfileInfo) -> String {
        profile.region.isEmpty ? profile.name : "\(profile.name) (\(profile.region))"
    }

    /// An enabled, self-targeted item.
    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    /// A greyed-out, non-interactive label row.
    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A small, secondary caption row — reads as a hint rather than a full
    /// menu command (the default menu font is used for real items).
    private func hint(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        return item
    }

    /// Adds a separator unless the menu is empty or already ends with one, so
    /// sections that render nothing don't leave doubled or leading dividers.
    private func appendSeparator(_ menu: NSMenu) {
        if let last = menu.items.last, !last.isSeparatorItem {
            menu.addItem(.separator())
        }
    }

    // MARK: - Actions

    @objc private func login() { state.login() }
    @objc private func logout() { state.logout() }
    @objc private func copyExport() { state.copyExportCommand() }
    @objc private func manageProfiles() { openProfileWindow() }
    @objc private func copyInstall() { state.copyInstallCommand() }
    @objc private func copyOfficialInstall() { state.copyOfficialInstallCommand() }
    @objc private func installInstructions() { state.openInstallInstructions() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// A custom-drawn profile row. Standard menu items can't right-justify an
/// arbitrary image, so the checkmark, title, and (optional) trailing link icon
/// are drawn by hand — approximating the system menu row so it sits alongside
/// the standard items. The ⌥ variant of a profile uses one of these with
/// `showLink` on; AppKit's alternate-item swap reveals it live while ⌥ is held.
@MainActor
private final class ProfileRowView: NSView {
    private let title: String
    private let checked: Bool
    private let showLink: Bool
    private let onSelect: () -> Void

    /// Where the title starts — roughly the system menu's text inset, leaving a
    /// checkmark column to its left.
    private let textLeft: CGFloat = 21
    private let font = NSFont.menuFont(ofSize: 0)

    init(title: String, checked: Bool, showLink: Bool, onSelect: @escaping () -> Void) {
        self.title = title
        self.checked = checked
        self.showLink = showLink
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // View-based menu items don't stretch to the menu width on their own; match
    // the content view so the highlight spans the full row like other items.
    override func viewWillDraw() {
        if let width = superview?.bounds.width, width > 0, abs(width - bounds.width) > 0.5 {
            setFrameSize(NSSize(width: width, height: bounds.height))
        }
        super.viewWillDraw()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    // Highlight is driven by the menu item's own state (see draw); these only
    // nudge a redraw as the pointer moves across the row.
    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
        onSelect()
    }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit keeps exactly one item highlighted; trusting it (rather than a
        // local hover flag) avoids rows getting stranded highlighted when the ⌥
        // alternate swaps the view out from under the pointer.
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let color: NSColor = highlighted ? .alternateSelectedControlTextColor : .labelColor

        if checked, let check = symbol("checkmark", weight: .semibold, color: color) {
            draw(check, at: NSPoint(x: textLeft - check.size.width - 4,
                                    y: (bounds.height - check.size.height) / 2))
        }

        let attributed = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: textLeft, y: (bounds.height - size.height) / 2))

        if showLink, let arrow = symbol("arrow.up.forward.app", weight: .regular, color: color) {
            draw(arrow, at: NSPoint(x: bounds.maxX - 13 - arrow.size.width,
                                    y: (bounds.height - arrow.size.height) / 2))
        }
    }

    private func draw(_ image: NSImage, at point: NSPoint) {
        image.draw(at: point, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1)
    }

    /// An SF Symbol rendered at the menu font size and flat-tinted to `color`
    /// (symbols are template images, so source-atop paints the glyph).
    private func symbol(_ name: String, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: weight)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let image = NSImage(size: base.size)
        image.lockFocus()
        base.draw(at: .zero, from: NSRect(origin: .zero, size: base.size),
                  operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
