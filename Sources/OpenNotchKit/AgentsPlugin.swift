import SwiftUI

@MainActor public struct AgentsPlugin: NotchPlugin, NotchTabProvider {
    public static let manifest = PluginManifest(
        id: "cafe.notch.agents", name: "Agents", version: "1.0.0", author: "OpenNotch")
    private let host: PluginHost
    public init(host: PluginHost) { self.host = host }
    public func widgets() -> [PluginWidget] { [] }

    public func tabs() -> [PluginTab] {
        [PluginTab(id: "agents", title: "Agents", systemImage: "sparkle",
                   content: AnyView(AgentsTabView(service: host.agents)))]
    }

    // The Music side owns the left wing.
    public func compactLeading() -> AnyView? { nil }
    public func compactTrailing() -> AnyView? { AnyView(AgentsFigure(service: host.agents)) }
    // Left of the camera belongs to Music; the 5h reset lives in its limit row.
    public func openTrailing() -> AnyView? { AnyView(BurnRateLabel(service: host.agents)) }
}

/// Tokens per minute across every live session.
public func totalBurn(_ sessions: [AgentSession], at now: Date) -> Double {
    sessions.reduce(0) { $0 + $1.burn.perMinute(at: now) }
}

/// Time left until `resetsAt`: "2h 14m", "14m", nil once it has passed.
public func resetText(_ resetsAt: Date?, now: Date) -> String? {
    guard let resetsAt, resetsAt > now else { return nil }
    let m = Int(resetsAt.timeIntervalSince(now) / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(max(m, 1))m"
}

public enum StripAction: Equatable { case redirect, stop, dismiss }

/// Stop and Redirect need the Claude hook; Codex runs are only flagged.
public func stripActions(for agent: AgentKind, canControl: Bool) -> [StripAction] {
    agent == .claude && canControl ? [.redirect, .stop, .dismiss] : [.dismiss]
}

/// 4.31 → "4.3×"
public func multipleText(_ m: Double) -> String { String(format: "%.1f×", m) }

/// 41_000 → "41k", 1_200_000 → "1.2M"
public func compactCount(_ n: Double) -> String {
    func trim(_ v: Double) -> String { v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v) }
    if n >= 1_000_000 { return trim(n / 1_000_000) + "M" }
    if n >= 1_000 { return trim(n / 1_000) + "k" }
    return String(Int(n.rounded()))
}
