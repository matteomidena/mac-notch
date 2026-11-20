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

    /// nil when the login is unusable: no token, no expiry, or `loginEnded` set to anything.
    public static func parse(keychainJSON: Data) -> ClaudeCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: keychainJSON) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let ms = oauth["expiresAt"] as? Double,
              (oauth["loginEnded"] ?? NSNull()) is NSNull
        else { return nil }
        return ClaudeCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: ms / 1000))
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }
}
