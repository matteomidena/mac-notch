public enum NotchPhase: Equatable { case collapsed, expanded, pinned, hidden, alert }
public enum NotchEvent: Equatable {
    case hoverIn, hoverOut
    case click, clickOutside, escape
    case dragIn, dragOut
    case enterFullscreen, exitFullscreen
    case alertRaised, alertFolded, alertClosed
}

public struct NotchStateMachine {
    public private(set) var phase: NotchPhase
    public init(phase: NotchPhase = .collapsed) { self.phase = phase }

    public mutating func handle(_ event: NotchEvent) -> NotchPhase {
        // The alert strip owns hover and clicks: only the alert/escape/fullscreen
        // events leave it, everything else is ignored while it is showing.
        if phase == .alert {
            switch event {
            case .alertFolded, .alertClosed, .escape, .exitFullscreen: phase = .collapsed
            case .enterFullscreen: phase = .hidden
            default: break
            }
            return phase
        }
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
        case .alertRaised: if phase == .collapsed { phase = .alert }
        case .alertFolded, .alertClosed: break
        }
        return phase
    }
}
