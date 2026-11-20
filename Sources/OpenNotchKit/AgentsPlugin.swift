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
