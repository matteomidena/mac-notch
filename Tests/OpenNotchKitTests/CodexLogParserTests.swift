import Testing
import Foundation
@testable import OpenNotchKit

private func codexLines() throws -> [String] {
    guard let url = Bundle.module.url(forResource: "Fixtures/codex-rollout", withExtension: "jsonl") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

@Test func codexSessionMetaIds() throws {
    let l = try codexLines()
    let top = try #require(CodexLogParser.parse(l[0]))
    #expect(top.threadId == "00000000-0000-7000-8000-000000000001")
    #expect(top.parentThreadId == nil)
    #expect(top.cwd == "/Users/example/project")
    let sub = try #require(CodexLogParser.parse(l[1]))
    #expect(sub.threadId == "00000000-0000-7000-8000-000000000002")
    #expect(sub.parentThreadId == "00000000-0000-7000-8000-000000000001")
}

@Test func codexTokenCountIsCumulativeAndUncached() throws {
    let p = try #require(CodexLogParser.parse(try codexLines()[2]))
    #expect(p.tokens == .cumulative(TokenCounts(input: 12577, cacheRead: 19584, output: 203)))
}

@Test func codexRateLimitsBecomePlanLimits() throws {
    let p = try #require(CodexLogParser.parse(try codexLines()[2]))
    #expect(p.limits == PlanLimits(
        agent: .codex,
        windows: [LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1795628010))],
        hasCredits: true,
        fetchedAt: parseISODate("2026-01-01T10:00:02.500Z")!))
}

@Test func codexNullInfoStillGivesLimits() throws {
    let p = try #require(CodexLogParser.parse(try codexLines()[3]))
    #expect(p.tokens == nil)
    #expect(p.limits != nil)
}

@Test func codexFirstUserPrompt() throws {
    #expect(CodexLogParser.parse(try codexLines()[4])?.userPrompt == "Fix the build")
}

@Test func codexResponseItemPrompt() {
    let line = #"{"timestamp":"2026-01-01T10:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix"},{"type":"input_text","text":"the build"}]}}"#
    #expect(CodexLogParser.parse(line)?.userPrompt == "Fix\nthe build")
}

@Test func codexInstructionsBlockIsNotAPrompt() {
    let line = #"{"timestamp":"2026-01-01T10:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#
    #expect(CodexLogParser.parse(line)?.userPrompt == nil)
}
