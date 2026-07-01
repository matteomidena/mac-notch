import SwiftUI
import Observation

public struct PluginManifest: Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public init(id: String, name: String, version: String, author: String) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
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

// `Observable` conformance is required so SwiftUI re-renders widgets when
// now-playing state changes. Conformers must be `@Observable`.
@MainActor public protocol NowPlayingService: AnyObject, Observable {
    var current: NowPlayingInfo? { get }
    func play(); func pause(); func toggle()
    func next(); func previous()
    func seek(to time: TimeInterval)
}

@MainActor public protocol PluginHost: AnyObject {
    var nowPlaying: NowPlayingService { get }
}

@MainActor public protocol NotchPlugin {
    static var manifest: PluginManifest { get }
    init(host: PluginHost)
    func widgets() -> [PluginWidget]
    // Optional compact views shown in the collapsed "ambient" bar, flanking the
    // physical notch (leading = left of notch, trailing = right). Default nil.
    func compactLeading() -> AnyView?
    func compactTrailing() -> AnyView?
}

public extension NotchPlugin {
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
}
