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
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
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
