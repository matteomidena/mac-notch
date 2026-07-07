import Foundation
import SwiftUI

/// A transient island-style alert a plugin asks the host to show (charge started,
/// meeting in 5 min). Priority breaks contention; duration bounds visibility.
public struct NotchEvent: Identifiable {
    public let id: String
    public let priority: Int
    public let duration: TimeInterval
    public let view: AnyView
    public init(id: String, priority: Int, duration: TimeInterval, view: AnyView) {
        self.id = id
        self.priority = priority
        self.duration = duration
        self.view = view
    }
}

/// Arbitrates transient events so plugins can't fight over the notch. Pure logic:
/// the clock is injected and `current` is a computed decision, not a timer.
///
/// ponytail: M3 builds the arbitration only (the risky part). M4 wires
/// `PluginHost.post(event:)` and the panel expansion render — no consumer exists yet.
@MainActor public final class EventQueue {
    private struct Entry { let event: NotchEvent; var postedAt: Date; let seq: Int }
    private let now: () -> Date
    private var entries: [Entry] = []
    private var seq = 0
    private var holding = false
    private var heldAt: Date?

    public init(now: @escaping () -> Date = Date.init) { self.now = now }

    public func post(_ event: NotchEvent) {
        seq += 1
        entries.append(Entry(event: event, postedAt: now(), seq: seq))
    }

    /// While the user is interacting, expiry pauses (heldAt "freezes the clock")
    /// so an event doesn't silently expire behind the user's hover.
    public func setUserHolding(_ holding: Bool) {
        if holding, !self.holding {
            heldAt = now()
        } else if !holding, self.holding, let held = heldAt {
            // Shift every post forward by the paused interval so remaining
            // display time is preserved.
            let delta = now().timeIntervalSince(held)
            entries = entries.map {
                Entry(event: $0.event, postedAt: $0.postedAt.addingTimeInterval(delta), seq: $0.seq)
            }
            heldAt = nil
        }
        self.holding = holding
    }

    public var current: NotchEvent? {
        guard !holding else { return nil }
        let t = now()
        return entries
            .filter { t >= $0.postedAt && t < $0.postedAt.addingTimeInterval($0.event.duration) }
            .sorted { ($0.event.priority, $0.seq) > ($1.event.priority, $1.seq) }
            .first?.event
    }
}
