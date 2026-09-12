import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSinceReferenceDate: 0)

@Test func backsOffThenGivesUpOnThirdRapidFailure() {
    var policy = RestartPolicy()
    #expect(policy.recordFailure(at: t0) == .restart(after: 1))
    #expect(policy.recordFailure(at: t0.addingTimeInterval(5)) == .restart(after: 2))
    #expect(policy.recordFailure(at: t0.addingTimeInterval(10)) == .giveUp)
}

@Test func oldFailuresExpireAfterAMinute() {
    var policy = RestartPolicy()
    _ = policy.recordFailure(at: t0)
    _ = policy.recordFailure(at: t0.addingTimeInterval(5))
    // 61s after the first failure: only the second is still in-window.
    #expect(policy.recordFailure(at: t0.addingTimeInterval(61)) == .restart(after: 2))
}

@Test func successResetsTheWindow() {
    var policy = RestartPolicy()
    _ = policy.recordFailure(at: t0)
    _ = policy.recordFailure(at: t0.addingTimeInterval(1))
    policy.recordSuccess()
    #expect(policy.recordFailure(at: t0.addingTimeInterval(2)) == .restart(after: 1))
}
