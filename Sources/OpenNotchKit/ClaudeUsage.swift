import Foundation

/// Decodes the Claude plan-usage response (`five_hour`, `seven_day`); other keys are ignored.
public enum ClaudeUsageDecoder {
    private static let keys: [(key: String, label: String)] = [("five_hour", "5h"), ("seven_day", "Weekly")]

    /// nil when the data is not a JSON object or holds no usable window.
    public static func decode(_ data: Data, at now: Date) -> PlanLimits? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let windows: [LimitWindow] = keys.compactMap { key, label in
            guard let w = obj[key] as? [String: Any], let used = w["utilization"] as? Double else { return nil }
            let reset = (w["resets_at"] as? String).flatMap(parseISODate)
            return LimitWindow(label: label, usedPercent: used, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        return PlanLimits(agent: .claude, windows: windows, fetchedAt: now)
    }
}

/// The Claude Code login token, read from the Keychain item's JSON.
public struct ClaudeCredential: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public var refreshToken: String? = nil
    public var scopes: [String] = []

    /// nil when the login is unusable: no token, no expiry, or `loginEnded` set to anything.
    public static func parse(keychainJSON: Data) -> ClaudeCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: keychainJSON) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let ms = oauth["expiresAt"] as? Double,
              (oauth["loginEnded"] ?? NSNull()) is NSNull
        else { return nil }
        return ClaudeCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: ms / 1000),
                                refreshToken: oauth["refreshToken"] as? String, scopes: oauth["scopes"] as? [String] ?? [])
    }

    /// The Keychain JSON with a token-endpoint response folded in, the way Claude Code saves a renewal:
    /// new access token and expiry, new refresh token when one came back, every other field untouched.
    public static func renewed(keychainJSON: Data, response: Data, at now: Date) -> (json: Data, token: String)? {
        guard var root = try? JSONSerialization.jsonObject(with: keychainJSON) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any],
              let res = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let access = res["access_token"] as? String, !access.isEmpty,
              let expiresIn = (res["expires_in"] as? NSNumber)?.doubleValue else { return nil }
        oauth["accessToken"] = access
        oauth["expiresAt"] = Int64((now.timeIntervalSince1970 + expiresIn) * 1000)
        if let refresh = res["refresh_token"] as? String, !refresh.isEmpty { oauth["refreshToken"] = refresh }
        root["claudeAiOauth"] = oauth
        guard let json = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return (json, access)
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }
}
