import SwiftUI

@MainActor public struct MediaPlugin: NotchPlugin {
    public static let manifest = PluginManifest(
        id: "cafe.notch.media", name: "Media", version: "1.0.0", author: "OpenNotch")
    private let host: PluginHost
    public init(host: PluginHost) { self.host = host }
    public func widgets() -> [PluginWidget] {
        let host = self.host
        return [PluginWidget(id: "now-playing", size: .wide,
                             content: AnyView(NowPlayingView(
                                service: host.nowPlaying,
                                appIcon: { id in
                                    host.installedApps()
                                        .first(where: { $0.bundleId == id })?.iconData
                                })))]
    }

    // Ambient-bar contributions: artwork left of the notch, visualizer right.
    // These observe the service directly, so they follow track/playback changes.
    public func compactLeading() -> AnyView? {
        AnyView(CompactArtwork(service: host.nowPlaying))
    }
    public func compactTrailing() -> AnyView? {
        AnyView(CompactVisualizer(service: host.nowPlaying))
    }
}

/// Small artwork shown left of the notch in the ambient bar, nudged up so it
/// sits high in the menubar strip.
struct CompactArtwork: View {
    let service: NowPlayingService
    var body: some View {
        ArtworkView(data: service.current?.artworkData, size: 26).offset(y: -3)
    }
}

/// Small visualizer shown right of the notch in the ambient bar.
struct CompactVisualizer: View {
    let service: NowPlayingService
    var body: some View {
        EqualizerBars(isPlaying: service.current?.isPlaying ?? false, barHeight: 13)
            .foregroundStyle(.white)
            .offset(y: -3)
    }
}
