import SwiftUI

@MainActor public final class PluginRuntime {
    private let host: PluginHost
    private var plugins: [NotchPlugin]
    private let enabledStore: PluginStorage?
    private var disabledIds: Set<String>
    public private(set) var widgets: [PluginWidget] = []

    public init(host: PluginHost, plugins: [NotchPlugin], enabledStore: PluginStorage? = nil) {
        self.host = host
        self.plugins = plugins
        self.enabledStore = enabledStore
        self.disabledIds = Set(enabledStore?.stringArray(forKey: "disabledPluginIds") ?? [])
        reload()
    }

    /// Merge loaded third-party plugins into the single list.
    public func add(_ newPlugins: [NotchPlugin]) {
        plugins.append(contentsOf: newPlugins)
        reload()
    }

    public func isEnabled(_ id: String) -> Bool { !disabledIds.contains(id) }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabledIds.remove(id) } else { disabledIds.insert(id) }
        enabledStore?.set(Array(disabledIds), forKey: "disabledPluginIds")
        reload()
    }

    private var activePlugins: [NotchPlugin] {
        plugins.filter { isEnabled(type(of: $0).manifest.id) }
    }

    public func reload() {
        widgets = activePlugins.flatMap { $0.widgets() }
            .enumerated()
            .sorted { (rank($0.element.size), $0.offset) < (rank($1.element.size), $1.offset) }
            .map(\.element)
    }

    private func rank(_ s: WidgetSize) -> Int {
        switch s { case .wide: 0; case .medium: 1; case .small: 2 }
    }

    public var compactLeading: [AnyView] { activePlugins.compactMap { $0.compactLeading() } }
    public var compactTrailing: [AnyView] { activePlugins.compactMap { $0.compactTrailing() } }
    public var quickActions: [QuickAction] { activePlugins.flatMap { $0.quickActions() } }

    // MARK: Settings surface

    public var pluginSummaries: [(id: String, name: String, enabled: Bool, hasSettings: Bool)] {
        plugins.map {
            let m = type(of: $0).manifest
            return (m.id, m.name, isEnabled(m.id), $0.settingsPane() != nil)
        }
    }

    public func settingsPane(for id: String) -> AnyView? {
        plugins.first { type(of: $0).manifest.id == id }?.settingsPane() ?? nil
    }
}
