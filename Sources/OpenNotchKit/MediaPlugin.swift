import SwiftUI

@MainActor public struct MediaPlugin: NotchPlugin {
    public static let manifest = PluginManifest(
        id: "cafe.notch.media", name: "Media", version: "1.0.0", author: "OpenNotch")
    private let host: PluginHost
    public init(host: PluginHost) { self.host = host }
    public func widgets() -> [PluginWidget] {
        [PluginWidget(id: "now-playing", size: .wide,
                      content: AnyView(NowPlayingView(service: host.nowPlaying)))]
    }
}
