# OpenNotch — Quick Actions plugin API + customizable App Launcher + Settings window

**Date:** 2026-07-02
**Status:** Approved (brainstorming)
**Supersedes placeholder:** `QuickActionsPlaceholder` in `Sources/OpenNotch/NotchShell.swift`

## Goal

Replace the hardcoded `QuickActionsPlaceholder` (the right column of the expanded
notch) with a real plugin contribution mechanism, and ship a first reference
plugin — an **App Launcher** whose apps are **user-customizable** through a new
tabbed **Settings** window. The picker only lists **installed** apps, so a user
can never choose an app they don't have.

## Constraints (inherited, non-negotiable)

- **Pure/executable split.** New domain logic (plugin API, store, launcher
  plugin, live reload) lives in `OpenNotchKit` and is unit-tested. Window /
  pills / clicks / app enumeration are AppKit and get **manual DoD**.
- **Plugins import only SwiftUI.** No `AppKit`/`NSPanel`/`MediaRemote`. The
  keystone test enforces it. Anything a plugin needs from the OS (launching an
  app, listing installed apps) is provided by the `PluginHost`.
  - Note: `NSImage(data:)` / `Image(nsImage:)` are reachable through `import
    SwiftUI` on macOS (see `ArtworkView`), so rendering icon `Data` in the kit
    does **not** count as importing AppKit.
- Tests use `import Testing` (`@Test`/`#expect`), not XCTest (CLT-only env).

## Architecture

### 1. Contribution API (`OpenNotchKit/PluginAPI.swift`)

```swift
public struct QuickAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String        // SF Symbol fallback
    public let iconData: Data?             // real app icon; rendered like artwork
    public let action: @MainActor () -> Void
    public init(id:title:systemImage:iconData:action:)
}

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let bundleId: String            // id == bundleId
    public let name: String
    public let iconData: Data?
    public var id: String { bundleId }
    public init(bundleId:name:iconData:)
}
```

`NotchPlugin` gains one method with a default (mirrors `compactLeading/Trailing`):

```swift
func quickActions() -> [QuickAction]   // default: []
```

`PluginHost` gains two capabilities:

```swift
func launchApp(bundleIdentifier: String)
func installedApps() -> [InstalledApp]
```

### 2. Shared config — `OpenNotchKit/LauncherStore.swift`

```swift
@Observable @MainActor public final class LauncherStore {
    public var bundleIds: [String]        // ordered; the chosen launcher apps
    public init(defaults: UserDefaults = .standard, key: String = "launcher.bundleIds")
    // load on init; persist to UserDefaults on every set of bundleIds
    public func add(_ bundleId: String)
    public func remove(_ bundleId: String)
    public func contains(_ bundleId: String) -> Bool
}
```

- `@Observable` so both the settings UI and the controller's live-reload react to
  changes. Persistence is `UserDefaults` (Foundation — allowed in the kit).
- One instance is owned by `AppDelegate` and shared with the plugin and the
  Settings window.

### 3. Reference plugin — `OpenNotchKit/AppLauncherPlugin.swift`

```swift
@MainActor public struct AppLauncherPlugin: NotchPlugin {
    static var manifest: PluginManifest { … "cafe.notch.launcher" … }
    init(host: PluginHost, store: LauncherStore)
    func quickActions() -> [QuickAction]
}
```

- For each `bundleId` in `store.bundleIds`, resolve `name` + `iconData` from
  `host.installedApps()`. Emit a `QuickAction{ id: bundleId, title: name,
  systemImage: "app.fill", iconData, action: { host.launchApp(bundleIdentifier:
  bundleId) } }`.
- A `bundleId` no longer present in `installedApps()` (app was uninstalled) is
  **skipped** — no dead pill.
- Imports only SwiftUI.

### 4. Runtime (`OpenNotchKit/PluginRuntime.swift`)

```swift
public var quickActions: [QuickAction] { plugins.flatMap { $0.quickActions() } }
```

Collected in plugin order, same shape as `compactLeading/Trailing`.

### 5. Shell (`Sources/OpenNotch/NotchShell.swift`)

- Delete `QuickActionsPlaceholder`. Add `QuickActionsColumn(actions: [QuickAction])`
  rendering each action as the existing **pill** style (icon + title) inside a
  `Button(action:)`. Icon = `iconData` rendered via `ArtworkView`-style
  `NSImage(data:)`, else `Image(systemName: systemImage)`.
- The expanded panel shows the divider + right column **only when
  `quickActions` is non-empty**; otherwise the player fills the panel.
- `NotchViewModel` gains `var quickActions: [QuickAction] = []`.
- Post-build: the expanded panel width (currently `500`) was tuned for the old
  placeholder (2 pills + a circle); re-tune once real pills render. Not blocking.

