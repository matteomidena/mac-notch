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

/// SDK helper for the `@_cdecl` entry point — hides the pointer marshalling and
/// the main-actor hop. A plugin's entry point is a one-liner:
///
///     @_cdecl("opennotch_plugin_create")
///     public func opennotch_plugin_create(_ h: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
///         makePlugin(h) { MyPlugin(host: $0) }
///     }
///
/// The host always calls the entry on the main thread, so re-entering the main
/// actor here is safe. (We bridge through `UInt` because a raw pointer isn't
/// `Sendable` and `assumeIsolated` requires a `Sendable` result.)
public func makePlugin(_ hostPtr: UnsafeMutableRawPointer,
                       _ build: @MainActor @Sendable (PluginHost) -> NotchPlugin) -> UnsafeMutableRawPointer {
    // Launder pointers through UInt (Sendable) so nothing non-Sendable is
    // captured across the main-actor boundary the compiler can't see is safe.
    let hostAddr = UInt(bitPattern: hostPtr)
    let addr = MainActor.assumeIsolated {
        let host = hostFromPointer(UnsafeMutableRawPointer(bitPattern: hostAddr)!)
        return UInt(bitPattern: Unmanaged.passRetained(PluginBox(build(host))).toOpaque())
    }
    return UnsafeMutableRawPointer(bitPattern: addr)!
}
