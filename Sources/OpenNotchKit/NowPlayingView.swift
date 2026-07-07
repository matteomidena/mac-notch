import SwiftUI

@MainActor public final class NowPlayingViewModel {
    private let service: NowPlayingService
    public init(service: NowPlayingService) { self.service = service }
    public func toggle() { service.toggle() }
    public func next() { service.next() }
    public func previous() { service.previous() }
    public func seek(to t: TimeInterval) { service.seek(to: t) }
}

/// Album artwork thumbnail with a music-note placeholder when none is available.
public struct ArtworkView: View {
    private let data: Data?
    private let size: CGFloat
    public init(data: Data?, size: CGFloat = 40) { self.data = data; self.size = size }
    public var body: some View {
        Group {
            if let data, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.15))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }
}

/// Decorative audio-level bars that bounce while playing and rest flat when paused.
/// (Not a real FFT — MediaRemote gives no level data; this is an ambient indicator.)
public struct EqualizerBars: View {
    private let isPlaying: Bool
    private let barHeight: CGFloat
    private let barCount = 4
    public init(isPlaying: Bool, barHeight: CGFloat = 18) {
        self.isPlaying = isPlaying
        self.barHeight = barHeight
    }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule().frame(width: 2.5, height: barHeight * height(i: i, t: t))
                }
            }
            .frame(height: barHeight)
        }
    }
    private func height(i: Int, t: Double) -> Double {
        guard isPlaying else { return 0.22 }
        let v = sin(t * 6.0 + Double(i) * 1.7) * 0.5 + 0.5
        return 0.25 + v * 0.75
    }
}

/// The player column of the expanded panel: large artwork with a source badge,
/// title / album / artist, and transport controls.
public struct NowPlayingView: View {
    // Held directly so `body` reads `service.current` inside SwiftUI's observation
    // scope — the service is `@Observable`, so this read makes the view re-render
    // on track/state changes. `vm` carries the transport actions.
    private let service: NowPlayingService
    private let vm: NowPlayingViewModel
    public init(service: NowPlayingService) {
        self.service = service
        self.vm = NowPlayingViewModel(service: service)
    }
    public var body: some View {
        let info = service.current
        if !service.isAvailable {
            return AnyView(
                Text("Media unavailable")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(width: 220, height: 60)
            )
        }
        return AnyView(HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(data: info?.artworkData, size: 60)
                Image(systemName: "music.note")           // source badge (generic)
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(.red))
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: 5, y: 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info?.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(info?.album ?? " ")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Text(info?.artist ?? " ")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                HStack(spacing: 18) {
                    Button(action: vm.previous) { Image(systemName: "backward.fill") }
                    Button(action: vm.toggle) {
                        Image(systemName: (info?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    }
                    Button(action: vm.next) { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain).font(.system(size: 12)).padding(.top, 3)
            }
            .frame(width: 150, alignment: .leading)
        }
        .foregroundStyle(.white))
    }
}
