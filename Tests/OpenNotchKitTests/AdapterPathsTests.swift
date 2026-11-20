import Testing
import Foundation
@testable import OpenNotchKit

@Test func prefersBundleResourcesWhenPresent() {
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { _ in true })
    #expect(r.script == "/App/Contents/Resources/mediaremote-adapter/bin/mediaremote-adapter.pl")
    #expect(r.framework == "/App/Contents/Resources/mediaremote-adapter/build/MediaRemoteAdapter.framework")
}

@Test func fallsBackToCwdWhenBundleFilesMissing() {
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { _ in false })
    #expect(r.script == "/repo/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl")
    #expect(r.framework == "/repo/vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
}

@Test func fallsBackWhenNoBundleURL() {
    let r = AdapterPaths.resolve(bundleResourceURL: nil, cwd: "/repo", fileExists: { _ in true })
    #expect(r.script.hasPrefix("/repo/vendor/"))
}

@Test func interFontPrefersBundleWhenPresent() {
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { $0 == "/App/Contents/Resources/inter/InterVariable.ttf" })
    #expect(r.interFont == "/App/Contents/Resources/inter/InterVariable.ttf")
}

@Test func interFontFallsBackToCwd() {
    // Resolved independently of the adapter: the adapter is in the bundle, the font is not.
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { $0.contains("mediaremote-adapter") })
    #expect(r.interFont == "/repo/vendor/inter/InterVariable.ttf")
    #expect(r.script.hasPrefix("/App/"))
}
