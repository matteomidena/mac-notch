import Testing
import Foundation
@testable import OpenNotchKit

@Test func claudeWeightsMatchSpec() {
    let t = TokenCounts(input: 100, cacheWrite: 1000, cacheRead: 10_000, output: 10)
    let expected: Double = 100 + 1250 + 1000 + 50
    #expect(TokenWeights.weighted(t, agent: .claude) == expected)
}

@Test func codexCachedInputAtOneTenth() {
    let t = TokenCounts(input: 1000, cacheRead: 10_000, output: 10)
    #expect(TokenWeights.weighted(t, agent: .codex) == 1000 + 1000 + 10 * TokenWeights.codexOutput)
}

@Test func windowPercentIsZeroAfterReset() {
    let w = LimitWindow(label: "5h", usedPercent: 62, resetsAt: Date(timeIntervalSince1970: 1000))
    #expect(w.percent(at: Date(timeIntervalSince1970: 999)) == 62)
    #expect(w.percent(at: Date(timeIntervalSince1970: 1000)) == 0)
}

@Test func tightestPicksHighestPercentAcrossAgents() {
    let now = Date(timeIntervalSince1970: 0)
    let cc = PlanLimits(agent: .claude,
                        windows: [LimitWindow(label: "5h", usedPercent: 62, resetsAt: nil),
                                  LimitWindow(label: "Weekly", usedPercent: 40, resetsAt: nil)],
                        fetchedAt: now)
    let cx = PlanLimits(agent: .codex,
                        windows: [LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: nil)],
                        fetchedAt: now)
    #expect(tightestLimit([cx, cc], at: now) == TightestLimit(agent: .claude, window: cc.windows[0]))
    #expect(tightestLimit([], at: now) == nil)
}

@Test func windowLabels() {
    #expect(windowLabel(minutes: 300) == "5h")
    #expect(windowLabel(minutes: 10080) == "Weekly")
}
