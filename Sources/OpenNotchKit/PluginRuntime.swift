import SwiftUI

@MainActor public final class PluginRuntime {
    private let host: PluginHost
    private let plugins: [NotchPlugin]
    public private(set) var widgets: [PluginWidget] = []

    public init(host: PluginHost, plugins: [NotchPlugin]) {
        self.host = host
        self.plugins = plugins
        reload()
    }

    public func reload() {
        let rank: [WidgetSize: Int] = [.wide: 0, .medium: 1, .small: 2]
        widgets = plugins.flatMap { $0.widgets() }
            .enumerated()
            .sorted { (rank[$0.element.size]!, $0.offset) < (rank[$1.element.size]!, $1.offset) }
            .map(\.element)
    }

    /// Compact views for the ambient bar, in plugin order (first non-nil wins per side).
    public var compactLeading: [AnyView] { plugins.compactMap { $0.compactLeading() } }
    public var compactTrailing: [AnyView] { plugins.compactMap { $0.compactTrailing() } }
}
