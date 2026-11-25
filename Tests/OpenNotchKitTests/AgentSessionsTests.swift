import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tokens(_ input: Int = 0, output: Int = 0) -> TokenCounts {
    TokenCounts(input: input, output: output)
}

private func deltaLine(_ t: TokenCounts, id: String?, at: Date = t0) -> ParsedLogLine {
    ParsedLogLine(at: at, tokens: .delta(t, messageId: id))
}

@MainActor @Test func repeatedMessageIdCountsOnce() {
    let s = AgentSessions()
    let t = tokens(10, output: 5)
    for _ in 0..<2 {
        s.ingest(deltaLine(t, id: "m1"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    }
    #expect(s.sessions["S"]?.totals == t)
}

@MainActor @Test func claudeSubagentRollsUpIntoParent() {
    let s = AgentSessions()
    s.ingest(deltaLine(tokens(7), id: "m1"), agent: .claude, fileKey: "f", pathIds: ("agent-a", "P"))
    #expect(s.sessions["P"]?.totals == tokens(7))
    #expect(s.sessions["agent-a"] == nil)
}

@MainActor @Test func codexSubagentRollsUpIntoParent() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(at: t0, threadId: "child", parentThreadId: "P"), agent: .codex, fileKey: "f", pathIds: nil)
    s.ingest(ParsedLogLine(at: t0, tokens: .cumulative(tokens(40))), agent: .codex, fileKey: "f", pathIds: nil)
    #expect(s.sessions["P"]?.totals == tokens(40))
}

@MainActor @Test func codexCumulativeIsDifferenced() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(at: t0, threadId: "T"), agent: .codex, fileKey: "f", pathIds: nil)
    for n in [100, 250, 50] {
        s.ingest(ParsedLogLine(at: t0, tokens: .cumulative(tokens(n))), agent: .codex, fileKey: "f", pathIds: nil)
    }
    #expect(s.sessions["T"]?.totals.input == 250)
}

@Test func burnRateTrailingWindow() {
    var b = BurnRate()
    b.add(6000, at: t0)
    b.add(6000, at: t0.addingTimeInterval(300))
    #expect(b.perMinute(at: t0.addingTimeInterval(300)) == 1200)
    #expect(b.perMinute(at: t0.addingTimeInterval(700)) == 600)
}

@Test func historyHasThirtyBuckets() {
    var b = BurnRate()
    b.add(5, at: t0)
    let h = b.history(at: t0)
    #expect(h.count == 30)
    #expect(h.last == 5)
}

@MainActor @Test func liveWithinFiveMinutes() {
    let s = AgentSessions()
    s.ingest(deltaLine(tokens(1), id: "m"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    let session = s.sessions["S"]!
    #expect(session.isLive(at: t0.addingTimeInterval(299)))
    #expect(!session.isLive(at: t0.addingTimeInterval(301)))
}

@MainActor @Test func projectAndFirstPrompt() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(at: t0, cwd: "/a/b/mac-notch", userPrompt: "first"),
             agent: .claude, fileKey: "f", pathIds: ("S", nil))
    s.ingest(deltaLine(tokens(1), id: "m"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    s.ingest(ParsedLogLine(at: t0, cwd: "/x/other", userPrompt: "second"),
             agent: .claude, fileKey: "f", pathIds: ("S", nil))
    #expect(s.sessions["S"]?.project == "mac-notch")
    #expect(s.sessions["S"]?.firstPrompt == "first")

    s.ingest(ParsedLogLine(at: t0, tokens: .delta(tokens(1), messageId: "n"), userPrompt: String(repeating: "x", count: 200)),
             agent: .claude, fileKey: "g", pathIds: ("L", nil))
    #expect(s.sessions["L"]?.firstPrompt?.count == 120)
}

@MainActor @Test func newestLimitsWin() {
    let s = AgentSessions()
    func limits(_ pct: Double, _ at: Double) -> PlanLimits {
        PlanLimits(agent: .codex, windows: [LimitWindow(label: "5h", usedPercent: pct, resetsAt: nil)],
                   fetchedAt: Date(timeIntervalSince1970: at))
    }
    s.ingest(ParsedLogLine(at: t0, limits: limits(50, 200)), agent: .codex, fileKey: "f", pathIds: nil)
    s.ingest(ParsedLogLine(at: t0, limits: limits(10, 100)), agent: .codex, fileKey: "f", pathIds: nil)
    #expect(s.latestLimits[.codex]?.windows.first?.usedPercent == 50)
}

@MainActor @Test func rateWindowAppliesToExistingSessions() {
    let s = AgentSessions()
    s.ingest(deltaLine(tokens(600), id: "m"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    s.rateWindow = 60
    #expect(s.sessions["S"]?.burn.window == 60)
    #expect(s.sessions["S"]!.burn.perMinute(at: t0) == 600)
    s.ingest(deltaLine(tokens(1), id: "n"), agent: .claude, fileKey: "g", pathIds: ("N", nil))
    #expect(s.sessions["N"]?.burn.window == 60)
}

// An interrupted turn (Esc, or the desktop app abandoning a session it relocated) is not "needs you".
@MainActor @Test func interruptedSessionIsHidden() throws {
    let line = #"{"type":"user","timestamp":"2026-11-25T07:53:36.000Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    let parsed = try #require(ClaudeLogParser.parse(line))
    #expect(parsed.state == .idle)
    let s = AgentSessions()
    s.ingest(parsed, agent: .claude, fileKey: "f", pathIds: ("S", nil))
    #expect(s.live(at: parsed.at!).isEmpty)
}
