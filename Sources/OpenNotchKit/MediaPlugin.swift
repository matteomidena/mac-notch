import SwiftUI

@MainActor public struct MediaPlugin: NotchPlugin, NotchTabProvider {
    public static let manifest = PluginManifest(
        id: "cafe.notch.media", name: "Media", version: "1.0.0", author: "OpenNotch")
    private let host: PluginHost
    public init(host: PluginHost) { self.host = host }
    public func widgets() -> [PluginWidget] { [] }

    public func tabs() -> [PluginTab] {
        [PluginTab(id: "music", title: "Music", systemImage: "music.note",
                   content: AnyView(MusicTabView(host: host)))]
    }

    // Closed-notch wing: artwork and bars left of the camera. Both observe the
    // services directly, so they follow track/playback changes.
    public func compactLeading() -> AnyView? { AnyView(CompactWing(host: host)) }
    public func compactTrailing() -> AnyView? { nil }
}

struct CompactWing: View {
    let host: PluginHost
    var body: some View {
        HStack(spacing: 6) {
            ArtworkView(data: host.nowPlaying.current?.artworkData, size: 18, cornerRadius: 4)
            EqualizerBars(isPlaying: host.nowPlaying.current?.isPlaying ?? false, barHeight: 13).foregroundStyle(musicColor)
        }
        .offset(y: -3)
    }
}
