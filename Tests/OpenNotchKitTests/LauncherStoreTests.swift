import Testing
import Foundation
@testable import OpenNotchKit

@MainActor @Test func launcherStoreAddsRemovesAndDedupes() {
    let suite = "opennotch.tests.store.a"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    let s = LauncherStore(defaults: d, key: "k")
    s.add("com.a"); s.add("com.b"); s.add("com.a")   // dup ignored
    #expect(s.bundleIds == ["com.a", "com.b"])
    #expect(s.contains("com.b") == true)
    s.remove("com.a")
    #expect(s.bundleIds == ["com.b"])
}

@MainActor @Test func launcherStorePersistsAcrossInstances() {
    let suite = "opennotch.tests.store.b"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    let s1 = LauncherStore(defaults: d, key: "k")
    s1.add("com.x"); s1.add("com.y")
    let s2 = LauncherStore(defaults: d, key: "k")
    #expect(s2.bundleIds == ["com.x", "com.y"])
}
