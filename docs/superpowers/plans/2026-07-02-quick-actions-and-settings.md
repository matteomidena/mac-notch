# Quick Actions Plugin API + Customizable App Launcher + Settings Window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `QuickActionsPlaceholder` with a real plugin contribution API, and ship a user-customizable App Launcher configured through a new tabbed Settings window (General + Shortcuts).

**Architecture:** New domain types (`QuickAction`, `InstalledApp`, `LauncherStore`, `AppLauncherPlugin`, `PluginRuntime.quickActions`) live in `OpenNotchKit` and are unit-tested. AppKit-dependent pieces (host `launchApp`/`installedApps`, the SwiftUI pills, the tabbed Settings window, status menu) live in the `OpenNotch` executable and get manual DoD. Plugins never import AppKit — anything OS-level comes from `PluginHost`.

**Tech Stack:** Swift, SwiftUI, AppKit (executable only), ServiceManagement (`SMAppService`), swift-testing (`import Testing`), SwiftPM.

## Global Constraints

- Tests use `import Testing` (`@Test`/`#expect`) — **never** XCTest (CommandLineTools-only environment).
- Plugins and everything in `OpenNotchKit` must **not** `import AppKit`/`import MediaRemote`. `NSImage(data:)`/`Image(nsImage:)` reached via `import SwiftUI` are allowed (see `ArtworkView`).
- The "keystone" guarantee = a plugin functions using **only** the public `PluginHost` API (proved with `FakeHost`), never privileged internals.
- Pure logic gets unit tests; window/rendering/clicks get manual DoD (the user is the visual verifier).
- Run the app with `swift run OpenNotch` from the repo root. Launch in background + `pkill -f .build/debug/OpenNotch` to stop.
- Build must pass warnings-as-errors: `swift build`. Full tests: `swift test`.
- New `@Observable` classes are `@MainActor` (match `NowPlayingService`/`NotchViewModel`).

---

## Phase A — Quick Actions API + App Launcher (pure + wiring)

### Task 1: Extend the plugin API (`QuickAction`, `InstalledApp`, host capabilities, plugin method)

**Files:**
- Modify: `Sources/OpenNotchKit/PluginAPI.swift`
- Modify (keep tests compiling): `Tests/OpenNotchKitTests/PluginRuntimeTests.swift` (the shared `FakeHost`)

**Interfaces:**
- Produces:
  - `struct QuickAction: Identifiable { let id: String; let title: String; let systemImage: String; let iconData: Data?; let action: @MainActor () -> Void }`
  - `struct InstalledApp: Identifiable, Equatable, Sendable { let bundleId: String; let name: String; let iconData: Data?; var id: String { bundleId } }`
  - `PluginHost.launchApp(bundleIdentifier: String)`, `PluginHost.installedApps() -> [InstalledApp]`
  - `NotchPlugin.quickActions() -> [QuickAction]` (default `[]`)

- [ ] **Step 1: Add the new types and protocol members to `PluginAPI.swift`**

Add after the existing `PluginWidget` struct:

```swift
/// A tappable quick action contributed to the expanded panel's right column.
/// `iconData` (a real app icon, PNG) is rendered like artwork; when nil the
/// `systemImage` SF Symbol is used instead.
public struct QuickAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let iconData: Data?
    public let action: @MainActor () -> Void
    public init(id: String, title: String, systemImage: String,
                iconData: Data? = nil, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.iconData = iconData
        self.action = action
    }
}

/// An installed application the host discovered, exposed to plugins so they can
/// resolve a bundle id to a display name + icon without touching AppKit.
public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let bundleId: String
    public let name: String
    public let iconData: Data?
    public var id: String { bundleId }
    public init(bundleId: String, name: String, iconData: Data?) {
        self.bundleId = bundleId
        self.name = name
        self.iconData = iconData
    }
}
```

Extend `PluginHost`:

```swift
@MainActor public protocol PluginHost: AnyObject {
    var nowPlaying: NowPlayingService { get }
    func launchApp(bundleIdentifier: String)
    func installedApps() -> [InstalledApp]
}
```

Extend `NotchPlugin` and its default-implementation extension:

