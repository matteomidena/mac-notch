import SwiftUI
import Observation

public struct PluginManifest: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let apiVersion: String
    public let bundleName: String
    public init(id: String, name: String, version: String, author: String,
                apiVersion: String = "1.0.0", bundleName: String = "") {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.apiVersion = apiVersion
        self.bundleName = bundleName
    }
}

public enum WidgetSize: Equatable, Sendable { case small, medium, wide }

public struct PluginWidget: Identifiable {
    public let id: String
    public let size: WidgetSize
    public let content: AnyView
    public init(id: String, size: WidgetSize, content: AnyView) {
        self.id = id
        self.size = size
        self.content = content
    }
}

/// A tappable quick action contributed to the expanded panel's right column.
/// `iconData` (a real app icon, PNG) is rendered like artwork; when nil the
/// `systemImage` SF Symbol is used instead.
public struct QuickAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let iconData: Data?
    public let action: @MainActor () -> Void
    public init(id: String, title: String, systemImage: String,
                iconData: Data? = nil, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.iconData = iconData
        self.action = action
    }
}

/// An installed application the host discovered, exposed to plugins so they can
/// resolve a bundle id to a display name + icon without touching AppKit.
public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let bundleId: String
    public let name: String
    public let iconData: Data?
    public var id: String { bundleId }
    public init(bundleId: String, name: String, iconData: Data?) {
        self.bundleId = bundleId
        self.name = name
        self.iconData = iconData
    }
}

// `Observable` conformance is required so SwiftUI re-renders widgets when
// now-playing state changes. Conformers must be `@Observable`.
@MainActor public protocol NowPlayingService: AnyObject, Observable {
    var current: NowPlayingInfo? { get }
    /// False when the host's media backend is down (adapter kept crashing).
    var isAvailable: Bool { get }
    func play(); func pause(); func toggle()
    func next(); func previous()
    func seek(to time: TimeInterval)
}

@MainActor public protocol PluginHost: AnyObject {
    var nowPlaying: NowPlayingService { get }
    func launchApp(bundleIdentifier: String)
    func installedApps() -> [InstalledApp]
    func storage(for pluginId: String) -> PluginStorage
}

public extension PluginHost {
    func storage(for pluginId: String) -> PluginStorage {
        UserDefaultsPluginStorage(pluginId: pluginId)
    }
}

@MainActor public protocol NotchPlugin {
    static var manifest: PluginManifest { get }
    init(host: PluginHost)
    func widgets() -> [PluginWidget]
    // Optional compact views shown in the collapsed "ambient" bar, flanking the
    // physical notch (leading = left of notch, trailing = right). Default nil.
    func compactLeading() -> AnyView?
    func compactTrailing() -> AnyView?
    func quickActions() -> [QuickAction]
}

public extension NotchPlugin {
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    func quickActions() -> [QuickAction] { [] }
}
