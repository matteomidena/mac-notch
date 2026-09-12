import Testing
import SwiftUI
@testable import OpenNotchKit

// Reuses FakeHost / StubPlugin from PluginRuntimeTests.swift (DRY).

@MainActor @Test func hostPointerRoundTrips() {
    let host = FakeHost()
    let p = hostPointer(host)
    let back = hostFromPointer(p)
    #expect(back is FakeHost)
}

@MainActor @Test func boxPointerRoundTripsAndConstructs() {
    let host = FakeHost()
    // Simulate what a plugin's @_cdecl entry does:
    let boxPtr = Unmanaged.passRetained(PluginBox(StubPlugin(host: host))).toOpaque()
    // Host side reclaims:
    let plugin = pluginFromBoxPointer(boxPtr)
    #expect(type(of: plugin).manifest.id == "test.stub")
    #expect(plugin.widgets().first?.size == .medium)
}
