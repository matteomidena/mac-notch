import Foundation

public struct BurnRate: Equatable, Sendable {
    public var window: TimeInterval
    public let keep: TimeInterval
    private var entries: [(at: Date, weighted: Double)] = []

    public init(window: TimeInterval = 600, keep: TimeInterval = 1800) {
        self.window = window
        self.keep = keep
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.window == b.window && a.keep == b.keep
            && a.entries.map(\.at) == b.entries.map(\.at)
            && a.entries.map(\.weighted) == b.entries.map(\.weighted)
    }

    public mutating func add(_ weighted: Double, at: Date) {
        entries.append((at, weighted))
        let newest = entries.map(\.at).max() ?? at
        entries.removeAll { newest.timeIntervalSince($0.at) > keep }
    }

    private func sum(from: Date, to: Date) -> Double {
        entries.reduce(0) { $1.at > from && $1.at <= to ? $0 + $1.weighted : $0 }
    }

    public func perMinute(at now: Date) -> Double {
        sum(from: now.addingTimeInterval(-window), to: now) / (window / 60)
    }

    public func history(at now: Date, minutes: Int = 30) -> [Double] {
        (0..<max(0, minutes)).map { i in
            sum(from: now.addingTimeInterval(-Double(minutes - i) * 60),
                to: now.addingTimeInterval(-Double(minutes - i - 1) * 60))
        }
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: AgentKind
    public var project: String
    public var firstPrompt: String?
    public var startedAt: Date
    public var lastActivity: Date
    public var totals = TokenCounts()
    public var weightedTotal: Double = 0
    public var burn: BurnRate
    public var activeMinutes: Int { activeMinuteSet.count }
    fileprivate var activeMinuteSet: Set<Int> = []

    public func isLive(at now: Date) -> Bool { now.timeIntervalSince(lastActivity) <= 300 }
}

public final class AgentSessions {
    public private(set) var sessions: [String: AgentSession] = [:]
    public private(set) var latestLimits: [AgentKind: PlanLimits] = [:]

    public var rateWindow: TimeInterval = 600 {
        didSet { for key in sessions.keys { sessions[key]?.burn.window = rateWindow } }
    }

    private var seenMessageIds: [String: Set<String>] = [:]   // fileKey -> Claude message ids
    private var previousCumulative: [String: TokenCounts] = [:]
    private var codexKeys: [String: String] = [:]             // fileKey -> roll-up key

    public init() {}

    public func ingest(_ line: ParsedLogLine, agent: AgentKind, fileKey: String,
                       pathIds: (session: String, parent: String?)?) {
        if let limits = line.limits, limits.fetchedAt > (latestLimits[limits.agent]?.fetchedAt ?? .distantPast) {
            latestLimits[limits.agent] = limits
        }
        if agent == .codex, let thread = line.threadId {
            codexKeys[fileKey] = line.parentThreadId ?? thread
        }
        let key: String?
        switch agent {
        case .claude: key = pathIds.map { $0.parent ?? $0.session }
        case .codex: key = codexKeys[fileKey]
        }
        guard let key, let at = line.at else { return }

        var delta = TokenCounts()
        switch line.tokens {
        case .delta(let t, let messageId)?:
            if let messageId {
                if !seenMessageIds[fileKey, default: []].insert(messageId).inserted { break }
            }
            delta = t
        case .cumulative(let new)?:
            let old = previousCumulative[fileKey] ?? TokenCounts()
            previousCumulative[fileKey] = new
            delta = TokenCounts(input: max(0, new.input - old.input),
                                cacheWrite: max(0, new.cacheWrite - old.cacheWrite),
                                cacheRead: max(0, new.cacheRead - old.cacheRead),
                                output: max(0, new.output - old.output))
        case nil:
            break
        }

        var session: AgentSession
        if let existing = sessions[key] {
            session = existing
        } else {
            session = AgentSession(id: key, agent: agent, project: "", startedAt: at, lastActivity: at,
                                   burn: BurnRate(window: rateWindow))
        }
        if at > session.lastActivity { session.lastActivity = at }
        if session.project.isEmpty, let cwd = line.cwd, !cwd.isEmpty {
            session.project = cwd.split(separator: "/").last.map(String.init) ?? ""
        }
        if session.firstPrompt == nil, let p = line.userPrompt, !p.isEmpty {
            session.firstPrompt = String(p.prefix(120))
        }
        session.totals = session.totals + delta
        let weighted = TokenWeights.weighted(delta, agent: agent)
        if weighted > 0 {
            session.weightedTotal += weighted
            session.burn.add(weighted, at: at)
            session.activeMinuteSet.insert(Int((at.timeIntervalSince1970 / 60).rounded(.down)))
        }
        sessions[key] = session
    }

    public func live(at now: Date) -> [AgentSession] {
        sessions.values.filter { $0.isLive(at: now) }.sorted {
            let (a, b) = ($0.burn.perMinute(at: now), $1.burn.perMinute(at: now))
            return a != b ? a > b : $0.id < $1.id
        }
    }
}
