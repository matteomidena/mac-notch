import Foundation
import OpenNotchKit

/// Host-side IO for the Claude usage flow. The token lives only in these call frames: never logged, stored or written back.
enum ClaudeUsageClient {
    static let connectedKey = "cafe.notch.agents.claudeConnected"

    /// Read-only, off the main actor. Goes through /usr/bin/security, not SecItemCopyMatching: Claude Code
    /// writes the item with that tool, so it is already on the item's ACL and macOS never prompts. A direct
    /// read prompted again after every Claude token refresh and every rebuild (ad-hoc signature changes).
    static func readCredential() -> ClaudeCredentialRead {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .notFound }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        switch p.terminationStatus {
        case 0: return .data(data)
        case 128: return .denied  // errSecUserCanceled surfaced by security(1)
        default: return .notFound // 44: no item
        }
    }

    static let service = "Claude Code-credentials"
    // Claude Code's own OAuth client and token endpoint (from its binary); renewals look like its own.
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Token-endpoint response body on 200, else nil. The tokens never leave this frame.
    static func renew(refreshToken: String, scopes: [String]) async -> Data? {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientId]
        if !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Writes the renewed credential back with security(1), as Claude Code does (`-U -a -s -X hex`), so the
    /// item keeps its ACL and Claude Code reads the new token. Argv, not `security -i`: the JSON is over its
    /// stdin line limit, and Claude Code falls back to argv for the same reason.
    static func save(_ json: Data) -> Bool {
        guard let account = account() else { return false }
        let hex = json.map { String(format: "%02x", $0) }.joined()
        return run(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex]).status == 0
    }

    private static func account() -> String? {
        let out = run(["find-generic-password", "-s", service])
        guard out.status == 0, let text = String(data: out.data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("\"acct\"<blob>=") }),
              let start = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: start)...].trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
        return String(value.dropFirst().dropLast())
    }

    private static func run(_ args: [String]) -> (status: Int32, data: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    static func fetch(token: String) async -> (status: Int, body: Data)? {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, body)
    }
}
