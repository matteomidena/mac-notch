import Testing
import Foundation
@testable import OpenNotchKit

private func fixtureLines() throws -> [String] {
    guard let url = Bundle.module.url(forResource: "Fixtures/claude-transcript", withExtension: "jsonl") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

@Test func splitterKeepsPartialLine() {
    var s = LineSplitter()
    #expect(s.feed(Data("a\nb".utf8)) == ["a"])
    #expect(s.feed(Data("c\n".utf8)) == ["bc"])
}

@Test func parsesAssistantUsage() throws {
    let p = try #require(ClaudeLogParser.parse(try fixtureLines()[1]))
    #expect(p.tokens == .delta(TokenCounts(input: 2, cacheWrite: 1073, cacheRead: 202787, output: 24), messageId: "msg_1"))
    #expect(p.cwd == "/Users/example/project")
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(p.at == f.date(from: "2026-01-01T10:00:01.250Z"))
}

@Test func userPromptOnlyFromRealPrompts() throws {
    let lines = try fixtureLines()
    #expect(ClaudeLogParser.parse(lines[0])?.userPrompt == "Fix the build")
    #expect(ClaudeLogParser.parse(lines[3])?.userPrompt == nil)
    #expect(ClaudeLogParser.parse(lines[4])?.userPrompt == nil)
    #expect(ClaudeLogParser.parse(lines[5]) != nil)
    let arr = #"{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}"#
    #expect(ClaudeLogParser.parse(arr)?.userPrompt == "hi")
}

@Test func malformedLineIsNil() {
    #expect(ClaudeLogParser.parse("{not json") == nil)
}

@Test func sessionIdsFromPath() {
    let u = "00000000-0000-4000-8000-0000000000aa"
    let a = ClaudeLogParser.sessionIds(path: "/h/.claude/projects/-Users-example-project/\(u).jsonl")
    #expect(a?.session == u && a?.parent == nil)
    let b = ClaudeLogParser.sessionIds(path: "/h/.claude/projects/-Users-example-project/\(u)/subagents/agent-1.jsonl")
    #expect(b?.session == "agent-1" && b?.parent == u)
    #expect(ClaudeLogParser.sessionIds(path: "/x/notes.txt") == nil)
}

@Test func splitterReturnsManyLinesInOrderAndKeepsFragment() {
    var s = LineSplitter()
    #expect(s.feed(Data("one\ntwo\nthree\nfo".utf8)) == ["one", "two", "three"])
    #expect(s.feed(Data("ur\n".utf8)) == ["four"])
}

@Test func splitterFeedEndingOnNewlineDoesNotReEmit() {
    var s = LineSplitter()
    #expect(s.feed(Data("a\nb\n".utf8)) == ["a", "b"])
    #expect(s.feed(Data("c\n".utf8)) == ["c"])
    #expect(s.feed(Data()) == [])
}

@Test func splitterKeepsMultibyteCharSplitAcrossFeeds() {
    var s = LineSplitter()
    let bytes = Array("é\n".utf8)  // 0xC3 0xA9 0x0A
    #expect(s.feed(Data(bytes[0..<1])) == [])
    #expect(s.feed(Data(bytes[1...])) == ["é"])
}
