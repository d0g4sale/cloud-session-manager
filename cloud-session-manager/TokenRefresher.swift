import Foundation

enum TokenRefreshResult {
    case refreshed
    /// The Identity Center session itself has ended — a new `aws sso login`
    /// is required. This is the authoritative "session expired" signal.
    case sessionEnded
    /// Transient problem (network, throttling); worth retrying later.
    case transientFailure(String)
}

/// Exchanges the cached refreshToken for a new access token, the same
/// SSO-OIDC CreateToken call the AWS CLI performs transparently.
enum TokenRefresher {
    static func refresh(_ token: SSOToken) async -> TokenRefreshResult {
        guard let clientID = token.clientID,
              let clientSecret = token.clientSecret,
              let refreshToken = token.refreshToken,
              let region = token.region,
              let url = URL(string: "https://oidc.\(region).amazonaws.com/token")
        else {
            return .sessionEnded
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "clientId": clientID,
            "clientSecret": clientSecret,
            "grantType": "refresh_token",
            "refreshToken": refreshToken,
        ])
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            if status == 200,
               let json,
               let accessToken = json["accessToken"] as? String,
               let expiresIn = (json["expiresIn"] as? NSNumber)?.doubleValue {
                var updated = token
                updated.raw["accessToken"] = accessToken
                updated.raw["expiresAt"] = SSOTokenCache.formatDate(Date(timeIntervalSinceNow: expiresIn))
                if let newRefresh = json["refreshToken"] as? String {
                    updated.raw["refreshToken"] = newRefresh
                }
                try SSOTokenCache.write(updated)
                return .refreshed
            }

            let code = json?["error"] as? String ?? ""
            // invalid_grant / expired_token: the refresh token is no longer
            // honored, i.e. the SSO session has genuinely ended.
            if ["invalid_grant", "expired_token", "access_denied", "unauthorized_client"].contains(code) {
                return .sessionEnded
            }
            return .transientFailure("HTTP \(status) \(code)")
        } catch {
            return .transientFailure(error.localizedDescription)
        }
    }
}
