import Testing
import Foundation
@testable import OpenNotchKit

// Reuses FakeHost from PluginRuntimeTests.swift.

@MainActor @Test func loaderRejectsIncompatibleApiVersion() throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let dir = tmp.appendingPathComponent("x.notchplugin")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{ "id":"x","name":"x","version":"1","author":"t","apiVersion":"2.0.0","bundleName":"x.bundle" }"#
        .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

    var loader = PluginLoader()
    loader.openExecutable = { _ in Issue.record("should not dlopen an incompatible plugin"); return nil }
    let host = FakeHost()
    #expect(throws: PluginLoadError.self) {
        try loader.load(pluginDirectory: dir, host: host)
    }
}

@MainActor @Test func loaderReportsMissingManifest() {
    let loader = PluginLoader()
    let host = FakeHost()
    #expect(throws: PluginLoadError.noManifest) {
        try loader.load(pluginDirectory: URL(fileURLWithPath: "/nonexistent.notchplugin"), host: host)
    }
}

// Real dlopen integration — skipped when no toolchain is present.
@MainActor @Test func loadsAndCallsRealFixture() throws {
    guard let swiftc = PluginFixtureBuilder.swiftcPath else { return }  // skip on toolchain-less CI
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let dir = try PluginFixtureBuilder.build(id: "fixture", into: tmp, swiftc: swiftc)

    // The kit-free fixture's entry returns a C string, not a PluginBox, so we
    // exercise the dlopen/dlsym/call seam directly (not the box reclaim).
    let loader = PluginLoader()
    let manifest = try parsePluginManifest(
        Data(contentsOf: dir.appendingPathComponent("manifest.json")))
    let exe = PluginLoader.executableURL(pluginDirectory: dir, manifest: manifest)
    let handle = try #require(loader.openExecutable(exe.path))
    let sym = try #require(loader.lookupEntry(handle))
    let fn = unsafeBitCast(sym, to: PluginCreateFn.self)
    let ret = fn(UnsafeMutableRawPointer(bitPattern: 0x1)!)  // fixture ignores host
    #expect(String(cString: ret.assumingMemoryBound(to: CChar.self)) == "fixture")
}

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("notchplugin-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
