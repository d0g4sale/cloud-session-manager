import Foundation

/// Reports the installed AWS CLI version — the same string `aws --version`
/// prints — so the menu can show what's installed and, when it isn't,
/// point at how to install it.
enum AWSCLIVersion {
    /// Runs `aws --version` and returns just the version (e.g. "2.35.15").
    /// Returns nil when the CLI can't be run or its output can't be parsed.
    static func detect(cliPath: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = ["--version"]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { _ in
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                // v2 prints to stdout; older CLIs printed to stderr — read both.
                let text = [out, err]
                    .compactMap { String(data: $0, encoding: .utf8) }
                    .joined(separator: " ")
                continuation.resume(returning: parse(text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Extracts the version from `aws-cli/2.35.15 Python/… Darwin/… source/…`.
    static func parse(_ output: String) -> String? {
        guard let token = output.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .first(where: { $0.hasPrefix("aws-cli/") }) else { return nil }
        let version = token.dropFirst("aws-cli/".count)
        return version.isEmpty ? nil : String(version)
    }
}
