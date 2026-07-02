import SwiftUI

/// Reference quick-action plugin: turns the user's chosen apps (LauncherStore)
/// into launch pills. Imports only SwiftUI — all OS work goes through the host.
@MainActor public struct AppLauncherPlugin: NotchPlugin {
    public static let manifest = PluginManifest(
        id: "cafe.notch.launcher", name: "App Launcher", version: "1.0.0", author: "OpenNotch")

    private let host: PluginHost
    private let store: LauncherStore

    public init(host: PluginHost) { self.init(host: host, store: LauncherStore()) }
    public init(host: PluginHost, store: LauncherStore) {
        self.host = host
        self.store = store
    }

    public func widgets() -> [PluginWidget] { [] }

    public func quickActions() -> [QuickAction] {
        let installed = host.installedApps()
        return store.bundleIds.compactMap { id in
            guard let app = installed.first(where: { $0.bundleId == id }) else { return nil }
            return QuickAction(id: id, title: app.name, systemImage: "app.fill",
                               iconData: app.iconData,
                               action: { host.launchApp(bundleIdentifier: id) })
        }
    }
}
