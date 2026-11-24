import AppKit
import OpenNotchKit

/// Owns one NotchController per attached display (notch shape on the built-in
/// screen, pill fallback elsewhere — NotchGeometry decides per screen) and
/// rebuilds the set when displays change (lid, monitor plug, resolution).
@MainActor
final class DisplayCoordinator {
    private let runtime: PluginRuntime
    private let nowPlaying: NowPlayingService
    private let agents: AgentUsageService
    private var controllers: [NotchController] = []
    private var observer: NSObjectProtocol?

    init(runtime: PluginRuntime, nowPlaying: NowPlayingService, agents: AgentUsageService) {
        self.runtime = runtime
        self.nowPlaying = nowPlaying
        self.agents = agents
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        rebuild()
    }

    private func rebuild() {
        controllers.forEach { $0.tearDown() }
        controllers = NSScreen.screens.map { screen in
            let controller = NotchController(screen: screen, runtime: runtime,
                                             nowPlaying: nowPlaying, agents: agents)
            controller.show()
            return controller
        }
    }
}
