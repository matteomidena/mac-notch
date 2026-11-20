import Foundation

/// Adds/removes OpenNotch's PreToolUse hook in Claude's settings.json, leaving everything else alone.
public enum ClaudeSettingsPatch {
    public enum PatchError: Error, Equatable { case notAJSONObject }

    public static func install(into settings: Data?, command: String) throws -> Data {
        var root = try parse(settings)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        if !pre.contains(where: { isOurs($0, command) }) {
            pre.append(["matcher": "*", "hooks": [["type": "command", "command": command]]])
        }
        hooks["PreToolUse"] = pre
        root["hooks"] = hooks
        return try encode(root)
    }

    public static func remove(from settings: Data, command: String) throws -> Data {
        var root = try parse(settings)
        guard var hooks = root["hooks"] as? [String: Any],
              let pre = hooks["PreToolUse"] as? [[String: Any]] else { return try encode(root) }
        let kept: [[String: Any]] = pre.compactMap { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
            let rest = inner.filter { $0["type"] as? String != "command" || $0["command"] as? String != command }
            guard rest.count != inner.count else { return entry }
            if rest.isEmpty { return nil }
            var e = entry
            e["hooks"] = rest
            return e
        }
        hooks["PreToolUse"] = kept.isEmpty ? nil : kept
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return try encode(root)
    }

    public static func isInstalled(in settings: Data?, command: String) -> Bool {
        guard let root = try? parse(settings),
              let pre = (root["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] else { return false }
        return pre.contains { isOurs($0, command) }
    }

    private static func isOurs(_ entry: [String: Any], _ command: String) -> Bool {
        (entry["hooks"] as? [[String: Any]])?.contains {
            $0["type"] as? String == "command" && $0["command"] as? String == command
        } ?? false
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PatchError.notAJSONObject }
        return o
    }

    private static func encode(_ o: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
