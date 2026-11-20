import Testing
import Foundation
@testable import OpenNotchKit

@Test func agentsPanelHeightHasMinimumOf300() {
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 0) == 300)
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 2) == 300)
}

@Test func agentsPanelHeightGrows32PerRowPastMinimum() {
    let at = AgentsLayout.panelHeight(limitRows: 3, sessionRows: 6)
    #expect(at > 300)
    #expect(AgentsLayout.panelHeight(limitRows: 3, sessionRows: 7) == at + 32)
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
