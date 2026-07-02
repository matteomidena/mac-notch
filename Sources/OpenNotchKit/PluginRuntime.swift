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
        widgets = plugins.flatMap { $0.widgets() }
            .enumerated()
            .sorted { (rank($0.element.size), $0.offset) < (rank($1.element.size), $1.offset) }
            .map(\.element)
    }

    private func rank(_ s: WidgetSize) -> Int {
        switch s {
        case .wide: 0
        case .medium: 1
        case .small: 2
        }
    }

    /// Compact views for the ambient bar, in plugin order (first non-nil wins per side).
    public var compactLeading: [AnyView] { plugins.compactMap { $0.compactLeading() } }
    public var compactTrailing: [AnyView] { plugins.compactMap { $0.compactTrailing() } }

    /// Quick actions for the expanded panel's right column, in plugin order.
    public var quickActions: [QuickAction] { plugins.flatMap { $0.quickActions() } }
}
