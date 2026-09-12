import Testing
@testable import OpenNotchKit

@Test func cleanLoadLeavesNothingBlocked() {
    let store = InMemoryMarkerStore()
    let bl = PluginBlocklist(store: store)
    bl.beginLoad("weather")
    bl.endLoad("weather")
    #expect(store.markers.isEmpty)
}

@Test func markerSurvivingToNextLaunchIsBlocked() {
    let store = InMemoryMarkerStore()
    // Simulate a crash mid-load last run: marker persisted, never cleared.
    PluginBlocklist(store: store).beginLoad("crasher")   // "process died here"
    // Next launch:
    let next = PluginBlocklist(store: store)
    #expect(next.blocked == ["crasher"])
}

@Test func unblockClearsMarker() {
    let store = InMemoryMarkerStore()
    PluginBlocklist(store: store).beginLoad("crasher")
    let next = PluginBlocklist(store: store)
    next.unblock("crasher")
    #expect(next.blocked.isEmpty)
    #expect(store.markers.isEmpty)
}

@Test func multipleInflightMarkersTracked() {
    let store = InMemoryMarkerStore()
    let bl = PluginBlocklist(store: store)
    bl.beginLoad("a"); bl.beginLoad("b")
    bl.endLoad("a")
    #expect(store.markers == ["b"])
}
