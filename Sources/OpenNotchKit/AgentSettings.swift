import Foundation

/// Agents settings: one small Codable blob under one key. Clamped on init, decode and set.
public struct AgentSettings: Codable, Equatable, Sendable {
    public static let thresholdRange = 1.5...10.0
    public static let windowRange = 5...30
    static let key = "settings"

    public var threshold: Double { didSet { threshold = Self.clamp(threshold, Self.thresholdRange, 3) } }
    public var windowMinutes: Int { didSet { windowMinutes = min(max(windowMinutes, 5), 30) } }
    public var alertsEnabled: Bool

    public init(threshold: Double = 3, windowMinutes: Int = 10, alertsEnabled: Bool = true) {
        self.threshold = Self.clamp(threshold, Self.thresholdRange, 3)
        self.windowMinutes = min(max(windowMinutes, 5), 30)
        self.alertsEnabled = alertsEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(threshold: try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 3,
                  windowMinutes: try c.decodeIfPresent(Int.self, forKey: .windowMinutes) ?? 10,
                  alertsEnabled: try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true)
    }

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double {
        v.isNaN ? fallback : min(max(v, r.lowerBound), r.upperBound)
    }

    public static func load(from storage: PluginStorage) -> AgentSettings {
        storage.data(forKey: key).flatMap { try? JSONDecoder().decode(AgentSettings.self, from: $0) } ?? AgentSettings()
    }

    public func save(to storage: PluginStorage) {
        storage.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
