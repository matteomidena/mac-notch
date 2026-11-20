import Foundation

public enum Baseline {
    public static let minSessions = 10
    public static let defaultNormal: [AgentKind: Double] = [.claude: 30_000, .codex: 15_000]  // ponytail: guess until 10 sessions exist

    /// Average over ACTIVE minutes, not wall time: an idle hour would make every burst look abnormal.
    public static func averageRate(weightedTotal: Double, activeMinutes: Int) -> Double {
        weightedTotal / Double(max(1, activeMinutes))
    }

    /// Median of the positive averages once there are `minSessions` of them, else the agent's default.
    public static func normal(averages: [Double], agent: AgentKind) -> Double {
        let sorted = averages.filter { $0 > 0 }.sorted()
        guard sorted.count >= minSessions else { return defaultNormal[agent] ?? 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

public struct RunawayConfig: Equatable, Sendable {
    public var threshold = 3.0, clearBelow = 2.0, hold: TimeInterval = 120
    public var floor = 200_000.0, cooldown: TimeInterval = 900, reflag = 1.5
    public init() {}
}

public enum RunawayChange: Equatable, Sendable {
    case flagged(sessionId: String, multiple: Double)
    case cleared(sessionId: String)
}

public struct RunawayDetector {
    private struct State {
        var aboveSince: Date?
        var flagged = false
        var ack: (rate: Double, time: Date)?
    }

    public var config: RunawayConfig
    private var states: [String: State] = [:]

    public init(config: RunawayConfig = .init()) { self.config = config }

    public mutating func update(sessionId: String, rate: Double, weightedTotal: Double,
                                normal: Double, at now: Date) -> RunawayChange? {
        guard normal > 0 else { return nil }
        var s = states[sessionId] ?? State()
        defer { states[sessionId] = s }

        if s.flagged {
            guard rate < config.clearBelow * normal else { return nil }
            s.flagged = false
            s.aboveSince = nil
            return .cleared(sessionId: sessionId)
        }

        var above = rate >= config.threshold * normal && weightedTotal >= config.floor
        if above, let ack = s.ack, now < ack.time.addingTimeInterval(config.cooldown) {
            above = rate >= config.reflag * ack.rate
        }
        guard above else { s.aboveSince = nil; return nil }

        let since = s.aboveSince ?? now
        s.aboveSince = since
        guard now.timeIntervalSince(since) >= config.hold else { return nil }
        s.flagged = true
        return .flagged(sessionId: sessionId, multiple: rate / normal)
    }

    /// Stop, Redirect or ×: un-flag and start the cooldown.
    public mutating func acknowledge(sessionId: String, rate: Double, at now: Date) {
        var s = states[sessionId] ?? State()
        s.flagged = false
        s.aboveSince = nil
        s.ack = (rate, now)
        states[sessionId] = s
    }

    public func isFlagged(_ sessionId: String) -> Bool { states[sessionId]?.flagged ?? false }
}
