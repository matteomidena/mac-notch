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
