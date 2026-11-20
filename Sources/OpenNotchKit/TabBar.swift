import Foundation

public struct TabItem: Equatable, Sendable {
    public let id, title, systemImage: String
    public init(id: String, title: String, systemImage: String) {
        self.id = id; self.title = title; self.systemImage = systemImage
    }
}

public enum TabBar {
    public static func items(providerTabs: [TabItem], hasWidgets: Bool, hasQuickActions: Bool) -> [TabItem] {
        var out = providerTabs
        if hasWidgets { out.append(TabItem(id: "widgets", title: "Widgets", systemImage: "square.grid.2x2")) }
        if hasQuickActions { out.append(TabItem(id: "launcher", title: "Launcher", systemImage: "square.grid.3x3.fill")) }
        return out
    }

    public static func defaultTab(_ items: [TabItem], hasLiveSession: Bool, isPlaying: Bool) -> String? {
        guard let first = items.first else { return nil }
        if hasLiveSession { return "agents" }
        if isPlaying { return "music" }
        return first.id
    }
}
