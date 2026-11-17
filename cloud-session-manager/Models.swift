import CryptoKit
import Foundation

struct ProfileInfo: Identifiable, Hashable {
    var name: String
    var ssoSession: String
    var accountID: String
    var roleName: String
    var region: String
    var output: String

    var id: String { name }

    static func from(section: ConfigSection) -> ProfileInfo? {
        guard section.name.hasPrefix("profile ") else { return nil }
        let name = String(section.name.dropFirst("profile ".count))
        return ProfileInfo(
            name: name,
            ssoSession: section.value(for: "sso_session") ?? "",
            accountID: section.value(for: "sso_account_id") ?? "",
            roleName: section.value(for: "sso_role_name") ?? "",
            region: section.value(for: "region") ?? "",
            output: section.value(for: "output") ?? ""
        )
    }
}

struct SSOSessionInfo: Identifiable, Hashable {
    var name: String
    var startURL: String
    var region: String
    var scopes: String

    var id: String { name }

    static func from(section: ConfigSection) -> SSOSessionInfo? {
        guard section.name.hasPrefix("sso-session ") else { return nil }
        let name = String(section.name.dropFirst("sso-session ".count))
        return SSOSessionInfo(
            name: name,
            startURL: section.value(for: "sso_start_url") ?? "",
            region: section.value(for: "sso_region") ?? "",
            scopes: section.value(for: "sso_registration_scopes") ?? ""
        )
    }
}

enum TokenStatus: Equatable {
    case valid(expires: Date)
    case expired(since: Date)
    case notLoggedIn
    case noSession
}

/// The cached OIDC token the AWS CLI writes after `aws sso login`. Note that
/// `expiresAt` is the short-lived *access token* expiry (often 1 hour) — the
/// SSO session itself usually lasts much longer and is kept alive by
/// exchanging `refreshToken` for fresh access tokens.
struct SSOToken {
    var cacheURL: URL
    var raw: [String: Any]
    var accessToken: String?
    var expiresAt: Date?
    var refreshToken: String?
    var clientID: String?
    var clientSecret: String?
    var region: String?

    var hasAccessToken: Bool { accessToken != nil }

    func status(now: Date = Date()) -> TokenStatus {
        guard hasAccessToken, let expiresAt else { return .notLoggedIn }
        return expiresAt > now ? .valid(expires: expiresAt) : .expired(since: expiresAt)
    }
}

/// An account the signed-in user can access, as returned by the SSO Portal
/// `ListAccounts` API. Roles are fetched separately (`ListAccountRoles`).
struct SSOAccount: Identifiable, Hashable {
    let accountID: String
    let accountName: String
    let emailAddress: String

    var id: String { accountID }
    /// Menu label, e.g. "Dev — 123456789012".
    var menuLabel: String {
        accountName.isEmpty ? accountID : "\(accountName) — \(accountID)"
    }
}

enum SSOTokenCache {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoFractional.date(from: s)
    }

    static func formatDate(_ d: Date) -> String {
        iso.string(from: d)
    }

    /// The AWS CLI caches SSO tokens at ~/.aws/sso/cache/<sha1(sessionName)>.json.
    static func cacheURL(forSession sessionName: String) -> URL {
        let digest = Insecure.SHA1.hash(data: Data(sessionName.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return AWSConfig.default.ssoCacheDirectory.appendingPathComponent("\(hex).json")
    }

    static func load(forSession sessionName: String) -> SSOToken? {
        guard !sessionName.isEmpty else { return nil }
        let url = cacheURL(forSession: sessionName)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return SSOToken(
            cacheURL: url,
            raw: json,
            accessToken: json["accessToken"] as? String,
            expiresAt: (json["expiresAt"] as? String).flatMap(parseDate),
            refreshToken: json["refreshToken"] as? String,
            clientID: json["clientId"] as? String,
            clientSecret: json["clientSecret"] as? String,
            region: json["region"] as? String
        )
    }

    /// Rewrites the cache file the same way the AWS CLI does after a refresh,
    /// preserving all fields and the 0600 permissions.
    static func write(_ token: SSOToken) throws {
        let data = try JSONSerialization.data(withJSONObject: token.raw)
        try data.write(to: token.cacheURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: token.cacheURL.path)
    }
}
