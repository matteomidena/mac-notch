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
                if ClaudeLogParser.asksUser.contains(name) {
                    out.state = .needsYou; out.detail = name == "ExitPlanMode" ? "Plan ready" : "Asking a question"
                } else {
                    out.state = .working; out.detail = toolDetail(name, tool["input"] as? [String: Any] ?? [:])
                }
            } else if message?["stop_reason"] as? String == "end_turn" {
                out.state = .needsYou
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
        if type == "user", obj["isMeta"] as? Bool != true, message != nil {
            let interrupted = out.userPrompt?.hasPrefix("[Request interrupted") ?? false
            out.state = interrupted ? .needsYou : .working
            if out.userPrompt != nil && !interrupted { out.detail = "Thinking" }
        }
        return out
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
