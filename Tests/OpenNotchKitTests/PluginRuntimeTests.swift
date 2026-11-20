import Testing
import SwiftUI
@testable import OpenNotchKit

// Test doubles — public API only, no host internals.
@Observable @MainActor final class FakeNowPlaying: NowPlayingService {
    var current: NowPlayingInfo?
    var isAvailable = true
    @ObservationIgnored var calls: [String] = []
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func toggle() { calls.append("toggle") }
    func next() { calls.append("next") }
    func previous() { calls.append("previous") }
    func seek(to time: TimeInterval) { calls.append("seek:\(time)") }
    func toggleShuffle() { calls.append("toggleShuffle") }
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

@MainActor @Test func disabledPluginProducesNoWidgets() {
    let host = FakeHost()
    let rt = PluginRuntime(host: host, plugins: [StubPlugin(host: host)])
    #expect(rt.widgets.count == 1)
    rt.setEnabled("test.stub", false)
    #expect(rt.widgets.isEmpty)
    #expect(rt.isEnabled("test.stub") == false)
}

@MainActor @Test func enabledStatePersistsAcrossRuntimes() {
    let store = UserDefaultsPluginStorage(pluginId: "runtime",
        defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!)
    let host = FakeHost()
    PluginRuntime(host: host, plugins: [StubPlugin(host: host)], enabledStore: store)
        .setEnabled("test.stub", false)
    let rt2 = PluginRuntime(host: host, plugins: [StubPlugin(host: host)], enabledStore: store)
    #expect(rt2.isEnabled("test.stub") == false)
    #expect(rt2.widgets.isEmpty)
}

@MainActor @Test func addMergesThirdPartyPlugins() {
    let host = FakeHost()
    let rt = PluginRuntime(host: host, plugins: [])
    rt.add([StubPlugin(host: host)])
    #expect(rt.pluginSummaries.contains { $0.id == "test.stub" })
    #expect(rt.widgets.count == 1)
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

@MainActor struct TabStubPlugin: NotchPlugin, NotchTabProvider {
    static let manifest = PluginManifest(id: "test.tabs", name: "Tabs", version: "1", author: "t")
    init(host: PluginHost) {}
    func widgets() -> [PluginWidget] { [PluginWidget(id: "tw", size: .small, content: AnyView(EmptyView()))] }
    func tabs() -> [PluginTab] { [PluginTab(id: "t", title: "T", systemImage: "t", content: AnyView(EmptyView()))] }
}

@MainActor @Test func providerTabsAndWidgetSplit() {
    let host = FakeHost()
    let rt = PluginRuntime(host: host, plugins: [TabStubPlugin(host: host), StubPlugin(host: host)])
    #expect(rt.tabs.map(\.id) == ["t"])
    #expect(rt.widgets.map(\.id) == ["w0"])
    rt.setEnabled("test.tabs", false)
    #expect(rt.tabs.isEmpty)
}

@MainActor @Test func hostDefaultsAreInertServices() {
    let host = FakeHost()
    #expect(host.agents.limits.isEmpty && host.agents.liveSessions.isEmpty)
    #expect(host.agents.alert == nil && !host.agents.canControl)
    #expect(host.spectrum.levels == [0, 0, 0] && !host.spectrum.isAvailable)
    host.np.toggleShuffle()  // default no-op must exist
}
