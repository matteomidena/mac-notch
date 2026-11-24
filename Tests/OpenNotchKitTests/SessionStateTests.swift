import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func claude(_ json: String) -> ParsedLogLine { ClaudeLogParser.parse(json)! }

@Test func claudeLinesMapToState() {
    let ts = #""timestamp":"2023-11-14T22:13:20.000Z""#
    let edit = claude(#"{"type":"assistant",\#(ts),"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/Checkout.ts"}}]}}"#)
    #expect(edit.state == .working && edit.detail == "Editing Checkout.ts")
    let done = claude(#"{"type":"assistant",\#(ts),"message":{"stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}"#)
    #expect(done.state == .needsYou)
    let ask = claude(#"{"type":"assistant",\#(ts),"message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{}}]}}"#)
    #expect(ask.state == .needsYou)
    let prompt = claude(#"{"type":"user",\#(ts),"message":{"content":"fix it"}}"#)
    #expect(prompt.state == .working)
    #expect(claude(#"{"type":"custom-title","customTitle":"Fix checkout"}"#).title == "Fix checkout")
}

@Test func codexTaskCompleteNeedsYou() {
    let l = CodexLogParser.parse(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#)!
    #expect(l.state == .needsYou)
}

@MainActor @Test func subagentFinishingDoesNotFlipParent() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(at: t0, state: .working, detail: "Running a subagent"), agent: .claude, fileKey: "main", pathIds: ("P", nil))
    s.ingest(ParsedLogLine(at: t0.addingTimeInterval(5), state: .needsYou), agent: .claude, fileKey: "sub", pathIds: ("a", "P"))
    #expect(s.sessions["P"]?.state == .working)
    s.ingest(ParsedLogLine(at: t0.addingTimeInterval(9), state: .needsYou), agent: .claude, fileKey: "main", pathIds: ("P", nil))
    #expect(s.sessions["P"]?.needsYou == true)
}

@MainActor @Test func waitingSessionsStayListedThenDrop() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(at: t0, state: .needsYou), agent: .claude, fileKey: "w", pathIds: ("W", nil))
    s.ingest(ParsedLogLine(at: t0, state: .working), agent: .claude, fileKey: "r", pathIds: ("R", nil))
    #expect(s.live(at: t0.addingTimeInterval(600)).map(\.id) == ["W"])  // R went quiet, W still waits
    #expect(s.live(at: t0.addingTimeInterval(AgentSession.waitingTTL + 1)).isEmpty)
}

@MainActor @Test func titleLineBeforeSessionIsKept() {
    let s = AgentSessions()
    s.ingest(ParsedLogLine(title: "Fix checkout"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    s.ingest(ParsedLogLine(at: t0, userPrompt: "do it"), agent: .claude, fileKey: "f", pathIds: ("S", nil))
    #expect(s.sessions["S"]?.displayTitle == "Fix checkout")
}
