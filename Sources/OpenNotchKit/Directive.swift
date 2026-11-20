import Foundation

public enum DirectiveAction: Equatable, Sendable { case stop, redirect(String) }

/// One-shot Stop/Redirect directives, delivered to Claude Code through a PreToolUse hook.
public enum Directive {
    public static func hookOutput(_ action: DirectiveAction) -> Data {
        let obj: [String: Any]
        switch action {
        case .stop:
            obj = ["continue": false, "stopReason": "Stopped from OpenNotch"]
        case .redirect(let text):
            obj = ["hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "The user redirected you: \(text)",
            ]]
        }
        // Escaping is JSONSerialization's job; sorted keys keep the stop bytes stable.
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    /// `^[A-Za-z0-9-]{1,64}$`, checked on scalars (a regex `$` would accept a trailing newline).
    public static func isSafeSessionId(_ id: String) -> Bool {
        let u = id.unicodeScalars
        return (1...64).contains(u.count) && u.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x61 && $0.value <= 0x7A) || $0 == "-"
        }
    }

    public static let hookScript = #"""
    #!/bin/sh
    # OpenNotch PreToolUse hook. Fails open: on any problem it exits 0 and the tool runs.
    dir="$HOME/Library/Application Support/OpenNotch/directives"
    id=$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    case "$id" in ""|*[!A-Za-z0-9-]*) exit 0 ;; esac
    f="$dir/$id.json"
    [ -f "$f" ] || exit 0
    # A directive older than 2 minutes is stale (the session went quiet): drop it.
    [ -n "$(find "$f" -mmin -2 2>/dev/null)" ] || { rm -f "$f"; exit 0; }
    cat "$f" 2>/dev/null
    rm -f "$f"
    exit 0

    """#
}
