import SwiftUI

@MainActor public final class NowPlayingViewModel {
    private let service: NowPlayingService
    public init(service: NowPlayingService) { self.service = service }
    public var info: NowPlayingInfo? { service.current }
    public func toggle() { service.toggle() }
    public func next() { service.next() }
    public func previous() { service.previous() }
    public func seek(to t: TimeInterval) { service.seek(to: t) }
}

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
        return HStack(spacing: 12) {
            if let bytes = info?.artworkData, let img = NSImage(data: bytes) {
                Image(nsImage: img).resizable().frame(width: 44, height: 44).cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3)).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading) {
                Text(info?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                Text(info?.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: vm.previous) { Image(systemName: "backward.fill") }
            Button(action: vm.toggle) { Image(systemName: (info?.isPlaying ?? false) ? "pause.fill" : "play.fill") }
            Button(action: vm.next) { Image(systemName: "forward.fill") }
        }.padding(12).frame(width: 360)
    }
}
