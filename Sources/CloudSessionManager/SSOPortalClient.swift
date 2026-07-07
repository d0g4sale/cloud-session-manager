import Foundation

/// Result of an SSO Portal lookup: either the fetched values or a
/// human-readable reason it failed.
enum SSOPortalResult<Value> {
    case success(Value)
    /// The access token was rejected — a fresh `aws sso login` is needed.
    case unauthorized
    /// Network, throttling, or an unexpected response; worth retrying.
    case failure(String)
}

/// Reads the accounts and roles the signed-in user can access, using the
/// cached SSO access token against the SSO Portal REST API
/// (`portal.sso.<region>.amazonaws.com`) — the same `ListAccounts` /
/// `ListAccountRoles` calls `aws configure sso` makes. Direct HTTPS keeps the
/// bearer token out of process arguments (unlike shelling out to the CLI).
enum SSOPortalClient {
    /// Lists every account the token grants access to, following pagination.
    static func listAccounts(accessToken: String, region: String) async -> SSOPortalResult<[SSOAccount]> {
        var accounts: [SSOAccount] = []
        var nextToken: String?
        repeat {
            var items = [URLQueryItem(name: "max_result", value: "100")]
            if let nextToken { items.append(URLQueryItem(name: "next_token", value: nextToken)) }
            let outcome = await get(
                region: region, path: "/assignment/accounts",
                queryItems: items, accessToken: accessToken)
            switch outcome {
            case .failure(let message): return .failure(message)
            case .unauthorized: return .unauthorized
            case .success(let json):
                let list = json["accountList"] as? [[String: Any]] ?? []
                for entry in list {
                    guard let id = entry["accountId"] as? String else { continue }
                    accounts.append(SSOAccount(
                        accountID: id,
                        accountName: entry["accountName"] as? String ?? "",
                        emailAddress: entry["emailAddress"] as? String ?? ""))
                }
                nextToken = json["nextToken"] as? String
            }
        } while nextToken != nil
        accounts.sort {
            $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
        }
        return .success(accounts)
    }

    /// Lists the roles the token grants for a single account.
    static func listAccountRoles(accessToken: String, accountID: String, region: String)
        async -> SSOPortalResult<[String]>
    {
        var roles: [String] = []
        var nextToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "account_id", value: accountID),
                URLQueryItem(name: "max_result", value: "100"),
            ]
            if let nextToken { items.append(URLQueryItem(name: "next_token", value: nextToken)) }
            let outcome = await get(
                region: region, path: "/assignment/roles",
                queryItems: items, accessToken: accessToken)
            switch outcome {
            case .failure(let message): return .failure(message)
            case .unauthorized: return .unauthorized
            case .success(let json):
                let list = json["roleList"] as? [[String: Any]] ?? []
                roles += list.compactMap { $0["roleName"] as? String }
                nextToken = json["nextToken"] as? String
            }
        } while nextToken != nil
        return .success(roles)
    }

    private static func get(
        region: String, path: String, queryItems: [URLQueryItem], accessToken: String
    ) async -> SSOPortalResult<[String: Any]> {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "portal.sso.\(region).amazonaws.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            return .failure("Could not build SSO portal URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(accessToken, forHTTPHeaderField: "x-amz-sso_bearer_token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { return .unauthorized }
            guard status == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                return .failure("HTTP \(status)")
            }
            return .success(json)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
