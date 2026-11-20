import Foundation

/// What the Keychain read found. The host maps OS statuses onto this; no token text crosses into logs.
public enum ClaudeCredentialRead: Sendable {
    case data(Data)
    case notFound
    case denied  // user cancelled or denied: the caller drops the connected flag
}

public enum ClaudeUsageOutcome: Equatable, Sendable {
    case snapshot(PlanLimits)
    case none      // nothing new: keep the last snapshot
    case denied
}

/// One attempt per window, counted on attempts (not successes) so a 401 is never retried faster.
public struct ClaudeFetchGate: Sendable {
    public static let interval: TimeInterval = 60
    private var last: Date?
    public init() {}
    public mutating func allow(at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < Self.interval { return false }
        last = now
        return true
    }
}

public enum ClaudeUsageFlow {
    /// Reads the credential, then fetches once. Any non-200 or missing/expired credential is `.none`: no retry, no refresh.
    public static func run(
        at now: Date,
        read: @Sendable () -> ClaudeCredentialRead,
        fetch: @Sendable (_ token: String) async -> (status: Int, body: Data)?
    ) async -> ClaudeUsageOutcome {
        switch read() {
        case .denied: return .denied
        case .notFound: return .none
        case .data(let json):
            guard let cred = ClaudeCredential.parse(keychainJSON: json), !cred.isExpired(at: now),
                  let res = await fetch(cred.accessToken), res.status == 200,
                  let limits = ClaudeUsageDecoder.decode(res.body, at: now) else { return .none }
            return .snapshot(limits)
        }
    }
}

/// nil while fresh; "N min ago" once a snapshot is 3+ minutes old.
public func limitAgeText(fetchedAt: Date, now: Date) -> String? {
    let minutes = Int(now.timeIntervalSince(fetchedAt) / 60)
    return minutes >= 3 ? "\(minutes) min ago" : nil
}
