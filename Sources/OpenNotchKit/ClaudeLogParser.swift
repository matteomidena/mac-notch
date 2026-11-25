import Foundation

public enum TokenReport: Equatable, Sendable {
    case delta(TokenCounts, messageId: String?)
    case cumulative(TokenCounts)
}

public struct ParsedLogLine: Equatable, Sendable {
    public var at: Date?
    public var tokens: TokenReport?
    public var cwd: String?
    public var userPrompt: String?
    public var threadId: String?
    public var parentThreadId: String?
    public var limits: PlanLimits?   // Codex only
    public var state: SessionState?  // what this line says the session is doing now
    public var detail: String?       // e.g. "Editing Foo.swift", "npm test"
    public var title: String?        // Claude session name (custom-title / agent-name)
    public var turnEnded = false     // the agent stopped and handed the turn back
    public var backgroundStarted: String?   // id of a task launched in the background
    public var backgroundEnded: [String] = []

    public init(at: Date? = nil, tokens: TokenReport? = nil, cwd: String? = nil, userPrompt: String? = nil,
                threadId: String? = nil, parentThreadId: String? = nil, limits: PlanLimits? = nil,
                state: SessionState? = nil, detail: String? = nil, title: String? = nil) {
        self.at = at; self.tokens = tokens; self.cwd = cwd; self.userPrompt = userPrompt
        self.threadId = threadId; self.parentThreadId = parentThreadId; self.limits = limits
        self.state = state; self.detail = detail; self.title = title
    }
}

/// ISO-8601 with fractional seconds, as both agents write timestamps.
// ISO8601DateFormatter is thread-safe; it just isn't marked Sendable.
nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseISODate(_ s: String) -> Date? { isoFormatter.date(from: s) }

public enum ClaudeLogParser {
    /// nil only when the line is not a JSON object.
    public static func parse(_ line: String) -> ParsedLogLine? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        var out = ParsedLogLine()
        if let ts = obj["timestamp"] as? String {
            out.at = parseISODate(ts)
        }
        out.cwd = obj["cwd"] as? String
        let message = obj["message"] as? [String: Any]
        let type = obj["type"] as? String

        if type == "assistant", let usage = message?["usage"] as? [String: Any] {
            out.tokens = .delta(TokenCounts(input: usage["input_tokens"] as? Int ?? 0,
                                            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                                            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                                            output: usage["output_tokens"] as? Int ?? 0),
                                messageId: message?["id"] as? String)
        }
        if let t = (obj["customTitle"] ?? obj["agentName"]) as? String, !t.isEmpty { out.title = t }
        if type == "assistant", let blocks = message?["content"] as? [[String: Any]] {
            if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }) {
                let name = tool["name"] as? String ?? ""
                let input = tool["input"] as? [String: Any] ?? [:]
                if ClaudeLogParser.asksUser.contains(name) {
                    out.state = .needsYou; out.detail = name == "ExitPlanMode" ? "Plan ready" : "Asking a question"
                } else if name == "mcp__ccd_turn__wrap_up", let ask = input["ask"] as? String, !ask.isEmpty {
                    out.state = .needsYou; out.detail = ask  // the desktop app's next-step question
                } else {
                    if name == "KillShell" || name == "TaskStop",
                       let id = (input["shell_id"] ?? input["task_id"]) as? String { out.backgroundEnded = [id] }
                    out.state = .working; out.detail = toolDetail(name, input)
                }
            } else if message?["stop_reason"] as? String == "end_turn" {
                // A finished turn waits on you only if it ends on a question; otherwise it's done.
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                out.turnEnded = true
                out.state = endsWithQuestion(text) ? .needsYou : .idle
            } else {
                out.state = .working
            }
        }
        if type == "user", obj["isMeta"] as? Bool != true {
            if let s = message?["content"] as? String {
                out.userPrompt = s
            } else if let blocks = message?["content"] as? [[String: Any]],
                      !blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                out.userPrompt = texts.isEmpty ? nil : texts.joined(separator: "\n")
            }
        }
        if type == "user", let blocks = message?["content"] as? [[String: Any]] {
            for b in blocks where b["type"] as? String == "tool_result" {
                let text = (b["content"] as? String)
                    ?? (b["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
                if let r = text.range(of: #"running in background with ID: (\w+)"#, options: .regularExpression) {
                    out.backgroundStarted = String(text[r].split(separator: " ").last ?? "")
                }
            }
        }
        // A background task's completion notice, queued for the agent or delivered as a prompt.
        if let raw = (obj["content"] as? String) ?? out.userPrompt, raw.contains("<task-id>") {
            out.backgroundEnded += taskIds(raw)
        }
        if type == "user", obj["isMeta"] as? Bool != true, message != nil {
            let interrupted = out.userPrompt?.hasPrefix("[Request interrupted") ?? false
            // You interrupted it, so you're already there: nothing waits on you.
            out.state = interrupted ? .idle : .working
            if out.userPrompt != nil && !interrupted { out.detail = "Thinking" }
        }
        return out
    }

    static func endsWithQuestion(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }

    static func taskIds(_ s: String) -> [String] {
        s.components(separatedBy: "<task-id>").dropFirst().compactMap { $0.components(separatedBy: "</task-id>").first }
    }

    /// Tools that stop the turn until the user answers.
    static let asksUser: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    static func toolDetail(_ name: String, _ input: [String: Any]) -> String {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        switch name {
        case "Bash": return (input["description"] as? String) ?? (input["command"] as? String).map { String($0.prefix(60)) } ?? "Running a command"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing " + (file ?? "files")
        case "Read": return "Reading " + (file ?? "files")
        case "Grep", "Glob": return "Searching"
        case "Task", "Agent": return "Running a subagent"
        case "WebFetch", "WebSearch": return "Browsing the web"
        default:
            // mcp__server__tool → "tool"
            return name.hasPrefix("mcp__") ? (name.components(separatedBy: "__").last ?? name) : name
        }
    }

    /// `…/<enc-cwd>/<uuid>.jsonl` → (uuid, nil); `…/<enc-cwd>/<uuid>/subagents/<name>.jsonl` → (name, uuid); else nil
    public static func sessionIds(path: String) -> (session: String, parent: String?)? {
        let parts = path.split(separator: "/").map(String.init)
        guard let file = parts.last, file.hasSuffix(".jsonl") else { return nil }
        let stem = String(file.dropLast(".jsonl".count))
        if parts.count >= 4, parts[parts.count - 2] == "subagents", UUID(uuidString: parts[parts.count - 3]) != nil {
            return (stem, parts[parts.count - 3])
        }
        if parts.count >= 2, UUID(uuidString: stem) != nil { return (stem, nil) }
        return nil
    }
}
