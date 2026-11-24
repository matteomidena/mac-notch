import SwiftUI
import Observation

public struct RunawayAlert: Equatable, Sendable {
    public let session: AgentSession
    public let multiple: Double
    public let normal: Double
    public init(session: AgentSession, multiple: Double, normal: Double) {
        self.session = session; self.multiple = multiple; self.normal = normal
    }
}

@MainActor public protocol AgentUsageService: AnyObject, Observable {
    var limits: [PlanLimits] { get }
    var liveSessions: [AgentSession] { get }
    var normalRate: [AgentKind: Double] { get }
    var alert: RunawayAlert? { get }
    /// Claude hook installed.
    var canControl: Bool { get }
    func stop(sessionId: String)
    func redirect(sessionId: String, text: String)
    func dismiss(sessionId: String)
    func refreshLimits()
}

public struct PluginTab: Identifiable {
    public let id, title, systemImage: String
    public let content: AnyView
    public init(id: String, title: String, systemImage: String, content: AnyView) {
        self.id = id; self.title = title; self.systemImage = systemImage; self.content = content
    }
}

/// Separate from `NotchPlugin` so 1.0 bundles are never asked for tabs.
@MainActor public protocol NotchTabProvider { func tabs() -> [PluginTab] }

/// Inert defaults so hosts/plugins built against 1.0 keep compiling.
@MainActor @Observable public final class NoAgents: AgentUsageService {
    public static let shared = NoAgents()
    public var limits: [PlanLimits] { [] }
    public var liveSessions: [AgentSession] { [] }
    public var normalRate: [AgentKind: Double] { [:] }
    public var alert: RunawayAlert? { nil }
    public var canControl: Bool { false }
    public func stop(sessionId: String) {}
    public func redirect(sessionId: String, text: String) {}
    public func dismiss(sessionId: String) {}
    public func refreshLimits() {}
}
