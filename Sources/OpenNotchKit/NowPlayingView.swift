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
    private let vm: NowPlayingViewModel
    public init(service: NowPlayingService) { self.vm = NowPlayingViewModel(service: service) }
    public var body: some View {
        HStack(spacing: 12) {
            if let bytes = vm.info?.artworkData, let img = NSImage(data: bytes) {
                Image(nsImage: img).resizable().frame(width: 44, height: 44).cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3)).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading) {
                Text(vm.info?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                Text(vm.info?.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: vm.previous) { Image(systemName: "backward.fill") }
            Button(action: vm.toggle) { Image(systemName: (vm.info?.isPlaying ?? false) ? "pause.fill" : "play.fill") }
            Button(action: vm.next) { Image(systemName: "forward.fill") }
        }.padding(12).frame(width: 360)
    }
}
