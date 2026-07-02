import Testing
import SwiftUI
@testable import OpenNotchKit

// Test doubles — public API only, no host internals.
@Observable @MainActor final class FakeNowPlaying: NowPlayingService {
    var current: NowPlayingInfo?
    @ObservationIgnored var calls: [String] = []
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func toggle() { calls.append("toggle") }
    func next() { calls.append("next") }
    func previous() { calls.append("previous") }
    func seek(to time: TimeInterval) { calls.append("seek:\(time)") }
}
@MainActor final class FakeHost: PluginHost {
    let np = FakeNowPlaying()
    var nowPlaying: NowPlayingService { np }
    var launched: [String] = []
    var apps: [InstalledApp] = []
    func launchApp(bundleIdentifier: String) { launched.append(bundleIdentifier) }
    func installedApps() -> [InstalledApp] { apps }
}
@MainActor struct StubPlugin: NotchPlugin {
    static let manifest = PluginManifest(id: "test.stub", name: "Stub", version: "1", author: "t")
    let host: PluginHost
    let sizes: [WidgetSize]
    init(host: PluginHost) { self.host = host; self.sizes = [.medium] }
    init(host: PluginHost, sizes: [WidgetSize]) { self.host = host; self.sizes = sizes }
    func widgets() -> [PluginWidget] {
        sizes.enumerated().map { i, s in PluginWidget(id: "w\(i)", size: s, content: AnyView(EmptyView())) }
    }
}

@MainActor @Test func collectsAndOrdersWidgetsBySize() {
    let host = FakeHost()
    let p = StubPlugin(host: host, sizes: [.small, .wide, .medium])
    let rt = PluginRuntime(host: host, plugins: [p])
    #expect(rt.widgets.map(\.size) == [.wide, .medium, .small])
}

@MainActor @Test func runtimeCollectsQuickActionsInPluginOrder() {
    let host = FakeHost()
    host.apps = [InstalledApp(bundleId: "com.a", name: "A", iconData: nil),
                 InstalledApp(bundleId: "com.b", name: "B", iconData: nil)]
    let suite = "opennotch.tests.rt.qa"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    let store = LauncherStore(defaults: d, key: "k")
    store.add("com.a"); store.add("com.b")
    let rt = PluginRuntime(host: host, plugins: [AppLauncherPlugin(host: host, store: store)])
    #expect(rt.quickActions.map(\.id) == ["com.a", "com.b"])
}
