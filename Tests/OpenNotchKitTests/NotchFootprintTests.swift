import Testing
import CoreGraphics
@testable import OpenNotchKit

private let notch = CGSize(width: 200, height: 32)
private let ambient = CGSize(width: 300, height: 32)
private let expanded = CGSize(width: 500, height: 124)

@Test func collapsedIsNotchOrAmbient() {
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: false,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == notch)
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == ambient)
}

@Test func expandedAndPinnedUseExpandedSize() {
    for phase in [NotchPhase.expanded, .pinned] {
        #expect(NotchFootprint.size(phase: phase, showAmbient: true,
                                    notchSize: notch, ambientSize: ambient, expandedSize: expanded) == expanded)
    }
}

@Test func hiddenKeepsNotchSize() {
    #expect(NotchFootprint.size(phase: .hidden, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == notch)
}

@Test func interactiveExcludesMenubarFlanksWhenOpen() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 184)
    let fp = CGSize(width: 500, height: 124)   // expanded; rect = (50, 0, 500, 124)
    func inside(_ x: CGFloat, _ y: CGFloat, clear: Bool) -> Bool {
        NotchFootprint.interactiveContains(CGPoint(x: x, y: y), footprint: fp, bounds: bounds,
                                           flipped: true, neckWidth: 200, menuBarHeight: 32,
                                           clearMenuBar: clear)
    }
    // Menubar strip, off to the side of the notch → passes through when open.
    #expect(inside(70, 10, clear: true) == false)
    // Menubar strip, over the notch neck → interactive.
    #expect(inside(300, 10, clear: true) == true)
    // Below the menubar → full width interactive.
    #expect(inside(70, 50, clear: true) == true)
    // Outside the footprint entirely.
    #expect(inside(10, 10, clear: true) == false)
    // When not open (collapsed/ambient), the whole footprint is interactive.
    #expect(inside(70, 10, clear: false) == true)
}

@Test func interactiveNonFlippedMenubarIsAtMaxY() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 184)
    let fp = CGSize(width: 500, height: 124)   // non-flipped rect = (50, 60, 500, 124)
    func inside(_ x: CGFloat, _ y: CGFloat) -> Bool {
        NotchFootprint.interactiveContains(CGPoint(x: x, y: y), footprint: fp, bounds: bounds,
                                           flipped: false, neckWidth: 200, menuBarHeight: 32,
                                           clearMenuBar: true)
    }
    // Top strip is near maxY (184) when non-flipped: a side point there passes through.
    #expect(inside(70, 180) == false)
    // Over the neck near the top → interactive.
    #expect(inside(300, 180) == true)
    // Deeper into the body (lower y) → full width.
    #expect(inside(70, 100) == true)
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
