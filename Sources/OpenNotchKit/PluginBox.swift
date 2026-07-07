import Foundation

/// The `@_cdecl` entry point every plugin bundle exports.
public let pluginEntryPointName = "opennotch_plugin_create"

/// C ABI of the entry point: takes the host pointer, returns a `PluginBox` pointer.
public typealias PluginCreateFn =
    @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer

/// Reference wrapper: plugins may be structs, but a pointer across the C ABI
/// needs a reference type. The plugin returns `Unmanaged.passRetained(PluginBox(...))`.
public final class PluginBox {
    public let plugin: NotchPlugin
    public init(_ plugin: NotchPlugin) { self.plugin = plugin }
}

/// Host → opaque pointer (unretained; the host outlives every plugin).
@MainActor public func hostPointer(_ host: PluginHost) -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(host as AnyObject).toOpaque()
}

/// Opaque pointer → host (for plugin authors; the SDK entry point uses this).
@MainActor public func hostFromPointer(_ p: UnsafeMutableRawPointer) -> PluginHost {
    Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as! PluginHost
}

/// Opaque `PluginBox` pointer → the plugin (host side; consumes the +1 retain).
@MainActor public func pluginFromBoxPointer(_ p: UnsafeMutableRawPointer) -> NotchPlugin {
    Unmanaged<PluginBox>.fromOpaque(p).takeRetainedValue().plugin
}
