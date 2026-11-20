import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func up(_ d: inout RunawayDetector, _ rate: Double, total: Double = 300_000, _ s: TimeInterval) -> RunawayChange? {
    d.update(sessionId: "s", rate: rate, weightedTotal: total, normal: 10_000, at: at(s))
}

@Suite struct RunawayDetectorTests {
    @Test func flagsOnlyAfterHold() {
        var d = RunawayDetector()
        #expect(up(&d, 31_000, 0) == nil)
        #expect(up(&d, 31_000, 60) == nil)
        #expect(up(&d, 31_000, 120) == .flagged(sessionId: "s", multiple: 3.1))
        #expect(d.isFlagged("s"))
        #expect(up(&d, 31_000, 180) == nil)
    }

    @Test func floorBlocksSmallSessions() {
        var d = RunawayDetector()
        for s in stride(from: 0.0, through: 600, by: 60) {
            #expect(up(&d, 50_000, total: 150_000, s) == nil)
        }
        #expect(!d.isFlagged("s"))
    }

    @Test func dipRestartsHold() {
        var d = RunawayDetector()
        #expect(up(&d, 31_000, 0) == nil)
        #expect(up(&d, 25_000, 60) == nil)
        #expect(up(&d, 31_000, 90) == nil)
        #expect(up(&d, 31_000, 180) == nil)
        #expect(up(&d, 31_000, 210) == .flagged(sessionId: "s", multiple: 3.1))
    }

    @Test func hysteresis() {
        var d = RunawayDetector()
        _ = up(&d, 31_000, 0)
        _ = up(&d, 31_000, 120)
        #expect(up(&d, 25_000, 130) == nil)
        #expect(d.isFlagged("s"))
        #expect(up(&d, 19_000, 140) == .cleared(sessionId: "s"))
        #expect(!d.isFlagged("s"))
    }

    @Test func cooldownAfterAcknowledge() {
        var d = RunawayDetector()
        _ = up(&d, 31_000, 0)
        _ = up(&d, 31_000, 120)
        d.acknowledge(sessionId: "s", rate: 31_000, at: at(130))
        #expect(!d.isFlagged("s"))
        for s in stride(from: 140.0, through: 740, by: 60) {
            #expect(up(&d, 31_000, s) == nil)
        }
        #expect(up(&d, 47_000, 760) == nil)
        #expect(up(&d, 47_000, 880) == .flagged(sessionId: "s", multiple: 4.7))
    }

    @Test func cooldownExpires() {
        var d = RunawayDetector()
        d.acknowledge(sessionId: "s", rate: 31_000, at: at(0))
        #expect(up(&d, 31_000, 900) == nil)
        #expect(up(&d, 31_000, 1_020) == .flagged(sessionId: "s", multiple: 3.1))
    }

    @Test func zeroNormalNeverFlags() {
        var d = RunawayDetector()
        for s in [0.0, 60, 120, 180] {
            #expect(d.update(sessionId: "s", rate: 31_000, weightedTotal: 300_000, normal: 0, at: at(s)) == nil)
        }
        #expect(!d.isFlagged("s"))
    }

    @Test func normalUsesMedianFromTenSessions() {
        #expect(Baseline.normal(averages: (1...10).map(Double.init), agent: .claude) == 5.5)
        #expect(Baseline.normal(averages: (1...9).map(Double.init), agent: .claude) == Baseline.defaultNormal[.claude])
    }

    @Test func normalIgnoresNonPositiveAverages() {
        let nine = (1...9).map(Double.init)
        #expect(Baseline.normal(averages: nine + [0], agent: .codex) == Baseline.defaultNormal[.codex])
        #expect(Baseline.normal(averages: nine + [-3], agent: .codex) == Baseline.defaultNormal[.codex])
        #expect(Baseline.normal(averages: nine + [0, 10], agent: .codex) == 5.5)
    }

    @Test func averageOverActiveMinutes() {
        #expect(Baseline.averageRate(weightedTotal: 600_000, activeMinutes: 20) == 30_000)
        #expect(Baseline.averageRate(weightedTotal: 600_000, activeMinutes: 0) == 600_000)
    }
}
