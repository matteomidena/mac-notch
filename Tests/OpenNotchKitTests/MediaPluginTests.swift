import Testing
import SwiftUI
@testable import OpenNotchKit

@MainActor @Test func mediaPluginEmitsOneWideNowPlayingWidget() {
    let host = FakeHost()
    let plugin = MediaPlugin(host: host)
    let ws = plugin.widgets()
    #expect(ws.count == 1)
    #expect(ws.first?.id == "now-playing")
    #expect(ws.first?.size == .wide)
    #expect(MediaPlugin.manifest.id == "cafe.notch.media")
}

@MainActor @Test func transportButtonsCallHostService() {
    let host = FakeHost()
    let vm = NowPlayingViewModel(service: host.nowPlaying)
    vm.toggle(); vm.next(); vm.previous()
    #expect(host.np.calls == ["toggle", "next", "previous"])
}
