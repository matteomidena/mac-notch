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

@Test func clickPinsFromCollapsedAndExpanded() {
    var sm = NotchStateMachine(phase: .collapsed)
    #expect(sm.handle(.click) == .pinned)
    sm = NotchStateMachine(phase: .expanded)
    #expect(sm.handle(.click) == .pinned)
}

@Test func pinnedIgnoresHoverOutAndClick() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.hoverOut) == .pinned)
    #expect(sm.handle(.click) == .pinned)
    #expect(sm.handle(.hoverIn) == .pinned)
}

@Test func clickOutsideAndEscapeCollapse() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.clickOutside) == .collapsed)
    sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.escape) == .collapsed)
    sm = NotchStateMachine(phase: .expanded)
    #expect(sm.handle(.escape) == .collapsed)
}

@Test func clickIgnoredWhenHidden() {
    var sm = NotchStateMachine(phase: .hidden)
    #expect(sm.handle(.click) == .hidden)
}

@Test func dragInExpandsDragOutCollapses() {
    var sm = NotchStateMachine(phase: .collapsed)
    #expect(sm.handle(.dragIn) == .expanded)
    #expect(sm.handle(.dragOut) == .collapsed)
}

@Test func dragIgnoredWhenHiddenOrPinned() {
    var sm = NotchStateMachine(phase: .hidden)
    #expect(sm.handle(.dragIn) == .hidden)
    sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.dragOut) == .pinned)
}

@Test func fullscreenHidesPinned() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.enterFullscreen) == .hidden)
    #expect(sm.handle(.exitFullscreen) == .collapsed)
}
