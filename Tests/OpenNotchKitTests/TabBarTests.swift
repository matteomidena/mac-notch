import Testing
@testable import OpenNotchKit

private let agents = TabItem(id: "agents", title: "Agents", systemImage: "a")
private let music = TabItem(id: "music", title: "Music", systemImage: "m")

@Test func tabBarItemsOrder() {
    let all = TabBar.items(providerTabs: [agents, music], hasWidgets: true, hasQuickActions: true)
    #expect(all.map(\.id) == ["agents", "music", "widgets", "launcher"])
    #expect(all[2] == TabItem(id: "widgets", title: "Widgets", systemImage: "square.grid.2x2"))
    #expect(all[3] == TabItem(id: "launcher", title: "Launcher", systemImage: "square.grid.3x3.fill"))
    let none = TabBar.items(providerTabs: [agents, music], hasWidgets: false, hasQuickActions: false)
    #expect(none.map(\.id) == ["agents", "music"])
}

@Test func tabBarDefaultTab() {
    let items = [music, agents]
    #expect(TabBar.defaultTab(items, hasLiveSession: true, isPlaying: true) == "agents")
    #expect(TabBar.defaultTab(items, hasLiveSession: false, isPlaying: true) == "music")
    #expect(TabBar.defaultTab(items, hasLiveSession: false, isPlaying: false) == "music")
    #expect(TabBar.defaultTab([agents], hasLiveSession: false, isPlaying: false) == "agents")
    #expect(TabBar.defaultTab([], hasLiveSession: true, isPlaying: true) == nil)
}