```swift
@MainActor public protocol NotchPlugin {
    static var manifest: PluginManifest { get }
    init(host: PluginHost)
    func widgets() -> [PluginWidget]
    func compactLeading() -> AnyView?
    func compactTrailing() -> AnyView?
    func quickActions() -> [QuickAction]
}

public extension NotchPlugin {
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    func quickActions() -> [QuickAction] { [] }
}
```

- [ ] **Step 2: Update the shared `FakeHost` to conform (records launches, returns canned apps)**

In `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`, replace the `FakeHost` definition:

```swift
@MainActor final class FakeHost: PluginHost {
    let np = FakeNowPlaying()
    var nowPlaying: NowPlayingService { np }
    var launched: [String] = []
    var apps: [InstalledApp] = []
    func launchApp(bundleIdentifier: String) { launched.append(bundleIdentifier) }
    func installedApps() -> [InstalledApp] { apps }
}
```

- [ ] **Step 3: Build to verify the API compiles and existing tests still pass**

Run: `swift build && swift test`
Expected: builds clean; all previously-passing tests (21) still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenNotchKit/PluginAPI.swift Tests/OpenNotchKitTests/PluginRuntimeTests.swift
git commit -m "feat(kit): QuickAction/InstalledApp types + host launchApp/installedApps"
```

---

### Task 2: `LauncherStore` (persisted, observable list of chosen bundle ids)

**Files:**
- Create: `Sources/OpenNotchKit/LauncherStore.swift`
- Test: `Tests/OpenNotchKitTests/LauncherStoreTests.swift`

**Interfaces:**
- Produces: `@Observable @MainActor final class LauncherStore` with `var bundleIds: [String] { get }` (private set), `init(defaults: UserDefaults = .standard, key: String = "launcher.bundleIds")`, `add(_:)`, `remove(_:)`, `contains(_:) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenNotchKitTests/LauncherStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter launcherStore`
Expected: FAIL — `cannot find 'LauncherStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/OpenNotchKit/LauncherStore.swift`:

```swift
import Foundation
import Observation

/// The user's chosen launcher apps, in order. `@Observable` so the settings UI
/// and the notch controller both react to changes; persisted to UserDefaults.
@Observable @MainActor public final class LauncherStore {
    public private(set) var bundleIds: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "launcher.bundleIds") {
        self.defaults = defaults
        self.key = key
        self.bundleIds = defaults.stringArray(forKey: key) ?? []
    }

    public func add(_ bundleId: String) {
        guard !bundleIds.contains(bundleId) else { return }
        bundleIds.append(bundleId)
        save()
    }

    public func remove(_ bundleId: String) {
        bundleIds.removeAll { $0 == bundleId }
        save()
    }

    public func contains(_ bundleId: String) -> Bool { bundleIds.contains(bundleId) }

    private func save() { defaults.set(bundleIds, forKey: key) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter launcherStore`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/LauncherStore.swift Tests/OpenNotchKitTests/LauncherStoreTests.swift
git commit -m "feat(kit): LauncherStore — persisted observable list of launcher bundle ids"
```

---

### Task 3: `AppLauncherPlugin` (resolves chosen apps to quick actions) + keystone

**Files:**
- Create: `Sources/OpenNotchKit/AppLauncherPlugin.swift`
- Test: `Tests/OpenNotchKitTests/AppLauncherPluginTests.swift`

**Interfaces:**
- Consumes: `PluginHost.installedApps()`/`launchApp(bundleIdentifier:)`, `LauncherStore`, `QuickAction`.
- Produces: `struct AppLauncherPlugin: NotchPlugin` with `init(host:)` and `init(host:store:)`; `quickActions()` emits one action per installed chosen app (skips uninstalled), each action calling `host.launchApp`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/AppLauncherPluginTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter launcher`
Expected: FAIL — `cannot find 'AppLauncherPlugin' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/OpenNotchKit/AppLauncherPlugin.swift`:

```swift
import SwiftUI

/// Reference quick-action plugin: turns the user's chosen apps (LauncherStore)
/// into launch pills. Imports only SwiftUI — all OS work goes through the host.
@MainActor public struct AppLauncherPlugin: NotchPlugin {
    public static let manifest = PluginManifest(
        id: "cafe.notch.launcher", name: "App Launcher", version: "1.0.0", author: "OpenNotch")

    private let host: PluginHost
    private let store: LauncherStore

    public init(host: PluginHost) { self.init(host: host, store: LauncherStore()) }
    public init(host: PluginHost, store: LauncherStore) {
        self.host = host
        self.store = store
    }

    public func quickActions() -> [QuickAction] {
        let installed = host.installedApps()
        return store.bundleIds.compactMap { id in
            guard let app = installed.first(where: { $0.bundleId == id }) else { return nil }
            return QuickAction(id: id, title: app.name, systemImage: "app.fill",
                               iconData: app.iconData,
                               action: { host.launchApp(bundleIdentifier: id) })
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter launcher`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/AppLauncherPlugin.swift Tests/OpenNotchKitTests/AppLauncherPluginTests.swift
git commit -m "feat(kit): AppLauncherPlugin — chosen apps to launch actions via host"
```

---

### Task 4: `PluginRuntime.quickActions`

**Files:**
- Modify: `Sources/OpenNotchKit/PluginRuntime.swift`
- Test: `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`

**Interfaces:**
- Produces: `PluginRuntime.quickActions: [QuickAction]` (computed; plugins in registration order).

- [ ] **Step 1: Write the failing test**

Append to `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`:

```swift
@MainActor @Test func runtimeCollectsQuickActionsInPluginOrder() {
    let host = FakeHost()
    host.apps = [InstalledApp(bundleId: "com.a", name: "A", iconData: nil),
                 InstalledApp(bundleId: "com.b", name: "B", iconData: nil)]
    let suite = "opennotch.tests.rt.qa"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    let store = LauncherStore(defaults: d, key: "k")
    store.add("com.a"); store.add("com.b")
    let rt = PluginRuntime(host: host, plugins: [AppLauncherPlugin(host: host, store: store)])
    #expect(rt.quickActions.map(\.id) == ["com.a", "com.b"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter runtimeCollectsQuickActions`
Expected: FAIL — `value of type 'PluginRuntime' has no member 'quickActions'`.

- [ ] **Step 3: Add the computed property**

In `Sources/OpenNotchKit/PluginRuntime.swift`, after the `compactTrailing` computed property:

```swift
    /// Quick actions for the expanded panel's right column, in plugin order.
    public var quickActions: [QuickAction] { plugins.flatMap { $0.quickActions() } }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter runtimeCollectsQuickActions`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/PluginRuntime.swift Tests/OpenNotchKitTests/PluginRuntimeTests.swift
git commit -m "feat(kit): PluginRuntime.quickActions collector"
```

---

### Task 5: Render real quick-action pills in the expanded panel

**Files:**
- Modify: `Sources/OpenNotch/NotchShell.swift`

**Interfaces:**
- Consumes: `NotchViewModel.quickActions`, `QuickAction`, `ArtworkView`.
- Produces: `NotchViewModel.quickActions: [QuickAction]` (default `[]`); `QuickActionsColumn` view replacing `QuickActionsPlaceholder`; the divider + column render only when `quickActions` is non-empty.

- [ ] **Step 1: Add `quickActions` to the view model**

In `NotchViewModel` (in `NotchShell.swift`), add alongside `widgets`:

```swift
    var quickActions: [QuickAction] = []
```

- [ ] **Step 2: Replace `QuickActionsPlaceholder` with a real column**

Delete the entire `private struct QuickActionsPlaceholder { … }` and add:

```swift
/// The expanded panel's right column: one pill per plugin-contributed QuickAction.
private struct QuickActionsColumn: View {
    let actions: [QuickAction]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                Button(action: action.action) {
                    HStack(spacing: 8) {
                        icon(for: action)
                        Text(action.title)
                            .foregroundStyle(.white).font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(width: 132)
                    .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func icon(for action: QuickAction) -> some View {
        if let data = action.iconData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: action.systemImage).foregroundStyle(.white).font(.system(size: 13))
        }
    }
}
```

- [ ] **Step 3: Show the divider + column only when there are actions**

In the expanded branch of `content`, replace:

```swift
                HStack(alignment: .center, spacing: 12) {
                    ForEach(model.widgets) { $0.content }      // player (left)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 60)
                    QuickActionsPlaceholder()                  // shortcuts (right)
                }
```

with:

```swift
                HStack(alignment: .center, spacing: 12) {
                    ForEach(model.widgets) { $0.content }      // player (left)
                    if !model.quickActions.isEmpty {
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 60)
                        QuickActionsColumn(actions: model.quickActions)   // shortcuts (right)
                    }
                }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` (warnings-as-errors passes).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/NotchShell.swift
git commit -m "feat(ui): render real quick-action pills; hide right column when empty"
```