### 6. Live reload (`Sources/OpenNotch/NotchWindow.swift`)

- `NotchController.init` sets `model.quickActions = runtime.quickActions`.
- Add `observeLauncher()` using `withObservationTracking` on `store.bundleIds`
  (same one-shot re-arm pattern as `observePlayback`): on change →
  `runtime.reload()` is not needed for quick actions (they're a computed pull),
  so re-pull `model.quickActions = runtime.quickActions` and re-arm.

### 7. Host implementation (`Sources/OpenNotch/AppDelegate.swift`)

- `AppHost` implements:
  - `launchApp(bundleIdentifier:)` — `NSWorkspace.urlForApplication(withBundleIdentifier:)`
    then `openApplication(at:configuration:)`. Missing app → `NSLog`, no-op.
  - `installedApps()` — enumerate `.app` bundles in `/Applications`,
    `/System/Applications`, and `~/Applications`; for each read `bundleIdentifier`,
    display name, and `NSWorkspace.shared.icon(forFile:)` → PNG `Data` (small,
    e.g. 32pt). De-duplicate by bundleId. (ponytail: directory scan is simple and
    good enough; swap for LaunchServices if coverage gaps appear.)
- Register `AppLauncherPlugin(host:, store:)` alongside `MediaPlugin`.
- Own the single `LauncherStore` and pass it to the plugin and the Settings window.

### 8. Settings window (`Sources/OpenNotch/SettingsWindow.swift`)

- `SettingsView` — a SwiftUI `TabView`:
  - **General tab:** the **Launch at Login** toggle (`SMAppService.mainApp`,
    moved here from the status menu). Room for future settings.
  - **Shortcuts tab:** a searchable list of `host.installedApps()` with a toggle
    per app bound to `LauncherStore` membership (`contains`/`add`/`remove`).
    Checking an app makes it a launcher pill immediately (live reload).
- Hosted in an `NSWindow` managed by a small `SettingsWindowController`; opening
  it calls `NSApp.activate(ignoringOtherApps: true)` (accessory app).

### 9. Status menu (`Sources/OpenNotch/AppDelegate.swift`)

- Replace the current items with: **Settings…** (opens the window) and **Quit**.
- The Launch-at-Login item moves into the General tab.

## Data flow

```
Settings ▸ Shortcuts tab  ──toggle──▶  LauncherStore.bundleIds  (persisted)
                                             │ @Observable
                    withObservationTracking  ▼
NotchController ── re-pull ──▶ runtime.quickActions ──▶ model.quickActions ──▶ pills
                                   │
AppLauncherPlugin.quickActions() ──┘  (resolves name/icon via host.installedApps(),
                                       action → host.launchApp(bundleId))
```

## Testing

**OpenNotchKit unit tests** (fake `PluginHost` recording `launchApp` calls and
returning canned `installedApps()`):

- `AppLauncherPlugin.quickActions()` emits one action per **installed** chosen
  app, with matching `id`/`title`/`iconData`; skips a chosen bundleId that isn't
  installed.
- Invoking an action's closure calls `host.launchApp(bundleIdentifier:)` with the
  correct bundleId.
- `LauncherStore`: `add`/`remove`/`contains`, ordering, and persistence
  round-trip through an injected `UserDefaults` (e.g. a suite name).
- `PluginRuntime.quickActions` collects across plugins in order.
- **Keystone:** extend the existing import check so `AppLauncherPlugin` is proven
  to import only SwiftUI.

**Manual DoD** (user is the visual verifier):

- Pills render in the right column with real app icons; empty selection hides the
  divider + column.
- Clicking a pill launches/activates the app (non-activating panel doesn't steal
  focus).
- Settings ▸ Shortcuts: toggling an app updates the pills live; General ▸ Launch
  at Login still works.

## Implementation phases

- **Phase A (pure + wiring):** `QuickAction`/`InstalledApp` API, `LauncherStore`,
  `AppLauncherPlugin`, `runtime.quickActions`, shell `QuickActionsColumn`,
  live-reload wiring, `AppHost.launchApp`/`installedApps`, register the plugin.
  Unit-tested; verify pills appear (seed the store with a default bundleId or two
  for the walkthrough).
- **Phase B (settings UI):** tabbed Settings window (General + Shortcuts),
  installed-app enumeration list, status-menu "Settings…", move Launch at Login.
  Manual DoD.

## Out of scope (YAGNI)

- Reordering pills, custom titles/icons per pill, non-app actions (URLs,
  Shortcuts) — the API supports them later via new plugins; not built now.
- Runtime third-party plugin loading (that's M2, a separate increment).
