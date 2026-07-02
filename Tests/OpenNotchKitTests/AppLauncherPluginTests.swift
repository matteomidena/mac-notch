import Testing
import Foundation
@testable import OpenNotchKit

@MainActor private func storeWith(_ ids: [String], suite: String) -> LauncherStore {
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    let s = LauncherStore(defaults: d, key: "k")
    ids.forEach { s.add($0) }
    return s
}

@MainActor @Test func launcherEmitsOneActionPerInstalledChosenApp() {
    let host = FakeHost()
    host.apps = [InstalledApp(bundleId: "com.a", name: "Alpha", iconData: Data([1])),
                 InstalledApp(bundleId: "com.b", name: "Beta", iconData: nil)]
    let store = storeWith(["com.a", "com.missing", "com.b"], suite: "opennotch.tests.launcher.1")
    let actions = AppLauncherPlugin(host: host, store: store).quickActions()
    #expect(actions.map(\.id) == ["com.a", "com.b"])          // uninstalled skipped
    #expect(actions.first?.title == "Alpha")
    #expect(actions.first?.iconData == Data([1]))
    #expect(AppLauncherPlugin.manifest.id == "cafe.notch.launcher")
}

@MainActor @Test func launcherActionLaunchesViaHostOnly() {
    let host = FakeHost()
    host.apps = [InstalledApp(bundleId: "com.a", name: "Alpha", iconData: nil)]
    let store = storeWith(["com.a"], suite: "opennotch.tests.launcher.2")
    let action = AppLauncherPlugin(host: host, store: store).quickActions().first!
    action.action()
    #expect(host.launched == ["com.a"])                        // keystone: host API only
}
