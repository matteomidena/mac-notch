import Foundation

public enum AgentKind: String, Sendable, Codable, CaseIterable {
    case claude = "CC"
    case codex = "CX"
}

/// Token usage for one agent. Codex: `input` is uncached, `cacheRead` is cached.
public struct TokenCounts: Equatable, Sendable {
    public var input, cacheWrite, cacheRead, output: Int

    public init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.output = output
    }

    public static func + (a: Self, b: Self) -> Self {
        Self(input: a.input + b.input,
             cacheWrite: a.cacheWrite + b.cacheWrite,
             cacheRead: a.cacheRead + b.cacheRead,
             output: a.output + b.output)
    }
}

public enum TokenWeights {
    // ponytail: list price out÷in for Codex's default model; update with prices
    public static let codexOutput: Double = 8

    public static func weighted(_ t: TokenCounts, agent: AgentKind) -> Double {
        switch agent {
        case .claude:
            return Double(t.input) + Double(t.cacheWrite) * 1.25
                + Double(t.cacheRead) / 10 + Double(t.output) * 5
        case .codex:
            return Double(t.input) + Double(t.cacheRead) / 10
                + Double(t.output) * codexOutput
        }
    }
}

public struct LimitWindow: Equatable, Sendable, Codable {
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// Usage in this window at `now`; a window that has already reset reads 0.
    public func percent(at now: Date) -> Double {
        if let resetsAt, now >= resetsAt { return 0 }
        return usedPercent
    }
}

public struct PlanLimits: Equatable, Sendable, Codable {
    public let agent: AgentKind
    public let windows: [LimitWindow]
    public let fetchedAt: Date

    public init(agent: AgentKind, windows: [LimitWindow], fetchedAt: Date) {
        self.agent = agent
        self.windows = windows
        self.fetchedAt = fetchedAt
    }
}

public struct TightestLimit: Equatable {
    public let agent: AgentKind
    public let window: LimitWindow

    public init(agent: AgentKind, window: LimitWindow) {
        self.agent = agent
        self.window = window
    }
}

/// The window closest to its cap across all agents, or nil when there are no windows.
public func tightestLimit(_ all: [PlanLimits], at now: Date) -> TightestLimit? {
    var best: (agent: AgentKind, window: LimitWindow, percent: Double)?
    for limits in all {
        for window in limits.windows {
            let percent = window.percent(at: now)
            if best == nil || percent > best!.percent {
                best = (limits.agent, window, percent)
            }
        }
    }
    return best.map { TightestLimit(agent: $0.agent, window: $0.window) }
}

public func windowLabel(minutes: Int) -> String {
    switch minutes {
    case 300: return "5h"
    case 10080: return "Weekly"
    default: return "\(minutes / 60)h"
    }
}
