import Foundation

public enum CodexLogParser {
    /// nil only when the line is not a JSON object.
    public static func parse(_ line: String) -> ParsedLogLine? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        var out = ParsedLogLine()
        let at = (obj["timestamp"] as? String).flatMap(parseISODate)
        out.at = at
        let payload = obj["payload"] as? [String: Any] ?? [:]
        let ptype = payload["type"] as? String

        switch obj["type"] as? String {
        case "session_meta":
            out.threadId = payload["id"] as? String
            out.parentThreadId = payload["parent_thread_id"] as? String
            out.cwd = payload["cwd"] as? String
        case "event_msg":
            if ptype == "token_count" {
                if let usage = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any] {
                    let input = usage["input_tokens"] as? Int ?? 0
                    let cached = usage["cached_input_tokens"] as? Int ?? 0
                    out.tokens = .cumulative(TokenCounts(input: input - cached, cacheRead: cached,
                                                         output: usage["output_tokens"] as? Int ?? 0))
                }
                if let rl = payload["rate_limits"] as? [String: Any] {
                    let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
                        guard let w = rl[key] as? [String: Any],
                              let pct = (w["used_percent"] as? NSNumber)?.doubleValue,
                              let mins = w["window_minutes"] as? Int,
                              let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
                        return LimitWindow(label: windowLabel(minutes: mins), usedPercent: pct,
                                           resetsAt: Date(timeIntervalSince1970: reset))
                    }
                    out.limits = PlanLimits(agent: .codex, windows: windows,
                                            fetchedAt: at ?? Date())
                }
            } else if ptype == "user_message" {
                out.userPrompt = payload["message"] as? String
                out.state = .working; out.detail = "Thinking"
            } else if ptype == "task_started" {
                out.state = .working
            } else if ptype == "task_complete" {
                out.turnEnded = true
                out.state = ClaudeLogParser.endsWithQuestion(payload["last_agent_message"] as? String ?? "") ? .needsYou : .idle
            } else if ptype == "turn_aborted" {
                out.state = .idle  // you stopped it
            }
        case "response_item":
            if ptype == "function_call" || ptype == "custom_tool_call" || ptype == "local_shell_call" {
                out.state = .working
                out.detail = codexDetail(payload)
            } else if ptype == "message", payload["role"] as? String == "user",
               let blocks = payload["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { $0["type"] as? String == "input_text" ? $0["text"] as? String : nil }
                let joined = texts.joined(separator: "\n")
                if !texts.isEmpty, !joined.hasPrefix("<") { out.userPrompt = joined }
            }
        default: break
        }
        return out
    }

    static func codexDetail(_ p: [String: Any]) -> String {
        let name = p["name"] as? String ?? ""
        if name == "apply_patch" { return "Editing files" }
        let args = (p["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            ?? (p["action"] as? [String: Any]) ?? [:]
        let cmd = (args["cmd"] ?? args["command"]).flatMap { v -> String? in
            if let s = v as? String { return s }
            if let a = v as? [String] { return (a.first == "bash" || a.first == "zsh") ? a.last : a.joined(separator: " ") }
            return nil
        }
        return cmd.map { String($0.prefix(60)) } ?? (name.isEmpty ? "Working" : name)
    }
}
