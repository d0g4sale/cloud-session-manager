import AppKit

/// The status badge overlaid on the menu bar cloud. Each case maps to an SF
/// Symbol (a `.circle.fill` so it reads as a colored disc with a white glyph)
/// and a color.
enum MenuBarBadge: Equatable {
    case signedIn    // valid credentials
    case signedOut   // no token / logged out
    case attention   // session ended or expired, sign-in required
    case working     // signing in or auto-renewing

    var symbol: String {
        switch self {
        case .signedIn:  return "checkmark.circle.fill"
        case .signedOut: return "xmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .working:   return "hourglass.circle.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .signedIn:  return .systemGreen
        case .signedOut: return .systemGray
        case .attention: return .systemOrange
        case .working:   return .systemGray
        }
    }
}

enum MenuBarIcon {
    /// A cloud glyph with an optional status badge composited into its
    /// bottom-trailing corner. Returned as a **non-template** image so the
    /// badge's color survives in the menu bar (a template image would be
    /// flattened to a single monochrome tint). The cloud itself uses
    /// `labelColor`, resolved at draw time inside the handler, so it still
    /// adapts to a light vs dark menu bar.
    static func image(badge: MenuBarBadge?) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let cloudCfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(.init(hierarchicalColor: .labelColor))
            if let cloud = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "AWS SSO")?
                .withSymbolConfiguration(cloudCfg) {
                let cs = cloud.size
                cloud.draw(in: NSRect(x: 0, y: (size.height - cs.height) / 2,
                                      width: cs.width, height: cs.height))
            }
            if let badge {
                let badgeCfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                    .applying(.init(paletteColors: [.white, badge.color]))
                if let b = NSImage(systemSymbolName: badge.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(badgeCfg) {
                    let bs = b.size
                    b.draw(in: NSRect(x: size.width - bs.width, y: 0, width: bs.width, height: bs.height))
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
