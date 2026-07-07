import Testing
import Foundation
@testable import OpenNotchKit

private func freshDefaults() -> UserDefaults {
    let suite = "test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

@Test func storageNamespacesKeysByPluginId() {
    let d = freshDefaults()
    let a = UserDefaultsPluginStorage(pluginId: "a", defaults: d)
    let b = UserDefaultsPluginStorage(pluginId: "b", defaults: d)
    a.set(["x"], forKey: "items")
    #expect(a.stringArray(forKey: "items") == ["x"])
    #expect(b.stringArray(forKey: "items") == nil)   // isolated namespace
}

@Test func storageRoundTripsData() {
    let s = UserDefaultsPluginStorage(pluginId: "a", defaults: freshDefaults())
    s.set(Data([1, 2, 3]), forKey: "blob")
    #expect(s.data(forKey: "blob") == Data([1, 2, 3]))
    s.set(nil as Data?, forKey: "blob")
    #expect(s.data(forKey: "blob") == nil)
}

@MainActor @Test func launcherStorePersistsThroughPluginStorage() {
    let s = UserDefaultsPluginStorage(pluginId: "launcher", defaults: freshDefaults())
    let store = LauncherStore(storage: s)
    store.add("com.apple.Safari")
    // A second store over the same storage sees the persisted value.
    let reload = LauncherStore(storage: s)
    #expect(reload.bundleIds == ["com.apple.Safari"])
}
