import Testing
import Foundation
@testable import OpenNotchKit

@Test func agentsPanelHeightHasMinimumOf300() {
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 0) == 300)
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 1) == 300)
}

@Test func agentsPanelHeightGrowsOneSessionRowPastMinimum() {
    let at = AgentsLayout.panelHeight(limitRows: 3, sessionRows: 3)
    #expect(at > 300)
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 4) == at + AgentsLayout.sessionRowHeight)
}

@Test func agentsPanelHeightCapsAt480() {
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 40) == 480)
}

@Test func agentsPanelHeightNeverDecreasesWithMoreRows() {
    var last: CGFloat = 0
    for n in 0...30 {
        let h = AgentsLayout.panelHeight(limitRows: 3, sessionRows: n)
        #expect(h >= last)
        last = h
    }
}

@MainActor @Test func waitingBadgeYieldsToUsageEveryTenSeconds() {
    let slot = { AgentsFigure.usageSlot(at: $0, agents: 2) }
    #expect(slot(0) == nil && slot(9.9) == nil)       // 10 s of badge
    #expect(slot(10) == 0 && slot(12.9) == 0)         // Claude for 3 s
    #expect(slot(13) == 1 && slot(15.9) == 1)         // Codex for 3 s
    #expect(slot(16) == nil)                          // cycle restarts
    #expect(AgentsFigure.usageSlot(at: 12, agents: 0) == nil)
}

@Test func batterySaverDecision() {
    let auto = BatterySaverMode.automatic
    #expect(auto.isActive(onBattery: true, percent: 19, lowPowerMode: false))
    #expect(!auto.isActive(onBattery: true, percent: 20, lowPowerMode: false))
    #expect(!auto.isActive(onBattery: false, percent: 5, lowPowerMode: false))   // charging
    #expect(auto.isActive(onBattery: false, percent: 80, lowPowerMode: true))    // macOS Low Power Mode
    #expect(!auto.isActive(onBattery: true, percent: nil, lowPowerMode: false))  // no battery
    #expect(BatterySaverMode.always.isActive(onBattery: false, percent: 100, lowPowerMode: false))
    #expect(!BatterySaverMode.off.isActive(onBattery: true, percent: 3, lowPowerMode: true))
}
