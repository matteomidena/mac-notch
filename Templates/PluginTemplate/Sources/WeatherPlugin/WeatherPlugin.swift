import SwiftUI
import OpenNotchKit

@MainActor struct WeatherPlugin: NotchPlugin {
    static let manifest = PluginManifest(
        id: "com.example.weather", name: "Weather", version: "1.0.0",
        author: "Example", apiVersion: "1.0.0", bundleName: "WeatherPlugin.bundle")
    let host: PluginHost
    init(host: PluginHost) { self.host = host }
    func widgets() -> [PluginWidget] {
        [PluginWidget(id: "weather", size: .small,
            content: AnyView(Label("72°", systemImage: "sun.max.fill").padding(8)))]
    }
}

/// The one required entry point. `makePlugin` (from OpenNotchKit) does the
/// pointer marshalling and the main-actor hop for you.
@_cdecl("opennotch_plugin_create")
public func opennotch_plugin_create(_ hostPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    makePlugin(hostPtr) { WeatherPlugin(host: $0) }
}
