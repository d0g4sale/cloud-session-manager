import Foundation

enum CredentialFetchOutcome {
    case success(expiration: Date?)
    case failure(message: String)
}

/// Asks the AWS CLI for the default profile's resolved credentials and their
/// expiration — the authoritative "how long will my aws commands keep
/// working" answer (equivalent to `aws configure export-credentials`).
enum CredentialsFetcher {
    static func fetch(cliPath: String, profile: String?) async -> CredentialFetchOutcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            var arguments = ["configure", "export-credentials"]
            if let profile {
                arguments += ["--profile", profile]
            }
            process.arguments = arguments
            process.environment = AppState.awsSubprocessEnvironment()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0,
                   let json = (try? JSONSerialization.jsonObject(with: outData)) as? [String: Any] {
                    let expiration = (json["Expiration"] as? String)
                        .flatMap(SSOTokenCache.parseDate)
                    continuation.resume(returning: .success(expiration: expiration))
                } else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first ?? ""
                    continuation.resume(returning: .failure(
                        message: message.isEmpty ? "export-credentials failed" : message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(message: error.localizedDescription))
            }
        }
    }
}
