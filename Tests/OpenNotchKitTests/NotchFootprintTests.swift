import Testing
import CoreGraphics
@testable import OpenNotchKit

private let notch = CGSize(width: 200, height: 32)
private let ambient = CGSize(width: 300, height: 32)
private let expanded = CGSize(width: 500, height: 124)
private let alert = CGSize(width: 360, height: 64)

@Test func collapsedIsNotchOrAmbient() {
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: false,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded, alertSize: alert) == notch)
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded, alertSize: alert) == ambient)
}

@Test func expandedAndPinnedUseExpandedSize() {
    for phase in [NotchPhase.expanded, .pinned] {
        #expect(NotchFootprint.size(phase: phase, showAmbient: true,
                                    notchSize: notch, ambientSize: ambient, expandedSize: expanded, alertSize: alert) == expanded)
    }
}

@Test func hiddenKeepsNotchSize() {
    #expect(NotchFootprint.size(phase: .hidden, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded, alertSize: alert) == notch)
}

@Test func hitRectIsTopCentered() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 184)
    let fp = CGSize(width: 500, height: 124)
    // Non-flipped (AppKit default): top = maxY.
    #expect(NotchFootprint.hitRect(footprint: fp, bounds: bounds, flipped: false)
            == CGRect(x: 50, y: 60, width: 500, height: 124))
    // Flipped: top = minY.
    #expect(NotchFootprint.hitRect(footprint: fp, bounds: bounds, flipped: true)
            == CGRect(x: 50, y: 0, width: 500, height: 124))
}

@Test func alertUsesAlertSize() {
    #expect(NotchFootprint.size(phase: .alert, showAmbient: true,
                                notchSize: notch, ambientSize: ambient,
                                expandedSize: expanded, alertSize: alert) == alert)
}
