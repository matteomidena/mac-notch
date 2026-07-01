import Testing
import CoreGraphics
@testable import OpenNotchKit

@Test func notchPresentCentersOnTopInset() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let m = NotchGeometry.metrics(screenFrame: screen, topInset: 37,
                                  notchWidth: 200, fallbackPillSize: .init(width: 180, height: 32))
    #expect(m.hasNotch)
    #expect(m.anchorRect.width == 200)
    #expect(m.anchorRect.height == 37)
    #expect(m.anchorRect.midX == screen.midX)
    #expect(m.anchorRect.maxY == screen.maxY) // pinned to top
}

@Test func notchlessFallsBackToCenteredPill() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let m = NotchGeometry.metrics(screenFrame: screen, topInset: 0,
                                  notchWidth: 200, fallbackPillSize: .init(width: 180, height: 32))
    #expect(!m.hasNotch)
    #expect(m.anchorRect.size == CGSize(width: 180, height: 32))
    #expect(m.anchorRect.midX == screen.midX)
    #expect(m.anchorRect.maxY == screen.maxY)
}
