import Foundation
import Testing
@testable import OpenNotchKit

private let C = "sh \"/Users/x/Library/Application Support/OpenNotch/hook.sh\""

private func obj(_ d: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any])
}
private func ours() -> [String: Any] {
    ["matcher": "*", "hooks": [["type": "command", "command": C]]]
}
private func same(_ a: Any, _ b: Any) -> Bool {
    (a as? NSObject)?.isEqual(b as? NSObject) ?? false
}

@Test func installIntoMissingFile() throws {
    let o = try obj(ClaudeSettingsPatch.install(into: nil, command: C))
    #expect(same(o, ["hooks": ["PreToolUse": [ours()]]]))
}

private let existing = #"""
{"statusLine":{"type":"command","command":"x"},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"b"}]}],
          "PostToolUse":[{"hooks":[{"type":"command","command":"p"}]}]}}
"""#

@Test func installKeepsEverythingElse() throws {
    let o = try obj(ClaudeSettingsPatch.install(into: Data(existing.utf8), command: C))
    #expect(o["statusLine"] != nil)
    let hooks = try #require(o["hooks"] as? [String: Any])
    #expect((hooks["PostToolUse"] as? [Any])?.count == 1)
    let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(pre.count == 2)
    #expect(pre[0]["matcher"] as? String == "Bash")
    #expect(same(pre[1], ours()))
}

@Test func installIsIdempotent() throws {
    let once = try ClaudeSettingsPatch.install(into: nil, command: C)
    let twice = try ClaudeSettingsPatch.install(into: once, command: C)
    let pre = try #require((try obj(twice)["hooks"] as? [String: Any])?["PreToolUse"] as? [Any])
    #expect(pre.count == 1)
}

@Test func removeOnlyOurs() throws {
    let installed = try ClaudeSettingsPatch.install(into: Data(existing.utf8), command: C)
    #expect(ClaudeSettingsPatch.isInstalled(in: installed, command: C))
    let o = try obj(ClaudeSettingsPatch.remove(from: installed, command: C))
    #expect(!ClaudeSettingsPatch.isInstalled(in: try ClaudeSettingsPatch.remove(from: installed, command: C), command: C))
    let hooks = try #require(o["hooks"] as? [String: Any])
    #expect((hooks["PreToolUse"] as? [[String: Any]])?.count == 1)
    #expect((hooks["PostToolUse"] as? [Any])?.count == 1)
    #expect(o["statusLine"] != nil)
}

@Test func removePrunesEmptyContainers() throws {
    let installed = try ClaudeSettingsPatch.install(into: Data(#"{"model":"x"}"#.utf8), command: C)
    let o = try obj(ClaudeSettingsPatch.remove(from: installed, command: C))
    #expect(same(o, ["model": "x"]))
}

@Test func removeKeepsEntryWithOtherHooks() throws {
    let s = #"{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"other"},{"type":"command","command":"\#(C.replacingOccurrences(of: "\"", with: "\\\""))"}]}]}}"#
    let o = try obj(ClaudeSettingsPatch.remove(from: Data(s.utf8), command: C))
    let pre = try #require((o["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
    #expect((pre[0]["hooks"] as? [Any])?.count == 1)
}

@Test func isInstalledFalseForNilOrGarbage() {
    #expect(!ClaudeSettingsPatch.isInstalled(in: nil, command: C))
    #expect(!ClaudeSettingsPatch.isInstalled(in: Data("nope".utf8), command: C))
}

@Test func invalidJSONThrows() {
    #expect(throws: ClaudeSettingsPatch.PatchError.notAJSONObject) {
        try ClaudeSettingsPatch.install(into: Data("not json".utf8), command: C)
    }
    #expect(throws: ClaudeSettingsPatch.PatchError.notAJSONObject) {
        try ClaudeSettingsPatch.install(into: Data("[]".utf8), command: C)
    }
}

@Test func installRefusesUnexpectedShapes() {
    for s in [#"{"hooks":[]}"#,
              #"{"hooks":{"PreToolUse":{}}}"#,
              #"{"hooks":{"PreToolUse":[{"matcher":"Bash"},"x"]}}"#] {
        #expect(throws: ClaudeSettingsPatch.PatchError.unexpectedShape) {
            try ClaudeSettingsPatch.install(into: Data(s.utf8), command: C)
        }
    }
}

@Test func installTreatsNullAsEmpty() throws {
    let o = try obj(ClaudeSettingsPatch.install(into: Data(#"{"hooks":{"PreToolUse":null}}"#.utf8), command: C))
    #expect(same(o, ["hooks": ["PreToolUse": [ours()]]]))
}