---

### Task 6: Wire the host, plugin, store, and live reload

**Files:**
- Modify: `Sources/OpenNotch/AppDelegate.swift`
- Modify: `Sources/OpenNotch/NotchWindow.swift`

**Interfaces:**
- Consumes: `AppLauncherPlugin`, `LauncherStore`, `PluginRuntime.quickActions`, `NotchViewModel.quickActions`.
- Produces: `AppHost.launchApp(bundleIdentifier:)`/`installedApps()`; a shared `LauncherStore` seeded with defaults; `NotchController` sets and live-updates `model.quickActions`.

- [ ] **Step 1: Add an NSImage→PNG helper and implement host capabilities in `AppDelegate.swift`**

At the top of `AppDelegate.swift` add `import SwiftUI` if not present, and add this helper near the top of the file (outside any type):

```swift
private extension NSImage {
    func pngData(maxPixel: CGFloat = 32) -> Data? {
        let target = NSImage(size: NSSize(width: maxPixel, height: maxPixel))
        target.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: maxPixel, height: maxPixel))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
```

Extend `AppHost` with the two capabilities:

```swift
    func launchApp(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("OpenNotch: no app for bundle id \(bundleIdentifier)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications",
                    (NSString(string: "~/Applications").expandingTildeInPath)]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                guard let bundle = Bundle(path: path),
                      let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                let data = NSWorkspace.shared.icon(forFile: path).pngData()
                apps.append(InstalledApp(bundleId: id, name: name, iconData: data))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
```

- [ ] **Step 2: Own a shared `LauncherStore`, seed it, register the plugin**

In `AppDelegate`, add a stored property:

```swift
    private let launcherStore = LauncherStore()
```

In `applicationDidFinishLaunching`, seed defaults on first run and register the plugin. Replace the runtime construction:

```swift
        if launcherStore.bundleIds.isEmpty {
            launcherStore.add("com.apple.Safari")
            launcherStore.add("com.apple.iCal")     // Calendar
        }
        let runtime = PluginRuntime(host: host, plugins: [
            MediaPlugin(host: host),
            AppLauncherPlugin(host: host, store: launcherStore),
        ])
```

- [ ] **Step 3: Set and live-update `model.quickActions` in `NotchWindow.swift`**

In `NotchController.init`, after `model.compactTrailing = runtime.compactTrailing.first`, add:

```swift
        model.quickActions = runtime.quickActions
```

Store the runtime so the observer can re-pull. Add a property near the other `private let`s:

```swift
    private let runtime: PluginRuntime
```

Set it at the very start of `init` (before `model = …`):

```swift
        self.runtime = runtime
```

At the end of `init` (after `observeFullscreen()`), add:

```swift
        observeQuickActions()
```

Add these methods near `observePlayback`:

```swift
    private func observeQuickActions() {
        withObservationTracking {
            _ = runtime.quickActions            // establishes dependency on store.bundleIds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.model.quickActions = self?.runtime.quickActions ?? []
                self?.observeQuickActions()     // re-arm (one-shot)
            }
        }
    }
```

> Note: `runtime.quickActions` reads `store.bundleIds` (an `@Observable` property) through `AppLauncherPlugin`, so `withObservationTracking` fires when the store changes.

- [ ] **Step 4: Build and run to verify pills appear**

Run: `swift build`
Expected: `Build complete!`

Then launch and eyeball (manual DoD):
```bash
pkill -f .build/debug/OpenNotch 2>/dev/null; nohup swift run OpenNotch >/tmp/opennotch.log 2>&1 &
```
Hover to expand — the right column should show **Safari** and **Calendar** pills with real icons; clicking one launches the app.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/AppDelegate.swift Sources/OpenNotch/NotchWindow.swift
git commit -m "feat: wire app-launcher plugin, host capabilities, and live quick-action reload"
```

---

## Phase B — Tabbed Settings window

### Task 7: Settings window (General + Shortcuts tabs) + status-menu "Settings…"

**Files:**
- Create: `Sources/OpenNotch/SettingsWindow.swift`
- Modify: `Sources/OpenNotch/AppDelegate.swift`

**Interfaces:**
- Consumes: `LauncherStore`, `AppHost.installedApps()`, `SMAppService`.
- Produces: `SettingsView` (TabView), `SettingsWindowController.show(store:installedApps:)`; status menu with **Settings…** + **Quit**; Launch at Login lives in the General tab.

- [ ] **Step 1: Create the tabbed Settings view + window controller**

Create `Sources/OpenNotch/SettingsWindow.swift`:

```swift
import SwiftUI
import AppKit
import ServiceManagement
import OpenNotchKit

