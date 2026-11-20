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
    let b = g.allow(at: t0.addingTimeInterval(59))
    let c = g.allow(at: t0.addingTimeInterval(60))
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
