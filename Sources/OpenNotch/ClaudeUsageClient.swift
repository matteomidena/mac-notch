import Foundation
import OpenNotchKit
import Security

/// Host-side IO for the Claude usage flow. The token lives only in these call frames: never logged, stored or written back.
enum ClaudeUsageClient {
    static let connectedKey = "cafe.notch.agents.claudeConnected"

    /// Blocks while the macOS prompt is up: call off the main actor only. Read-only.
    static func readCredential() -> ClaudeCredentialRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &out) {
        case errSecSuccess: return (out as? Data).map { .data($0) } ?? .notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: return .denied
        default: return .notFound
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
