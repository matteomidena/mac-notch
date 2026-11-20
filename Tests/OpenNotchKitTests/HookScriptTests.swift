import Foundation
import Testing
@testable import OpenNotchKit

private struct Env {
    let home: URL
    let script: URL
    var dir: URL { home.appendingPathComponent("Library/Application Support/OpenNotch/directives") }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        script = root.appendingPathComponent("hook.sh")
        try Directive.hookScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func write(_ id: String, _ data: Data) throws {
        try data.write(to: dir.appendingPathComponent("\(id).json"))
    }

    func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).json").path)
    }

    func run(_ stdin: String) throws -> (out: Data, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (out, p.terminationStatus)
    }

    func input(_ id: String, extra: String = "") -> String {
        #"{"session_id":"\#(id)","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{\#(extra)}}"#
    }
}

@Test func noDirectivePrintsNothing() throws {
    let e = try Env()
    let r = try e.run(e.input("abc-1"))
    #expect(r.out.isEmpty && r.status == 0)
}

@Test func directivePrintedOnceThenDeleted() throws {
    let e = try Env()
    let stop = Directive.hookOutput(.stop)
    try e.write("abc-1", stop)
    let first = try e.run(e.input("abc-1"))
    #expect(first.out == stop && first.status == 0)
    let second = try e.run(e.input("abc-1"))
    #expect(second.out.isEmpty && second.status == 0)
}

@Test func hostileSessionIdIgnored() throws {
    let e = try Env()
    try e.write("etc", Directive.hookOutput(.stop))
    for id in ["../../etc/x", "", "a b"] {
        let r = try e.run(e.input(id))
        #expect(r.out.isEmpty && r.status == 0)
    }
}

@Test func staleDirectiveDropped() throws {
    let e = try Env()
    try e.write("abc-1", Directive.hookOutput(.stop))
    let path = e.dir.appendingPathComponent("abc-1.json").path
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-180)], ofItemAtPath: path)
    let r = try e.run(e.input("abc-1"))
    #expect(r.out.isEmpty && r.status == 0)
    #expect(!e.exists("abc-1"))
}

@Test func sessionIdInToolInputIgnored() throws {
    let e = try Env()
    try e.write("victim-2", Directive.hookOutput(.stop))
    let r = try e.run(e.input("abc-1", extra: #""session_id":"victim-2""#))
    #expect(r.out.isEmpty && r.status == 0)
    #expect(e.exists("victim-2"))

    let mine = Directive.hookOutput(.redirect("hi"))
    try e.write("abc-1", mine)
    let r2 = try e.run(e.input("abc-1", extra: #""session_id":"victim-2""#))
    #expect(r2.out == mine)
    #expect(e.exists("victim-2"))
}

@Test func runsUnder20ms() throws {
    let e = try Env()
    var times: [Double] = []
    for _ in 0..<20 {
        let t = Date()
        _ = try e.run(e.input("abc-1"))
        times.append(Date().timeIntervalSince(t))
    }
    #expect(times.sorted()[10] < 0.020)
}

@Test func hookOutputStopExactBytes() {
    #expect(String(decoding: Directive.hookOutput(.stop), as: UTF8.self)
            == #"{"continue":false,"stopReason":"Stopped from OpenNotch"}"#)
}

@Test func redirectIsValidJSONForAnyText() throws {
    let text = "say \"hi\"\nback\\slash"
    let obj = try JSONSerialization.jsonObject(with: Directive.hookOutput(.redirect(text))) as? [String: Any]
    let h = obj?["hookSpecificOutput"] as? [String: Any]
    #expect(h?["hookEventName"] as? String == "PreToolUse")
    #expect(h?["permissionDecision"] as? String == "deny")
    #expect(h?["permissionDecisionReason"] as? String == "The user redirected you: \(text)")
}

@Test func safeSessionIds() {
    #expect(Directive.isSafeSessionId("abc-1"))
    #expect(Directive.isSafeSessionId(String(repeating: "a", count: 64)))
    #expect(!Directive.isSafeSessionId(String(repeating: "a", count: 65)))
    #expect(!Directive.isSafeSessionId(""))
    #expect(!Directive.isSafeSessionId("../x"))
    #expect(!Directive.isSafeSessionId("a b"))
    #expect(!Directive.isSafeSessionId("abc\n"))
}
