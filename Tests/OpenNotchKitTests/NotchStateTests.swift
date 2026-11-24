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

@Test func alertRaisedOnlyFromCollapsed() {
    #expect(NotchStateMachine(phase: .collapsed).handleCopy(.alertRaised) == .alert)
    for phase in [NotchPhase.expanded, .pinned, .hidden, .alert] {
        #expect(NotchStateMachine(phase: phase).handleCopy(.alertRaised) == phase)
    }
}

@Test func alertOwnsHoverAndClicks() {
    for event in [NotchEvent.hoverIn, .hoverOut, .click, .clickOutside, .dragIn, .dragOut] {
        #expect(NotchStateMachine(phase: .alert).handleCopy(event) == .alert)
    }
}

@Test func alertClosesToCollapsed() {
    for event in [NotchEvent.alertFolded, .alertClosed, .escape, .exitFullscreen] {
        #expect(NotchStateMachine(phase: .alert).handleCopy(event) == .collapsed)
    }
    #expect(NotchStateMachine(phase: .alert).handleCopy(.enterFullscreen) == .hidden)
}

@Test func alertFoldedAndClosedIgnoredOutsideAlert() {
    for phase in [NotchPhase.collapsed, .pinned] {
        #expect(NotchStateMachine(phase: phase).handleCopy(.alertFolded) == phase)
        #expect(NotchStateMachine(phase: phase).handleCopy(.alertClosed) == phase)
    }
}

private extension NotchStateMachine {
    func handleCopy(_ event: NotchEvent) -> NotchPhase {
        var sm = self
        return sm.handle(event)
    }
}
