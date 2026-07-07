import Testing
import Foundation
import SwiftUI
@testable import OpenNotchKit

private func ev(_ id: String, priority: Int, duration: TimeInterval) -> NotchEvent {
    NotchEvent(id: id, priority: priority, duration: duration, view: AnyView(EmptyView()))
}

@MainActor @Test func currentReturnsPostedEventWithinWindow() {
    var t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("a", priority: 1, duration: 5))
    #expect(q.current?.id == "a")
    t = Date(timeIntervalSince1970: 1006)   // window elapsed
    #expect(q.current == nil)
}

@MainActor @Test func higherPriorityWins() {
    let t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("low", priority: 1, duration: 10))
    q.post(ev("high", priority: 5, duration: 10))
    #expect(q.current?.id == "high")
}

@MainActor @Test func userHoldingSuppressesCurrent() {
    let t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("a", priority: 1, duration: 10))
    q.setUserHolding(true)
    #expect(q.current == nil)               // user interaction wins
    q.setUserHolding(false)
    #expect(q.current?.id == "a")           // resumes (clock was paused)
}
