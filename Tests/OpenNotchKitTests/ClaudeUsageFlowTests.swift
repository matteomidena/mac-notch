import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let usageBody = Data(#"{"five_hour":{"utilization":16,"resets_at":null},"seven_day":{"utilization":9,"resets_at":null}}"#.utf8)

private func cred(expiresMs: Double) -> Data {
    Data(#"{"claudeAiOauth":{"accessToken":"placeholder-token","expiresAt":\#(expiresMs)}}"#.utf8)
}
private let fresh = cred(expiresMs: (1_800_000_000 + 3600) * 1000)

@Test func gateCountsAttempts() {
    var g = ClaudeFetchGate()
    let a = g.allow(at: t0)
    let b = g.allow(at: t0.addingTimeInterval(14))
    let c = g.allow(at: t0.addingTimeInterval(15))
    #expect(a && !b && c)
}

@Test func flowReturnsSnapshotOn200() async {
    let out = await ClaudeUsageFlow.run(at: t0, read: { .data(fresh) }, fetch: { _ in (200, usageBody) })
    guard case .snapshot(let l) = out else { Issue.record("no snapshot"); return }
    #expect(l.windows.map(\.label) == ["5h", "Weekly"])
}

@Test func flowNon200IsNone() async {
    for status in [401, 403, 500] {
        let out = await ClaudeUsageFlow.run(at: t0, read: { .data(fresh) }, fetch: { _ in (status, usageBody) })
        #expect(out == .none)
    }
    #expect(await ClaudeUsageFlow.run(at: t0, read: { .data(fresh) }, fetch: { _ in nil }) == .none)
}

@Test func flowExpiredTokenMakesNoRequest() async {
    let expired = cred(expiresMs: (1_800_000_000 - 1) * 1000)
    let out = await ClaudeUsageFlow.run(at: t0, read: { .data(expired) }, fetch: { _ in
        Issue.record("fetched with an expired token"); return (200, usageBody)
    })
    #expect(out == .none)
}

@Test func flowKeychainStatuses() async {
    let fetch: @Sendable (String) async -> (status: Int, body: Data)? = { _ in Issue.record("fetched"); return nil }
    #expect(await ClaudeUsageFlow.run(at: t0, read: { .denied }, fetch: fetch) == .denied)
    #expect(await ClaudeUsageFlow.run(at: t0, read: { .notFound }, fetch: fetch) == .none)
    #expect(await ClaudeUsageFlow.run(at: t0, read: { .data(Data()) }, fetch: fetch) == .none)
}

@Test func ageTextAppearsAfterThreeMinutes() {
    #expect(limitAgeText(fetchedAt: t0, now: t0.addingTimeInterval(179)) == nil)
    #expect(limitAgeText(fetchedAt: t0, now: t0.addingTimeInterval(300)) == "5 min ago")
}

@Test func flowRenewsExpiredTokenSavesAndFetchesWithNewOne() async {
    let expired = Data(#"{"mcpOAuth":{"x":1},"claudeAiOauth":{"accessToken":"old","refreshToken":"r1","expiresAt":\#((1_800_000_000 - 1) * 1000.0),"scopes":["user:profile"]}}"#.utf8)
    let saved = LockedBox<Data?>(nil)
    let out = await ClaudeUsageFlow.run(
        at: t0, read: { .data(expired) },
        fetch: { token in token == "new" ? (200, usageBody) : (401, Data()) },
        renew: { refresh, scopes in
            #expect(refresh == "r1" && scopes == ["user:profile"])
            return Data(#"{"access_token":"new","refresh_token":"r2","expires_in":3600}"#.utf8)
        },
        save: { saved.value = $0; return true })
    guard case .snapshot = out else { Issue.record("no snapshot"); return }
    let root = try? JSONSerialization.jsonObject(with: saved.value ?? Data()) as? [String: Any]
    let oauth = root?["claudeAiOauth"] as? [String: Any]
    #expect(oauth?["accessToken"] as? String == "new" && oauth?["refreshToken"] as? String == "r2")
    #expect((oauth?["expiresAt"] as? NSNumber)?.doubleValue == 1_800_003_600_000.0)
    #expect(oauth?["scopes"] as? [String] == ["user:profile"] && root?["mcpOAuth"] != nil)
}

@Test func flowFailedRenewalKeepsSnapshotAndSavesNothing() async {
    let expired = Data(#"{"claudeAiOauth":{"accessToken":"old","refreshToken":"r1","expiresAt":1}}"#.utf8)
    let out = await ClaudeUsageFlow.run(at: t0, read: { .data(expired) }, fetch: { _ in (200, usageBody) },
                                        renew: { _, _ in nil }, save: { _ in Issue.record("saved"); return true })
    #expect(out == .none)
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.withLock { v } } set { lock.withLock { v = newValue } } }
}
