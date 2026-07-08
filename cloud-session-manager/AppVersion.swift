import Foundation

/// The app's own version, for display in the menu. Reads the values the release
/// build stamps into the bundle's Info.plist (`CFBundleShortVersionString` and
/// `CFBundleVersion`); when those are missing — e.g. running the bare binary
/// from `swift build` during development — it falls back to "dev".
enum AppVersion {
    /// What the menu shows, e.g. "1.2.3" for a release or "1.2.3 (42)" when a
    /// distinct build number is present, or "dev" for an un-stamped local build.
    static var displayString: String {
        display(from: Bundle.main.infoDictionary)
    }

    /// Builds the display string from an Info.plist dictionary. Pulled out so
    /// the formatting is testable without a real bundle.
    static func display(from info: [String: Any]?) -> String {
        let marketing = (info?["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let build = (info?["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let marketing else { return "dev" }
        // Only append the build number when it adds information (release builds
        // stamp the CI run number; a plain "1" from the default plist doesn't).
        if let build, build != marketing, build != "1" {
            return "\(marketing) (\(build))"
        }
        return marketing
    }
}
