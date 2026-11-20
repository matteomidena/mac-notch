import Testing
import Foundation
@testable import OpenNotchKit

private func usageFixture() throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/claude-usage", withExtension: "json") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func decodesFiveHourAndWeekly() throws {
    let limits = try #require(ClaudeUsageDecoder.decode(try usageFixture(), at: t0))
    #expect(limits.agent == .claude)
    #expect(limits.hasCredits == nil)
    #expect(limits.fetchedAt == t0)
    #expect(limits.windows.map(\.label) == ["5h", "Weekly"])
    #expect(limits.windows.map(\.usedPercent) == [16, 9])
    // 2026-11-02T18:30:00Z and 2026-11-06T19:00:00Z, fractional part is 0.18s
    let five = try #require(limits.windows[0].resetsAt)
    let week = try #require(limits.windows[1].resetsAt)
    #expect(abs(five.timeIntervalSince1970 - 1_793_644_200.181910) < 0.001)
    #expect(abs(week.timeIntervalSince1970 - 1_793_991_600.181929) < 0.001)
}

@Test func nullWindowsSkipped() throws {
    let limits = try #require(ClaudeUsageDecoder.decode(try usageFixture(), at: t0))
    #expect(limits.windows.count == 2)
}

@Test func missingFiveHourWindow() throws {
    let json = #"{"five_hour": null, "seven_day": {"utilization": 9.5, "resets_at": "2026-11-06T19:00:00.181929+00:00"}}"#
    let limits = try #require(ClaudeUsageDecoder.decode(Data(json.utf8), at: t0))
    #expect(limits.windows.map(\.label) == ["Weekly"])
    #expect(limits.windows[0].usedPercent == 9.5)
}

@Test func garbageIsNil() {
    #expect(ClaudeUsageDecoder.decode(Data("x".utf8), at: t0) == nil)
}

@Test func errorBodyIsNil() {
    let body = #"{"type":"error","error":{"type":"authentication_error","message":"x-api-key header is required"}}"#
    #expect(ClaudeUsageDecoder.decode(Data(body.utf8), at: t0) == nil)
}

@Test func credentialParsesAndExpires() throws {
    let ms = Int((t0.timeIntervalSince1970 + 3600) * 1000)
    let json = #"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":\#(ms)}}"#
    let cred = try #require(ClaudeCredential.parse(keychainJSON: Data(json.utf8)))
    #expect(cred.accessToken == "test-token")
    #expect(!cred.isExpired(at: t0))
    #expect(cred.isExpired(at: t0.addingTimeInterval(3601)))
}

@Test func credentialRejectsEmptyTokenAndEndedLogin() {
    let empty = #"{"claudeAiOauth":{"accessToken":"","expiresAt":0}}"#
    let ended = #"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":1800000000000,"loginEnded":"time_limit"}}"#
    #expect(ClaudeCredential.parse(keychainJSON: Data(empty.utf8)) == nil)
    #expect(ClaudeCredential.parse(keychainJSON: Data(ended.utf8)) == nil)
}
