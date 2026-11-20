import Testing
import Foundation
@testable import OpenNotchKit

@MainActor @Test func agentsPluginProvidesAgentsTab() {
    let tabs = AgentsPlugin(host: FakeHost()).tabs()
    #expect(tabs.map(\.id) == ["agents"])
    #expect(tabs.first?.title == "Agents")
    #expect(tabs.first?.systemImage == "sparkle")
}

@Test func multipleTextRoundsToOneDecimal() {
    #expect(multipleText(4.31) == "4.3×")
    #expect(multipleText(3) == "3.0×")
}

@Test func stripButtonsOnlyForControllableClaude() {
    #expect(stripActions(for: .claude, canControl: true) == [.redirect, .stop, .dismiss])
    #expect(stripActions(for: .codex, canControl: true) == [.dismiss])
    #expect(stripActions(for: .claude, canControl: false) == [.dismiss])
}

@Test func compactCountFormatsLikeTheMockup() {
    #expect(compactCount(41_000) == "41k")
    #expect(compactCount(1_200_000) == "1.2M")
    #expect(compactCount(950) == "950")
}
