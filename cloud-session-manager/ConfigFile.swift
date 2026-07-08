import Foundation

/// A line inside a config section: either a key/value pair or raw text
/// (comments, blank lines) that must be preserved on rewrite.
enum ConfigLine: Equatable {
    case keyValue(key: String, value: String)
    case raw(String)
}

final class ConfigSection {
    /// Section name as it appears between brackets, e.g. "default",
    /// "profile stridyn-dev", "sso-session aws-sso".
    var name: String
    var lines: [ConfigLine]

    init(name: String, lines: [ConfigLine] = []) {
        self.name = name
        self.lines = lines
    }

    func value(for key: String) -> String? {
        for line in lines {
            if case .keyValue(let k, let v) = line, k == key { return v }
        }
        return nil
    }

    func set(_ key: String, to value: String) {
        for (i, line) in lines.enumerated() {
            if case .keyValue(let k, _) = line, k == key {
                lines[i] = .keyValue(key: k, value: value)
                return
            }
        }
        lines.append(.keyValue(key: key, value: value))
    }

    func remove(_ key: String) {
        lines.removeAll {
            if case .keyValue(let k, _) = $0 { return k == key }
            return false
        }
    }

    var keyValues: [(key: String, value: String)] {
        lines.compactMap {
            if case .keyValue(let k, let v) = $0 { return (k, v) }
            return nil
        }
    }
}

/// Parses and serializes an AWS shared-config-style INI file while
/// preserving comments, blank lines, and unknown keys.
final class ConfigDocument {
    var preamble: [String] = []
    var sections: [ConfigSection] = []

    static func parse(_ text: String) -> ConfigDocument {
        let doc = ConfigDocument()
        var current: ConfigSection?
        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
                    .trimmingCharacters(in: .whitespaces)
                let section = ConfigSection(name: name)
                doc.sections.append(section)
                current = section
                continue
            }
            let isComment = trimmed.hasPrefix("#") || trimmed.hasPrefix(";")
            if !isComment, let eq = rawLine.firstIndex(of: "=") {
                let key = String(rawLine[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(rawLine[rawLine.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, let current {
                    current.lines.append(.keyValue(key: key, value: value))
                    continue
                }
            }
            if let current {
                current.lines.append(.raw(rawLine))
            } else {
                doc.preamble.append(rawLine)
            }
        }
        // Drop trailing blank raw lines inside sections so serialization stays tidy.
        for section in doc.sections {
            while case .raw(let s)? = section.lines.last,
                  s.trimmingCharacters(in: .whitespaces).isEmpty {
                section.lines.removeLast()
            }
        }
        return doc
    }

    func serialize() -> String {
        var out: [String] = preamble.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty || preamble.count == 1 }
        for section in sections {
            if !out.isEmpty { out.append("") }
            out.append("[\(section.name)]")
            for line in section.lines {
                switch line {
                case .keyValue(let k, let v): out.append("\(k) = \(v)")
                case .raw(let s): out.append(s)
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    func section(named name: String) -> ConfigSection? {
        sections.first { $0.name == name }
    }

    func removeSection(named name: String) {
        sections.removeAll { $0.name == name }
    }

    func ensureSection(named name: String) -> ConfigSection {
        if let existing = section(named: name) { return existing }
        let section = ConfigSection(name: name)
        sections.append(section)
        return section
    }

    /// Canonical contents of the [default] section when it mirrors a named
    /// profile: the `profile = <name>` marker followed by a copy of the
    /// source profile's keys.
    static func defaultLines(markerName: String, from source: ConfigSection) -> [ConfigLine] {
        var lines: [ConfigLine] = [.keyValue(key: "profile", value: markerName)]
        for (key, value) in source.keyValues where key != "profile" {
            lines.append(.keyValue(key: key, value: value))
        }
        return lines
    }

    /// If [default] was populated from a named profile (recorded by the
    /// `profile = <name>` marker) but that profile has since been edited,
    /// rebuild [default] from the source profile so it mirrors the current
    /// values. Only marker-managed defaults are touched — a hand-authored
    /// [default] with no marker (or a marker pointing at a missing profile)
    /// is left untouched. Filesystem-free; returns whether it changed anything.
    @discardableResult
    func reconcileDefaultFromMarker() -> Bool {
        guard let def = section(named: "default"),
              let marker = def.value(for: "profile"),
              let source = section(named: "profile \(marker)") else { return false }

        let expected = ConfigDocument.defaultLines(markerName: marker, from: source)
        if def.lines == expected { return false }
        def.lines = expected
        return true
    }
}

/// Locates and reads/writes the AWS shared-config files. The paths are
/// injectable (rooted at an `.aws` directory) so tests can point it at a
/// temporary directory; `AWSConfig.default` is the real `~/.aws`.
struct AWSConfig {
    let configURL: URL
    let ssoCacheDirectory: URL

    init(awsDirectory: URL) {
        self.configURL = awsDirectory.appendingPathComponent("config")
        self.ssoCacheDirectory = awsDirectory.appendingPathComponent("sso/cache")
    }

    static let `default` = AWSConfig(
        awsDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws")
    )

    func load() throws -> ConfigDocument {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        return ConfigDocument.parse(text)
    }

    /// Writes the document back, keeping a backup of the previous contents.
    func save(_ document: ConfigDocument) throws {
        let fm = FileManager.default
        let url = configURL
        // On a fresh machine ~/.aws may not exist yet; the atomic write fails
        // ("the folder doesn't exist") without it. Create it first.
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("config.awssso.bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        try document.serialize().write(to: url, atomically: true, encoding: .utf8)
    }
}