struct SettingsView: View {
    let store: LauncherStore
    let installedApps: [InstalledApp]
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(store: store, apps: installedApps).tabItem { Label("Shortcuts", systemImage: "bolt") }
        }
        .frame(width: 460, height: 440)
    }
}

private struct GeneralTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("OpenNotch: launch at login toggle failed: \(error)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .padding(20)
    }
}

private struct ShortcutsTab: View {
    let store: LauncherStore
    let apps: [InstalledApp]
    @State private var query = ""
    private var filtered: [InstalledApp] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
            List(filtered) { app in
                Toggle(isOn: Binding(
                    get: { store.contains(app.bundleId) },
                    set: { $0 ? store.add(app.bundleId) : store.remove(app.bundleId) }
                )) {
                    HStack(spacing: 8) {
                        if let d = app.iconData, let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().frame(width: 20, height: 20)
                        }
                        Text(app.name)
                    }
                }
            }
        }
        .padding(20)
    }
}

@MainActor final class SettingsWindowController {
    private var window: NSWindow?
    func show(store: LauncherStore, installedApps: [InstalledApp]) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "OpenNotch Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store, installedApps: installedApps))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: Replace the status menu and open Settings from it**

In `AppDelegate.swift`, add a stored property:

```swift
    private let settings = SettingsWindowController()
```

Replace the body of `setUpStatusItem()` (keep the `statusItem` creation + `waveform` image) with a menu of just Settings + Quit:

```swift
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
```

Delete `toggleLaunchAtLogin(_:)` and its menu item (Launch at Login now lives in the General tab). Add the opener:

```swift
    @objc private func openSettings() {
        settings.show(store: launcherStore, installedApps: host?.installedApps() ?? [])
    }
```

> `host` is the stored `AppHost?`. If it's not optional-stored, adjust to the existing property; call `installedApps()` on it.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Manual DoD — verify the window and live reload**

```bash
pkill -f .build/debug/OpenNotch 2>/dev/null; nohup swift run OpenNotch >/tmp/opennotch.log 2>&1 &
```
- Click the menubar `waveform` icon → **Settings…** opens a window with **General** and **Shortcuts** tabs.
- General ▸ **Launch at Login** toggles (verify state sticks on reopen).
- Shortcuts ▸ search + toggle an app on/off → hover the notch: the pill appears/disappears **live**.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/SettingsWindow.swift Sources/OpenNotch/AppDelegate.swift
git commit -m "feat: tabbed Settings window (General + Shortcuts); move Launch at Login into it"
```

---

## Post-implementation

- **Visual re-tune (manual):** the expanded panel width (`expandedSize` in `NotchWindow.swift`, currently `500`) was sized for the old placeholder. With real pills, re-check and adjust width/height if there's dead space. Not a code-correctness item.
- Run the full suite once more: `swift test` (expected: all green, ~26 tests).

## Self-Review notes (done)

- **Spec coverage:** QuickAction/InstalledApp (T1), host capabilities (T1/T6), LauncherStore (T2), AppLauncherPlugin + keystone (T3), runtime collector (T4), pills + empty-state (T5), live reload + enumeration + launch (T6), tabbed Settings + General/Shortcuts + status menu + Launch-at-Login move (T7). All covered.
- **Keystone clarification:** the repo has no source-import-scanning test; the keystone is proved by `AppLauncherPlugin` functioning through `FakeHost` only (T3). Spec's "extend the keystone" is satisfied this way.
- **Type consistency:** `QuickAction`, `InstalledApp`, `launchApp(bundleIdentifier:)`, `installedApps()`, `LauncherStore.add/remove/contains/bundleIds`, `PluginRuntime.quickActions`, `NotchViewModel.quickActions` used consistently across tasks.
