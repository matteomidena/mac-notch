public enum NotchPhase: Equatable { case collapsed, expanded, hidden }
public enum NotchEvent: Equatable { case hoverIn, hoverOut, enterFullscreen, exitFullscreen }

public struct NotchStateMachine {
    public private(set) var phase: NotchPhase
    public init(phase: NotchPhase = .collapsed) { self.phase = phase }

    public mutating func handle(_ event: NotchEvent) -> NotchPhase {
        switch event {
        case .enterFullscreen: phase = .hidden
        case .exitFullscreen:  phase = .collapsed
        case .hoverIn:  if phase != .hidden { phase = .expanded }
        case .hoverOut: if phase != .hidden { phase = .collapsed }
        }
        return phase
    }
}
