import Testing
import SwiftUI
@testable import OpenNotchKit

@MainActor @Test func mediaPluginProvidesMusicTab() {
    let plugin = MediaPlugin(host: FakeHost())
    #expect(plugin.tabs().map(\.id) == ["music"])
    #expect(plugin.widgets().isEmpty)
    #expect(plugin.compactTrailing() == nil)
    #expect(MediaPlugin.manifest.id == "cafe.notch.media")
}

@MainActor @Test func shuffleCallsService() {
    let host = FakeHost()
    NowPlayingViewModel(service: host.nowPlaying).shuffle()
    #expect(host.np.calls.contains("toggleShuffle"))
}

@MainActor @Test func transportButtonsCallHostService() {
    let host = FakeHost()
    let vm = NowPlayingViewModel(service: host.nowPlaying)
    vm.toggle(); vm.next(); vm.previous()
    #expect(host.np.calls == ["toggle", "next", "previous"])
}
