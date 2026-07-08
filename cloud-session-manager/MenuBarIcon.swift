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
    /// The AWS logo with an optional status badge composited into its
    /// bottom-trailing corner. Returned as a **non-template** image so the
    /// badge's color survives in the menu bar (a template image would be
    /// flattened to a single monochrome tint). The logo itself is tinted to
    /// `labelColor`, resolved at draw time inside the handler, so it still
    /// adapts to a light vs dark menu bar.
    static func image(badge: MenuBarBadge?) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            if let logo = NSImage(named: "AWSLogo") {
                // The Font Awesome mark is wider than it is tall (viewBox
                // 640×512). Scale it to fill the height, preserving aspect,
                // then tint the alpha shape to labelColor via source-atop.
                let logoHeight: CGFloat = 14
                let logoWidth = logoHeight * (logo.size.width / logo.size.height)
                let rect = NSRect(x: 0, y: (size.height - logoHeight) / 2,
                                  width: logoWidth, height: logoHeight)
                logo.draw(in: rect)
                NSColor.labelColor.set()
                rect.fill(using: .sourceAtop)
            }
            if let badge {
                let badgeCfg = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
                    .applying(.init(paletteColors: [.white, badge.color]))
                if let b = NSImage(systemSymbolName: badge.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(badgeCfg) {
                    let bs = b.size
                    // Tuck the badge flush into the bottom-trailing corner
                    // (like the Teams presence dot). Keep y at 0 so the bottom
                    // of the disc isn't clipped by the image bounds.
                    b.draw(in: NSRect(x: size.width - bs.width + 1, y: 0,
                                      width: bs.width, height: bs.height))
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
