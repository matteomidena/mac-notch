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

/// Fallback when there's no spectrum: 3 bars following a slow blend of sines, each eased
/// toward its target every frame (the mockup's low-pass). Static under Reduce Motion.
public struct EqualizerBars: View {
    private let isPlaying: Bool
    private let barHeight: CGFloat
    @State private var eased = Eased()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(isPlaying: Bool, barHeight: CGFloat = 18) {
        self.isPlaying = isPlaying
        self.barHeight = barHeight
    }
    /// Reference type so frames can ease without mutating @State during `body`.
    final class Eased { var v = [0.4, 0.6, 0.5] }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0,
                                paused: !isPlaying || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            SpectrumBars(levels: levels(t: t), isPlaying: true, height: barHeight)
        }
    }
    private func levels(t: Double) -> [Double] {
        if reduceMotion { return [0.45, 0.75, 0.55] }
        guard isPlaying else { return [0, 0, 0] }
        for i in 0..<3 {
            let d = Double(i)
            let target = 0.28 + 0.72 * (0.5 + 0.25 * sin(t * (2.1 + d * 0.7) + d * 1.9)
                                            + 0.25 * sin(t * (3.3 - d * 0.5) + d))
            eased.v[i] += (target - eased.v[i]) * 0.08
        }
        return eased.v
    }
}

/// The one place that picks real spectrum vs. the fallback bars.
struct VisualizerBars: View {
    let host: PluginHost
    let height: CGFloat
    var body: some View {
        let playing = host.nowPlaying.current?.isPlaying ?? false
        if host.spectrum.isAvailable {
            SpectrumBars(levels: host.spectrum.levels, isPlaying: playing, height: height)
        } else {
            EqualizerBars(isPlaying: playing, barHeight: height)
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
                    VisualizerBars(host: host, height: 22).foregroundStyle(musicColor)
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

let musicColor = Color(red: 1, green: 0xB0 / 255, blue: 0x8A / 255)
