public enum NotchPhase: Equatable { case collapsed, expanded, pinned, hidden }
public enum NotchEvent: Equatable {
    case hoverIn, hoverOut
    case click, clickOutside, escape
    case dragIn, dragOut
    case enterFullscreen, exitFullscreen
}

public struct NotchStateMachine {
    public private(set) var phase: NotchPhase
    public init(phase: NotchPhase = .collapsed) { self.phase = phase }

    public mutating func handle(_ event: NotchEvent) -> NotchPhase {
        switch event {
        case .enterFullscreen: phase = .hidden
        case .exitFullscreen:  phase = .collapsed
        case .hoverIn:  if phase == .collapsed { phase = .expanded }
        case .hoverOut: if phase == .expanded { phase = .collapsed }
        case .click:
            // Pins open. Never closes: clicks on buttons inside the panel also
            // arrive here, and interacting must not dismiss the panel.
            if phase == .collapsed || phase == .expanded { phase = .pinned }
        case .clickOutside, .escape:
            if phase == .expanded || phase == .pinned { phase = .collapsed }
        case .dragIn:  if phase == .collapsed { phase = .expanded }
        case .dragOut: if phase == .expanded { phase = .collapsed }
        }
        return phase
    }
}
