import SwiftUI

@MainActor public final class NowPlayingViewModel {
    private let service: NowPlayingService
    public init(service: NowPlayingService) { self.service = service }
    public func toggle() { service.toggle() }
    public func next() { service.next() }
    public func previous() { service.previous() }
    public func shuffle() { service.toggleShuffle() }
    public func seek(to t: TimeInterval) { service.seek(to: t) }
}

/// Album artwork thumbnail with a music-note placeholder when none is available.
public struct ArtworkView: View {
    private let data: Data?
    private let size: CGFloat
    private let cornerRadius: CGFloat?
    public init(data: Data?, size: CGFloat = 40, cornerRadius: CGFloat? = nil) {
        self.data = data; self.size = size; self.cornerRadius = cornerRadius
    }
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.18))
    }
}

/// Decorative equalizer: 3 capsules on out-of-phase sines (the July look). Still when paused
/// or under Reduce Motion.
public struct EqualizerBars: View {
    private let isPlaying: Bool
    private let barHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(isPlaying: Bool, barHeight: CGFloat = 18) {
        self.isPlaying = isPlaying
        self.barHeight = barHeight
    }
    nonisolated static func level(i: Int, t: Double, isPlaying: Bool, reduceMotion: Bool) -> Double {
        guard isPlaying else { return 0.22 }
        if reduceMotion { return [0.45, 0.75, 0.55][i] }
        return 0.25 + 0.75 * (sin(t * 6.0 + Double(i) * 1.7) * 0.5 + 0.5)
    }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0,
                                paused: !isPlaying || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().frame(width: 2.5, height: barHeight * Self.level(
                        i: i, t: t, isPlaying: isPlaying, reduceMotion: reduceMotion))
                }
            }
            .frame(height: barHeight)
        }
    }
}

/// Progress bar with drag-to-seek. Advances by wall clock between snapshots
/// (PlaybackProgress); a drag previews the target locally and seeks on release.
struct ProgressBar: View {
    let info: NowPlayingInfo
    let seek: (TimeInterval) -> Void
    @State private var dragTarget: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = info.duration ?? 0
            let position = dragTarget
                ?? PlaybackProgress.position(info: info, at: context.date) ?? 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white)
                        .frame(width: duration > 0
                               ? geo.size.width * min(position / duration, 1) : 0)
                }
                .contentShape(Rectangle().inset(by: -6))   // fat touch target
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            dragTarget = duration * fraction
                        }
                        .onEnded { _ in
                            if let target = dragTarget { seek(target) }
                            dragTarget = nil
                        })
            }
            .frame(height: 3)
        }
        .frame(height: 3)
    }
}

/// Music tab (mockup 3b): art, title / artist, bars, progress, transport row.
struct MusicTabView: View {
    let host: PluginHost
    private let vm: NowPlayingViewModel
    @Environment(\.openURL) private var openURL
    init(host: PluginHost) { self.host = host; self.vm = NowPlayingViewModel(service: host.nowPlaying) }

    var body: some View {
        let service = host.nowPlaying
        let info = service.current
        if !service.isAvailable {
            Text("Media unavailable").font(Hex.text(12)).foregroundStyle(Hex.muted)
                .frame(width: 220, height: 60)
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ArtworkView(data: info?.artworkData, size: 52, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info?.title ?? "Nothing playing").font(Hex.text(14, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(info?.artist ?? " ").font(Hex.text(13))
                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    EqualizerBars(isPlaying: host.nowPlaying.current?.isPlaying ?? false, barHeight: 22).foregroundStyle(Hex.ink)
                }
                if let info, info.duration != nil { ProgressBar(info: info, seek: vm.seek) }
                HStack(spacing: 24) {
                    button("shuffle", 15, dim: true, vm.shuffle)
                    button("backward.fill", 18, vm.previous)
                    button((info?.isPlaying ?? false) ? "pause.fill" : "play.fill", 22, vm.toggle)
                    button("forward.fill", 18, vm.next)
                    // ponytail: no public route-picker API for SwiftUI; open Sound settings instead.
                    button("airplayaudio", 15, dim: true) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                            openURL(url)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            .frame(maxWidth: 440)
        }
    }

    private func button(_ icon: String, _ size: CGFloat, dim: Bool = false,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size)) }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(dim ? 0.55 : 1))
    }
}

