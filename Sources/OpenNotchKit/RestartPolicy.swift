import Foundation

/// Decides whether a crashed adapter stream should be restarted. Three
/// failures within a minute means something is systematically broken (e.g.
/// macOS changed the MediaRemote rules) — give up and surface "unavailable"
/// instead of crash-looping a perl process forever.
public struct RestartPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case restart(after: TimeInterval)
        case giveUp
    }

    private var failures: [Date] = []
    private let window: TimeInterval = 60
    private let maxFailures = 3

    public init() {}

    public mutating func recordFailure(at now: Date) -> Decision {
        failures = failures.filter { now.timeIntervalSince($0) < window }
        failures.append(now)
        if failures.count >= maxFailures { return .giveUp }
        return .restart(after: pow(2, Double(failures.count - 1)))   // 1s, 2s
    }

    public mutating func recordSuccess() { failures = [] }
}
