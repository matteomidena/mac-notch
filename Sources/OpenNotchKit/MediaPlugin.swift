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
    public func openLeading() -> AnyView? { AnyView(OpenWing(host: host)) }
}

/// Open-panel strip, left of the camera: artwork and a scrolling "title · artist" while something plays.
struct OpenWing: View {
    let host: PluginHost
    var body: some View {
        if let info = host.nowPlaying.current, info.isPlaying {
            HStack(spacing: 6) {
                ArtworkView(data: info.artworkData, size: 16, cornerRadius: 4)
                Marquee(text: [info.title, info.artist].compactMap { $0 }.joined(separator: " · "))
                    .font(Hex.text(11, weight: .medium)).foregroundStyle(Hex.ink)
                    .frame(width: 74)
            }
            .transition(.opacity)
        }
    }
}

/// Single-line text that scrolls in a loop when it doesn't fit; static otherwise.
struct Marquee: View {
    let text: String
    var speed: Double = 22   // points per second
    var gap: CGFloat = 28
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @Environment(\.batterySaver) private var saver
    @Environment(\.pauseAmbientMotion) private var paused

    var body: some View {
        let label = Text(text).lineLimit(1).fixedSize()
        Color.clear.frame(height: 14)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { boxWidth = $0 }
            .overlay(alignment: .leading) {
                if textWidth > boxWidth {
                    TimelineView(.animation(minimumInterval: 1.0 / (saver ? 15 : 30), paused: paused)) { ctx in
                        let cycle = Double(textWidth + gap)
                        let x = CGFloat((ctx.date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: cycle))
                        HStack(spacing: gap) { label; label }.offset(x: -x)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                                 .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                } else {
                    label
                }
            }
            .background(alignment: .leading) {
                label.hidden().onGeometryChange(for: CGFloat.self, of: \.size.width) { textWidth = $0 }
            }
            .clipped()
    }
}

struct CompactWing: View {
    let host: PluginHost
    var body: some View {
        // Only while playing: a paused or ended session has no menu bar icon either.
        if let info = host.nowPlaying.current, info.isPlaying {
            HStack(spacing: 4) {
                ArtworkView(data: info.artworkData, size: 16, cornerRadius: 4)
                EqualizerBars(isPlaying: true, barHeight: 13).foregroundStyle(Hex.ink)
            }
            .offset(y: -3)
            .transition(.opacity)
        }
    }
}
