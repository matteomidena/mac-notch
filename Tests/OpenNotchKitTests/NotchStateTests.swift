import Testing
@testable import OpenNotchKit

@Test func hoverExpandsAndCollapses() {
    var m = NotchStateMachine()
    #expect(m.handle(.hoverIn) == .expanded)
    #expect(m.handle(.hoverOut) == .collapsed)
}

@Test func fullscreenHidesAndSwallowsHover() {
    var m = NotchStateMachine()
    #expect(m.handle(.enterFullscreen) == .hidden)
    #expect(m.handle(.hoverIn) == .hidden)      // swallowed
    #expect(m.handle(.exitFullscreen) == .collapsed)
    #expect(m.handle(.hoverIn) == .expanded)
}
