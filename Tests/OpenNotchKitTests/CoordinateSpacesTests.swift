import Testing
import CoreGraphics
@testable import OpenNotchKit

@Test func primaryScreenFrameMapsToOrigin() {
    // Primary screen 1728x1117 in AppKit is origin (0,0) size-identical in CG.
    let appKit = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 0, y: 0, width: 1728, height: 1117))
}

@Test func screenAbovePrimaryGetsNegativeCGY() {
    // External display sitting on top of the primary in AppKit space.
    let appKit = CGRect(x: 100, y: 1117, width: 2560, height: 1440)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 100, y: -1440, width: 2560, height: 1440))
}

@Test func windowInsidePrimaryFlipsY() {
    // A 800x600 window whose AppKit origin is y=100 on a 1117-tall primary:
    // its top edge is at appKit maxY=700 → CG y = 1117 - 700 = 417.
    let appKit = CGRect(x: 50, y: 100, width: 800, height: 600)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 50, y: 417, width: 800, height: 600))
}
