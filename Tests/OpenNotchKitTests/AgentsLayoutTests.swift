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
