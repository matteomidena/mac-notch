# OpenNotch v2 — Milestone M3 (Plugin Platform) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn OpenNotch's compiled-in plugin runtime into a real plugin *platform*: load third-party `.notchplugin` native bundles via `dlopen`, gate them by API version, blocklist crashers, arbitrate transient events, lay widgets out in a grid, manage them from a Settings tab, and publish `OpenNotchKit` as the SDK.

**Architecture:** The spec is `docs/superpowers/specs/2026-07-07-open-notch-v2-design.md` § "M3 — Plugin platform" — read it first. **Risk-#1 spike is done and GO** (`docs/superpowers/spikes/2026-07-07-m3-risk1-dlopen.md`): an unsigned host `dlopen`s a native plugin bundle on macOS 26. Pure logic (manifest parse, apiVersion gating, blocklist FSM, event arbitration, layout, storage namespacing, enable/disable) goes in `OpenNotchKit`, **test-first**. The `dlopen`/`dlsym` mechanics and the pointer-marshalling ABI also live in the kit and are covered by an integration test that compiles a minimal fixture with `swiftc` at test time (skips cleanly if `swiftc` is absent). AppKit/window/UI code goes in `OpenNotch` and is verified by the manual DoD checklist at the end.

**Tech Stack:** Swift 6 SPM package, SwiftUI + AppKit, swift-testing (`@Test`/`#expect`), `dlopen`/`dlsym` (libc, no new dependency).

## Global Constraints

- Platform floor: macOS 14 (`platforms: [.macOS(.v14)]` in Package.swift). Swift tools 6.0.
- **No new dependencies.** The only package dependency is swift-testing, tests only. `dlopen`/`dlsym` come from Darwin/libc — no package needed.
- Tests use `import Testing` (`@Test`, `#expect`) — never XCTest.
- **Pure/executable split:** domain logic in `Sources/OpenNotchKit` (unit-tested, test-first); window/AppKit code in `Sources/OpenNotch` (manual DoD).
- **Plugins import only SwiftUI.** `Sources/OpenNotchKit` files that are plugin-visible must not import AppKit.
- **YAGNI, per the spec:** "Grow `PluginHost` only as M4 plugins demand." Where a host capability has **no M3 consumer** (transient `events` rendering, permission-gated capabilities), build the **pure kit logic test-first** but do **not** wire it into the host protocol or the panel — leave a `ponytail:` note pointing at the M4 consumer. Where a capability **does** have an M3 consumer (storage → LauncherStore; per-plugin settings → Plugins tab; layout → panel; enable/disable → Plugins tab), wire it fully.
- **API version:** host declares `OPENNOTCH_API_VERSION = "1.0.0"`. Loader refuses a plugin whose `apiVersion` **major** differs from the host's, with a user-visible reason.
- **Entry point ABI (locked):** `@_cdecl("opennotch_plugin_create")(_ host: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer`. Host passes itself as `Unmanaged.passUnretained(host as AnyObject).toOpaque()`; plugin returns `Unmanaged.passRetained(PluginBox(myPlugin)).toOpaque()`; host reclaims with `takeRetainedValue()`. `PluginBox` is a kit class wrapping the `NotchPlugin` existential (plugins may be structs; the box gives a reference to cross the C boundary).
- Run tests with `swift test`. Build with `swift build`. Run the app with `swift run OpenNotch`.
- Commit style: `feat(kit):` for OpenNotchKit, `feat:`/`fix:` for the executable, `docs:`, `test:`. Commit after every task at minimum.

---

### Task 1: Manifest gains `apiVersion` + `bundleName`, plus JSON parsing

**Files:**
- Modify: `Sources/OpenNotchKit/PluginAPI.swift` (extend `PluginManifest`)
- Create: `Sources/OpenNotchKit/ManifestParsing.swift`
- Create: `Tests/OpenNotchKitTests/ManifestParsingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `PluginManifest` gains `apiVersion: String` and `bundleName: String` (both defaulted in `init` so compiled-in plugins are unaffected) and conforms to `Codable`. `enum ManifestError: Error, Equatable { case malformed(String) }`. `func parsePluginManifest(_ data: Data) throws -> PluginManifest`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/ManifestParsingTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenNotchKit

@Test func parsesValidManifest() throws {
    let json = """
    { "id": "weather", "name": "Weather", "version": "1.2.0",
      "author": "Acme", "apiVersion": "1.0.0", "bundleName": "Weather.bundle" }
    """.data(using: .utf8)!
    let m = try parsePluginManifest(json)
    #expect(m.id == "weather")
    #expect(m.name == "Weather")
    #expect(m.version == "1.2.0")
    #expect(m.author == "Acme")
    #expect(m.apiVersion == "1.0.0")
    #expect(m.bundleName == "Weather.bundle")
}

@Test func rejectsMissingRequiredField() {
    let json = #"{ "id": "weather", "name": "Weather" }"#.data(using: .utf8)!
    #expect(throws: ManifestError.self) { try parsePluginManifest(json) }
}

@Test func rejectsNonJSON() {
    let junk = Data([0x00, 0x01, 0x02])
    #expect(throws: ManifestError.self) { try parsePluginManifest(junk) }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ManifestParsing`
Expected: FAIL — `parsePluginManifest` / `ManifestError` not defined.

- [ ] **Step 3: Extend `PluginManifest` (make it Codable, add fields)**

In `Sources/OpenNotchKit/PluginAPI.swift` replace the `PluginManifest` struct with:

```swift
public struct PluginManifest: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let apiVersion: String
    public let bundleName: String
    public init(id: String, name: String, version: String, author: String,
                apiVersion: String = "1.0.0", bundleName: String = "") {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.apiVersion = apiVersion
        self.bundleName = bundleName
    }
}
```

- [ ] **Step 4: Implement the parser**

Create `Sources/OpenNotchKit/ManifestParsing.swift`:

```swift
import Foundation

public enum ManifestError: Error, Equatable {
    case malformed(String)
}

/// Parse a `.notchplugin` manifest.json into a `PluginManifest`.
/// All fields are required in the file; missing/extra/garbage → `.malformed`.
public func parsePluginManifest(_ data: Data) throws -> PluginManifest {
    do {
        return try JSONDecoder().decode(PluginManifest.self, from: data)
    } catch let e as DecodingError {
        throw ManifestError.malformed(String(describing: e))
    } catch {
        throw ManifestError.malformed(error.localizedDescription)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ManifestParsing`
Expected: PASS (3 tests). Also run `swift build` to confirm existing plugins still compile (they use the defaulted init).

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotchKit/PluginAPI.swift Sources/OpenNotchKit/ManifestParsing.swift Tests/OpenNotchKitTests/ManifestParsingTests.swift
git commit -m "feat(kit): manifest apiVersion/bundleName + JSON parsing"
```

---

### Task 2: API-version compatibility gate

**Files:**
- Create: `Sources/OpenNotchKit/APIVersion.swift`
- Create: `Tests/OpenNotchKitTests/APIVersionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `let OPENNOTCH_API_VERSION = "1.0.0"`. `enum APICompatibility: Equatable { case compatible; case incompatible(reason: String) }`. `func apiCompatibility(host: String, plugin: String) -> APICompatibility` — compatible iff both parse as `major.minor.patch` and majors are equal; otherwise `.incompatible` with a human reason.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/APIVersionTests.swift`:

```swift
import Testing
@testable import OpenNotchKit

@Test func sameMajorIsCompatible() {
    #expect(apiCompatibility(host: "1.0.0", plugin: "1.0.0") == .compatible)
    #expect(apiCompatibility(host: "1.4.2", plugin: "1.0.9") == .compatible)
}

@Test func differentMajorIsIncompatible() {
    if case .incompatible = apiCompatibility(host: "1.0.0", plugin: "2.0.0") {} else {
        Issue.record("expected incompatible across majors")
    }
}

@Test func unparsableVersionIsIncompatible() {
    if case .incompatible = apiCompatibility(host: "1.0.0", plugin: "banana") {} else {
        Issue.record("expected incompatible for unparsable version")
    }
}

@Test func hostConstantIsSemver() {
    #expect(apiCompatibility(host: OPENNOTCH_API_VERSION, plugin: OPENNOTCH_API_VERSION) == .compatible)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter APIVersion`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/APIVersion.swift`:

```swift
/// The plugin API version this host implements. Bump the MAJOR on any
/// source-breaking change to the plugin-facing API; loader refuses mismatched majors.
public let OPENNOTCH_API_VERSION = "1.0.0"

public enum APICompatibility: Equatable {
    case compatible
    case incompatible(reason: String)
}

private func major(_ v: String) -> Int? {
    let parts = v.split(separator: ".")
    guard parts.count == 3, let m = Int(parts[0]),
          Int(parts[1]) != nil, Int(parts[2]) != nil else { return nil }
    return m
}

public func apiCompatibility(host: String, plugin: String) -> APICompatibility {
    guard let hostMajor = major(host) else {
        return .incompatible(reason: "host API version '\(host)' is not semver")
    }
    guard let pluginMajor = major(plugin) else {
        return .incompatible(reason: "plugin API version '\(plugin)' is not semver")
    }
    guard hostMajor == pluginMajor else {
        return .incompatible(reason: "plugin needs API v\(pluginMajor).x, host is v\(hostMajor).x")
    }
    return .compatible
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter APIVersion`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/APIVersion.swift Tests/OpenNotchKitTests/APIVersionTests.swift
git commit -m "feat(kit): API-version compatibility gate"
```

---

### Task 3: Crash-attribution blocklist state machine

**Files:**
- Create: `Sources/OpenNotchKit/PluginBlocklist.swift`
- Create: `Tests/OpenNotchKitTests/PluginBlocklistTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol MarkerStore: AnyObject { var markers: [String] { get set } }` — persistence seam.
  - `final class InMemoryMarkerStore: MarkerStore` (test + default).
  - `final class PluginBlocklist` with: `init(store: MarkerStore)`; `func beginLoad(_ id: String)` (adds a marker before dlopen/construct); `func endLoad(_ id: String)` (clears it on success); `var blocked: Set<String>` (ids still marked = they crashed mid-load on a previous run); `func unblock(_ id: String)` (user action, clears the marker). The invariant: any id left in `markers` after a run either is mid-load *right now* or crashed the host last time — on the next launch, whatever remains is `blocked`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/PluginBlocklistTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PluginBlocklist`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/PluginBlocklist.swift`:

```swift
import Foundation

/// Persistence seam for blocklist markers (a flat list of plugin ids currently
/// "mid-load"). Backed by UserDefaults in the app; in-memory in tests.
public protocol MarkerStore: AnyObject {
    var markers: [String] { get set }
}

public final class InMemoryMarkerStore: MarkerStore {
    public var markers: [String]
    public init(markers: [String] = []) { self.markers = markers }
}

/// UserDefaults-backed marker store.
public final class DefaultsMarkerStore: MarkerStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "plugin.loadMarkers") {
        self.defaults = defaults
        self.key = key
    }
    public var markers: [String] {
        get { defaults.stringArray(forKey: key) ?? [] }
        set { defaults.set(newValue, forKey: key) }
    }
}

/// Crash-attribution: a marker is written *before* each dlopen/construct and
/// cleared on success. Anything still marked when a fresh instance is created
/// (i.e. it survived a host restart) is presumed to have crashed the host and
/// is `blocked` until the user unblocks it.
public final class PluginBlocklist {
    private let store: MarkerStore
    /// Snapshot of markers present at construction — these crashed last run.
    public let blocked: Set<String>

    public init(store: MarkerStore) {
        self.store = store
        self.blocked = Set(store.markers)
    }

    public func beginLoad(_ id: String) {
        guard !store.markers.contains(id) else { return }
        store.markers.append(id)
    }

    public func endLoad(_ id: String) {
        store.markers.removeAll { $0 == id }
    }

    public func unblock(_ id: String) {
        store.markers.removeAll { $0 == id }
    }
}
```

Note: `blocked` is snapshotted at init (before any `beginLoad` this run), so this-run in-flight markers don't self-report as blocked. `unblock` mutates the store but `blocked` is a let — the Settings UI reads `blocked` minus locally-unblocked ids; the app rebuilds/relaunches to re-attempt, matching "updates require relaunch".

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PluginBlocklist`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/PluginBlocklist.swift Tests/OpenNotchKitTests/PluginBlocklistTests.swift
git commit -m "feat(kit): crash-attribution blocklist state machine"
```

---

### Task 4: Pointer-marshalling ABI (`PluginBox` + host/plugin bridging)

**Files:**
- Create: `Sources/OpenNotchKit/PluginBox.swift`
- Create: `Tests/OpenNotchKitTests/PluginBoxTests.swift`

**Interfaces:**
- Consumes: `NotchPlugin`, `PluginHost` (Task's baseline API).
- Produces:
  - `public final class PluginBox { public let plugin: NotchPlugin; public init(_ plugin: NotchPlugin) }` — reference wrapper so a struct plugin can cross the C ABI.
  - `public func hostPointer(_ host: PluginHost) -> UnsafeMutableRawPointer` — `Unmanaged.passUnretained(host as AnyObject).toOpaque()`.
  - `public func hostFromPointer(_ p: UnsafeMutableRawPointer) -> PluginHost` — inverse, for plugin authors (SDK).
  - `public func pluginFromBoxPointer(_ p: UnsafeMutableRawPointer) -> NotchPlugin` — `takeRetainedValue()` on a `PluginBox`, returns `.plugin`.
  - `public typealias PluginCreateFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer`
  - `public let pluginEntryPointName = "opennotch_plugin_create"`

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenNotchKitTests/PluginBoxTests.swift`:

```swift
import Testing
import SwiftUI
@testable import OpenNotchKit

// Minimal fake host + plugin to exercise the round trip in-process.
@MainActor final class FakeHost: PluginHost {
    let np: NowPlayingService
    init(np: NowPlayingService) { self.np = np }
    var nowPlaying: NowPlayingService { np }
    func launchApp(bundleIdentifier: String) {}
    func installedApps() -> [InstalledApp] { [] }
}

@MainActor struct EchoPlugin: NotchPlugin {
    static let manifest = PluginManifest(id: "echo", name: "Echo", version: "1", author: "t")
    let host: PluginHost
    init(host: PluginHost) { self.host = host }
    func widgets() -> [PluginWidget] {
        [PluginWidget(id: "w", size: .small, content: AnyView(EmptyView()))]
    }
}

@MainActor @Test func hostPointerRoundTrips() {
    let host = FakeHost(np: StubNowPlaying())
    let p = hostPointer(host)
    let back = hostFromPointer(p)
    #expect(back is FakeHost)
}

@MainActor @Test func boxPointerRoundTripsAndConstructs() {
    let host = FakeHost(np: StubNowPlaying())
    // Simulate what a plugin's @_cdecl entry does:
    let boxPtr = Unmanaged.passRetained(PluginBox(EchoPlugin(host: host))).toOpaque()
    // Host side reclaims:
    let plugin = pluginFromBoxPointer(boxPtr)
    #expect(plugin.widgets().first?.id == "w")
}
```

Add a tiny `StubNowPlaying` if one isn't already shared in the test target:

```swift
@MainActor @Observable final class StubNowPlaying: NowPlayingService {
    var current: NowPlayingInfo? = nil
    var isAvailable: Bool = true
    func play() {}; func pause() {}; func toggle() {}
    func next() {}; func previous() {}; func seek(to time: TimeInterval) {}
}
```
(If `PluginRuntimeTests.swift` already defines a stub host / now-playing, reuse it and delete the duplicate — DRY. Check first with `grep -rn "NowPlayingService" Tests/`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PluginBox`
Expected: FAIL — `PluginBox` / bridging fns not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/PluginBox.swift`:

```swift
import Foundation

/// The `@_cdecl` entry point every plugin bundle exports.
public let pluginEntryPointName = "opennotch_plugin_create"

/// C ABI of the entry point: takes the host pointer, returns a `PluginBox` pointer.
public typealias PluginCreateFn =
    @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer

/// Reference wrapper: plugins may be structs, but a pointer across the C ABI
/// needs a reference type. The plugin returns `Unmanaged.passRetained(PluginBox(...))`.
public final class PluginBox {
    public let plugin: NotchPlugin
    public init(_ plugin: NotchPlugin) { self.plugin = plugin }
}

/// Host → opaque pointer (unretained; the host outlives every plugin).
@MainActor public func hostPointer(_ host: PluginHost) -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(host as AnyObject).toOpaque()
}

/// Opaque pointer → host (for plugin authors; the SDK entry point uses this).
@MainActor public func hostFromPointer(_ p: UnsafeMutableRawPointer) -> PluginHost {
    Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as! PluginHost
}

/// Opaque `PluginBox` pointer → the plugin (host side; consumes the +1 retain).
@MainActor public func pluginFromBoxPointer(_ p: UnsafeMutableRawPointer) -> NotchPlugin {
    Unmanaged<PluginBox>.fromOpaque(p).takeRetainedValue().plugin
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PluginBox`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/PluginBox.swift Tests/OpenNotchKitTests/PluginBoxTests.swift
git commit -m "feat(kit): plugin pointer-marshalling ABI (PluginBox)"
```

---

### Task 5: `dlopen` loader assembly (with injectable resolver + fixture integration test)

**Files:**
- Create: `Sources/OpenNotchKit/PluginLoader.swift`
- Create: `Tests/OpenNotchKitTests/PluginLoaderTests.swift`
- Create: `Tests/OpenNotchKitTests/PluginFixtureBuilder.swift` (test helper)

**Interfaces:**
- Consumes: `parsePluginManifest`, `apiCompatibility`, `PluginBox`/`PluginCreateFn`/`pluginEntryPointName`, `hostPointer`, `pluginFromBoxPointer`, `OPENNOTCH_API_VERSION`.
- Produces:
  - `enum PluginLoadError: Error, Equatable { case noManifest, manifest(String), incompatible(String), noExecutable, dlopenFailed(String), noEntryPoint }`
  - `struct PluginLoader`:
    - `var openExecutable: (String) -> UnsafeMutableRawPointer?` — defaults to `dlopen($0, RTLD_NOW)`; injectable for tests.
    - `var lookupEntry: (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?` — defaults to `dlsym($0, pluginEntryPointName)`; injectable.
    - `func load(pluginDirectory: URL, host: PluginHost, hostAPIVersion: String = OPENNOTCH_API_VERSION) throws -> NotchPlugin` — reads `manifest.json`, gates apiVersion, finds `bundleName`'s Mach-O, dlopens, dlsyms, calls the entry with `hostPointer(host)`, returns `pluginFromBoxPointer(...)`.
    - `static func executableURL(pluginDirectory: URL, manifest: PluginManifest) -> URL` — `dir/<bundleName>/Contents/MacOS/<bundleName without .bundle>`.

- [ ] **Step 1: Write the fixture builder (test helper)**

Create `Tests/OpenNotchKitTests/PluginFixtureBuilder.swift`. It compiles a **kit-free** minimal `.notchplugin` at test time (proves dlopen/dlsym/entry-call mechanics without the complexity of linking OpenNotchKit; the full kit-linked path is covered by the SDK template's manual DoD). The fixture's entry returns a pointer the test can verify:

```swift
import Foundation

enum PluginFixtureBuilder {
    /// Path to `swiftc`, or nil if unavailable (CI without a toolchain → skip).
    static var swiftcPath: String? {
        let candidates = ["/usr/bin/swiftc", "/usr/local/bin/swiftc"]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Fall back to `xcrun -f swiftc`.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["-f", "swiftc"]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Build a `.notchplugin` whose entry point returns a pointer to a heap
    /// C string == `id`. Returns the plugin directory URL. Caller owns cleanup.
    static func build(id: String, apiVersion: String = "1.0.0",
                      into base: URL, swiftc: String) throws -> URL {
        let fm = FileManager.default
        let dir = base.appendingPathComponent("\(id).notchplugin")
        let bundle = dir.appendingPathComponent("\(id).bundle")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        let src = base.appendingPathComponent("\(id).swift")
        try """
        import Foundation
        @_cdecl("opennotch_plugin_create")
        public func opennotch_plugin_create(_ host: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
            return UnsafeMutableRawPointer(mutating: strdup("\(id)"))
        }
        """.write(to: src, atomically: true, encoding: .utf8)

        let exe = macos.appendingPathComponent(id)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: swiftc)
        p.arguments = ["-emit-library", "-o", exe.path, src.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "fixture", code: Int(p.terminationStatus))
        }

        let manifest = """
        { "id": "\(id)", "name": "\(id)", "version": "1.0.0",
          "author": "test", "apiVersion": "\(apiVersion)", "bundleName": "\(id).bundle" }
        """
        try manifest.write(to: dir.appendingPathComponent("manifest.json"),
                           atomically: true, encoding: .utf8)
        return dir
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/OpenNotchKitTests/PluginLoaderTests.swift`. Two layers: orchestration (injected resolvers, always runs) and a real-dlopen integration test (skips if no `swiftc`).

```swift
import Testing
import Foundation
@testable import OpenNotchKit

@MainActor @Test func loaderRejectsIncompatibleApiVersion() throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let dir = tmp.appendingPathComponent("x.notchplugin")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{ "id":"x","name":"x","version":"1","author":"t","apiVersion":"2.0.0","bundleName":"x.bundle" }"#
        .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

    var loader = PluginLoader()
    loader.openExecutable = { _ in fatalError("should not dlopen an incompatible plugin") }
    let host = FakeHost(np: StubNowPlaying())
    #expect(throws: PluginLoadError.self) {
        try loader.load(pluginDirectory: dir, host: host)
    }
}

@MainActor @Test func loaderReportsMissingManifest() {
    let loader = PluginLoader()
    let host = FakeHost(np: StubNowPlaying())
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter PluginLoader`
Expected: FAIL — `PluginLoader` / `PluginLoadError` not defined.

- [ ] **Step 4: Implement the loader**

Create `Sources/OpenNotchKit/PluginLoader.swift`:

```swift
import Foundation

public enum PluginLoadError: Error, Equatable {
    case noManifest
    case manifest(String)
    case incompatible(String)
    case noExecutable
    case dlopenFailed(String)
    case noEntryPoint
}

public struct PluginLoader {
    /// dlopen seam (injectable for tests). Default: real dlopen.
    public var openExecutable: (String) -> UnsafeMutableRawPointer? = { path in
        dlopen(path, RTLD_NOW)
    }
    /// dlsym seam (injectable for tests). Default: real dlsym for the entry point.
    public var lookupEntry: (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? = { handle in
        dlsym(handle, pluginEntryPointName)
    }

    public init() {}

    public static func executableURL(pluginDirectory: URL, manifest: PluginManifest) -> URL {
        let bundle = pluginDirectory.appendingPathComponent(manifest.bundleName)
        let exeName = (manifest.bundleName as NSString).deletingPathExtension
        return bundle.appendingPathComponent("Contents/MacOS/\(exeName)")
    }

    @MainActor
    public func load(pluginDirectory: URL, host: PluginHost,
                     hostAPIVersion: String = OPENNOTCH_API_VERSION) throws -> NotchPlugin {
        let manifestURL = pluginDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { throw PluginLoadError.noManifest }
        let manifest: PluginManifest
        do { manifest = try parsePluginManifest(data) }
        catch { throw PluginLoadError.manifest(String(describing: error)) }

        if case .incompatible(let reason) = apiCompatibility(host: hostAPIVersion, plugin: manifest.apiVersion) {
            throw PluginLoadError.incompatible(reason)
        }

        let exe = Self.executableURL(pluginDirectory: pluginDirectory, manifest: manifest)
        guard FileManager.default.fileExists(atPath: exe.path) else { throw PluginLoadError.noExecutable }
        guard let handle = openExecutable(exe.path) else {
            throw PluginLoadError.dlopenFailed(String(cString: dlerror()))
        }
        guard let sym = lookupEntry(handle) else { throw PluginLoadError.noEntryPoint }

        let create = unsafeBitCast(sym, to: PluginCreateFn.self)
        let boxPtr = create(hostPointer(host))
        return pluginFromBoxPointer(boxPtr)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PluginLoader`
Expected: PASS (3 tests; the integration test runs when `swiftc` is present — confirm it did by checking `swift test --filter loadsAndCallsRealFixture -v` reports it ran, not skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotchKit/PluginLoader.swift Tests/OpenNotchKitTests/PluginLoaderTests.swift Tests/OpenNotchKitTests/PluginFixtureBuilder.swift
git commit -m "feat(kit): dlopen plugin loader + fixture integration test"
```

---

### Task 6: Per-plugin namespaced storage

**Files:**
- Create: `Sources/OpenNotchKit/PluginStorage.swift`
- Modify: `Sources/OpenNotchKit/PluginAPI.swift` (add `storage(for:)` to `PluginHost`)
- Modify: `Sources/OpenNotchKit/LauncherStore.swift` (migrate onto storage)
- Create: `Tests/OpenNotchKitTests/PluginStorageTests.swift`
- Modify: `Sources/OpenNotch/AppDelegate.swift` (implement `storage(for:)`)

**Interfaces:**
- Consumes: `PluginHost`.
- Produces:
  - `protocol PluginStorage: AnyObject { func data(forKey:) -> Data?; func set(_ data: Data?, forKey:); func stringArray(forKey:) -> [String]?; func set(_ arr: [String]?, forKey:) }`
  - `final class UserDefaultsPluginStorage: PluginStorage` — prefixes every key with `"plugin.\(pluginId)."`.
  - `PluginHost` gains `func storage(for pluginId: String) -> PluginStorage`.
  - `LauncherStore.init` gains `storage: PluginStorage? = nil` — when provided, reads/writes `bundleIds` through it (key `"bundleIds"` inside the launcher plugin's namespace) instead of raw `UserDefaults`. Default `nil` preserves current behavior.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/PluginStorageTests.swift`:

```swift
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
    s.set(nil, forKey: "blob")
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PluginStorage`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement `PluginStorage`**

Create `Sources/OpenNotchKit/PluginStorage.swift`:

```swift
import Foundation

/// Per-plugin key-value store. Keys are namespaced by plugin id so plugins
/// can't read or clobber each other's data.
public protocol PluginStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func stringArray(forKey key: String) -> [String]?
    func set(_ array: [String]?, forKey key: String)
}

public final class UserDefaultsPluginStorage: PluginStorage {
    private let defaults: UserDefaults
    private let prefix: String
    public init(pluginId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefix = "plugin.\(pluginId)."
    }
    private func k(_ key: String) -> String { prefix + key }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: k(key)) }
    public func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: k(key)) }
    public func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: k(key)) }
    public func set(_ array: [String]?, forKey key: String) { defaults.set(array, forKey: k(key)) }
}
```

- [ ] **Step 4: Add `storage(for:)` to `PluginHost`**

In `Sources/OpenNotchKit/PluginAPI.swift`, add to the `PluginHost` protocol:

```swift
    func storage(for pluginId: String) -> PluginStorage
```

Give it a default so existing conformers/tests don't all break at once:

```swift
public extension PluginHost {
    func storage(for pluginId: String) -> PluginStorage {
        UserDefaultsPluginStorage(pluginId: pluginId)
    }
}
```

- [ ] **Step 5: Migrate `LauncherStore` onto storage**

In `Sources/OpenNotchKit/LauncherStore.swift`, add a storage-backed init path. Keep the existing `defaults`/`key` init for source compatibility, add:

```swift
    @ObservationIgnored private let storage: PluginStorage?

    public init(storage: PluginStorage, maxCount: Int = 3) {
        self.storage = storage
        self.defaults = .standard
        self.key = "bundleIds"
        self.maxCount = maxCount
        self.bundleIds = Array((storage.stringArray(forKey: "bundleIds") ?? []).prefix(maxCount))
    }
```

Add `storage = nil` to the existing designated init's stored-property setup, and change `save()`:

```swift
    private func save() {
        if let storage { storage.set(bundleIds, forKey: "bundleIds") }
        else { defaults.set(bundleIds, forKey: key) }
    }
```

(Make the existing `init(defaults:key:maxCount:)` set `self.storage = nil`.)

- [ ] **Step 6: Wire the app host**

In `Sources/OpenNotch/AppDelegate.swift`, add to `AppHost`:

```swift
    func storage(for pluginId: String) -> PluginStorage {
        UserDefaultsPluginStorage(pluginId: pluginId)
    }
```

And construct the launcher store through it — in `applicationDidFinishLaunching`, once `host` exists, build `LauncherStore(storage: host.storage(for: "cafe.notch.launcher"))`. (The property `launcherStore` is currently an instance-level `let`; change it to a `var` set after `host` is created, or build the host earlier. Keep the seed logic that adds Safari/Calendar on first run.)

- [ ] **Step 7: Run tests + build**

Run: `swift test --filter PluginStorage` → PASS (3).
Run: `swift build` → succeeds.

- [ ] **Step 8: Commit**

```bash
git add Sources/OpenNotchKit/PluginStorage.swift Sources/OpenNotchKit/PluginAPI.swift Sources/OpenNotchKit/LauncherStore.swift Sources/OpenNotch/AppDelegate.swift Tests/OpenNotchKitTests/PluginStorageTests.swift
git commit -m "feat(kit): per-plugin namespaced storage; LauncherStore migrates onto it"
```

---

### Task 7: Transient-event priority queue (pure kit logic; wiring deferred to M4)

**Files:**
- Create: `Sources/OpenNotchKit/EventQueue.swift`
- Create: `Tests/OpenNotchKitTests/EventQueueTests.swift`

**Interfaces:**
- Consumes: nothing (SwiftUI for `AnyView`).
- Produces:
  - `struct NotchEvent: Identifiable { let id: String; let priority: Int; let duration: TimeInterval; let view: AnyView }`
  - `final class EventQueue`:
    - `init(now: @escaping () -> Date = Date.init)` — injectable clock.
    - `func post(_ event: NotchEvent)` — records post time = `now()`.
    - `var current: NotchEvent?` — highest-priority event whose window `[postedAt, postedAt+duration)` contains `now()` and that isn't suppressed; ties broken by most-recent post.
    - `func setUserHolding(_ holding: Bool)` — while true (user hovering), `current` is suppressed (returns nil) so the user's interaction wins; auto-expiry clock is paused.
  - **No host wiring, no panel rendering in M3.** `ponytail:` note in the file: "M4 wires `PluginHost.post(event:)` and the panel expansion render — no consumer exists yet."

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/EventQueueTests.swift`:

```swift
import Testing
import Foundation
import SwiftUI
@testable import OpenNotchKit

private func ev(_ id: String, priority: Int, duration: TimeInterval) -> NotchEvent {
    NotchEvent(id: id, priority: priority, duration: duration, view: AnyView(EmptyView()))
}

@MainActor @Test func currentReturnsPostedEventWithinWindow() {
    var t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("a", priority: 1, duration: 5))
    #expect(q.current?.id == "a")
    t = Date(timeIntervalSince1970: 1006)   // window elapsed
    #expect(q.current == nil)
}

@MainActor @Test func higherPriorityWins() {
    let t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("low", priority: 1, duration: 10))
    q.post(ev("high", priority: 5, duration: 10))
    #expect(q.current?.id == "high")
}

@MainActor @Test func userHoldingSuppressesCurrent() {
    let t = Date(timeIntervalSince1970: 1000)
    let q = EventQueue(now: { t })
    q.post(ev("a", priority: 1, duration: 10))
    q.setUserHolding(true)
    #expect(q.current == nil)               // user interaction wins
    q.setUserHolding(false)
    #expect(q.current?.id == "a")           // resumes (clock was paused)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventQueue`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/EventQueue.swift`:

```swift
import Foundation
import SwiftUI

/// A transient island-style alert a plugin asks the host to show (charge started,
/// meeting in 5 min). Priority breaks contention; duration bounds visibility.
public struct NotchEvent: Identifiable {
    public let id: String
    public let priority: Int
    public let duration: TimeInterval
    public let view: AnyView
    public init(id: String, priority: Int, duration: TimeInterval, view: AnyView) {
        self.id = id
        self.priority = priority
        self.duration = duration
        self.view = view
    }
}

/// Arbitrates transient events so plugins can't fight over the notch. Pure logic:
/// the clock is injected and `current` is a computed decision, not a timer.
///
/// ponytail: M3 builds the arbitration only (the risky part). M4 wires
/// `PluginHost.post(event:)` and the panel expansion render — no consumer exists yet.
@MainActor public final class EventQueue {
    private struct Entry { let event: NotchEvent; let postedAt: Date; let seq: Int }
    private let now: () -> Date
    private var entries: [Entry] = []
    private var seq = 0
    private var holding = false
    private var heldAt: Date?

    public init(now: @escaping () -> Date = Date.init) { self.now = now }

    public func post(_ event: NotchEvent) {
        seq += 1
        entries.append(Entry(event: event, postedAt: now(), seq: seq))
    }

    /// While the user is interacting, expiry pauses (heldAt "freezes the clock")
    /// so an event doesn't silently expire behind the user's hover.
    public func setUserHolding(_ holding: Bool) {
        if holding, !self.holding { heldAt = now() }
        else if !holding, self.holding, let held = heldAt {
            // Shift every post forward by the paused interval.
            let delta = now().timeIntervalSince(held)
            entries = entries.map { Entry(event: $0.event, postedAt: $0.postedAt.addingTimeInterval(delta), seq: $0.seq) }
            heldAt = nil
        }
        self.holding = holding
    }

    public var current: NotchEvent? {
        guard !holding else { return nil }
        let t = now()
        return entries
            .filter { t >= $0.postedAt && t < $0.postedAt.addingTimeInterval($0.event.duration) }
            .sorted { ($0.event.priority, $0.seq) > ($1.event.priority, $1.seq) }
            .first?.event
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EventQueue`
Expected: PASS (3).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/EventQueue.swift Tests/OpenNotchKitTests/EventQueueTests.swift
git commit -m "feat(kit): transient-event priority queue (arbitration only; M4 wires it)"
```

---

### Task 8: Widget grid layout engine

**Files:**
- Create: `Sources/OpenNotchKit/WidgetLayout.swift`
- Create: `Tests/OpenNotchKitTests/WidgetLayoutTests.swift`

**Interfaces:**
- Consumes: `WidgetSize`.
- Produces:
  - `struct LaidOutWidget: Equatable { let id: String; let row: Int; let column: Int; let columnSpan: Int }`
  - `enum WidgetLayout { static func arrange(_ widgets: [(id: String, size: WidgetSize)], columns: Int) -> [LaidOutWidget] }` — fills a grid left-to-right, top-to-bottom; `.wide` spans all `columns`, `.medium` spans 2 (capped at `columns`), `.small` spans 1; a widget that doesn't fit the current row wraps to the next. Input order is the user-configurable order (already applied by the runtime).

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/WidgetLayoutTests.swift`:

```swift
import Testing
@testable import OpenNotchKit

@Test func wideWidgetSpansAllColumns() {
    let out = WidgetLayout.arrange([("media", .wide)], columns: 4)
    #expect(out == [LaidOutWidget(id: "media", row: 0, column: 0, columnSpan: 4)])
}

@Test func smallWidgetsPackLeftToRightThenWrap() {
    let out = WidgetLayout.arrange(
        [("a", .small), ("b", .small), ("c", .small)], columns: 2)
    #expect(out == [
        LaidOutWidget(id: "a", row: 0, column: 0, columnSpan: 1),
        LaidOutWidget(id: "b", row: 0, column: 1, columnSpan: 1),
        LaidOutWidget(id: "c", row: 1, column: 0, columnSpan: 1),
    ])
}

@Test func mediumThatDoesNotFitWraps() {
    let out = WidgetLayout.arrange(
        [("a", .small), ("b", .medium)], columns: 2)
    // 'a' takes col 0; 'b' needs span 2 but only 1 left → wraps to row 1.
    #expect(out == [
        LaidOutWidget(id: "a", row: 0, column: 0, columnSpan: 1),
        LaidOutWidget(id: "b", row: 1, column: 0, columnSpan: 2),
    ])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WidgetLayout`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/WidgetLayout.swift`:

```swift
/// A widget placed on the expanded panel's grid.
public struct LaidOutWidget: Equatable {
    public let id: String
    public let row: Int
    public let column: Int
    public let columnSpan: Int
    public init(id: String, row: Int, column: Int, columnSpan: Int) {
        self.id = id; self.row = row; self.column = column; self.columnSpan = columnSpan
    }
}

/// Pure grid packing for the expanded panel. No geometry — the view maps
/// (row, column, span) to points. Input order is the user's widget order.
public enum WidgetLayout {
    private static func span(_ s: WidgetSize, columns: Int) -> Int {
        switch s {
        case .wide: return columns
        case .medium: return min(2, columns)
        case .small: return 1
        }
    }

    public static func arrange(_ widgets: [(id: String, size: WidgetSize)], columns: Int) -> [LaidOutWidget] {
        guard columns > 0 else { return [] }
        var out: [LaidOutWidget] = []
        var row = 0, col = 0
        for w in widgets {
            let s = span(w.size, columns: columns)
            if col + s > columns {          // doesn't fit → wrap
                row += 1; col = 0
            }
            out.append(LaidOutWidget(id: w.id, row: row, column: col, columnSpan: s))
            col += s
            if col >= columns { row += 1; col = 0 }
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WidgetLayout`
Expected: PASS (3).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/WidgetLayout.swift Tests/OpenNotchKitTests/WidgetLayoutTests.swift
git commit -m "feat(kit): widget grid layout engine"
```

---

### Task 9: Runtime enable/disable + merge first-party & third-party + per-plugin settings

**Files:**
- Modify: `Sources/OpenNotchKit/PluginAPI.swift` (add `settingsPane()` to `NotchPlugin`)
- Modify: `Sources/OpenNotchKit/PluginRuntime.swift`
- Modify: `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`

**Interfaces:**
- Consumes: `NotchPlugin`, `PluginStorage`, `WidgetLayout`.
- Produces:
  - `NotchPlugin` gains `func settingsPane() -> AnyView?` (default `nil` in the protocol extension).
  - `PluginRuntime`:
    - New init: `init(host:, plugins: [NotchPlugin], enabledStore: PluginStorage? = nil)` — persists enabled/disabled by plugin id (a disabled-ids list in storage under key `"disabledPluginIds"`).
    - `func setEnabled(_ id: String, _ enabled: Bool)` — persists + `reload()`.
    - `func isEnabled(_ id: String) -> Bool`.
    - `func add(_ plugins: [NotchPlugin])` — append loaded third-party plugins, then `reload()` (merges into the single list).
    - `var pluginSummaries: [(id: String, name: String, enabled: Bool, hasSettings: Bool)]` — for the Settings tab.
    - `func settingsPane(for id: String) -> AnyView?`.
    - `reload()` now filters out disabled ids and (still) sorts widgets; keep existing `compactLeading`/`compactTrailing`/`quickActions` but skip disabled plugins.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/OpenNotchKitTests/PluginRuntimeTests.swift` (reuse the file's existing stub host/plugins; if it has a `StubPlugin`, extend that pattern):

```swift
@MainActor @Test func disabledPluginProducesNoWidgets() {
    let host = FakeHost(np: StubNowPlaying())
    let rt = PluginRuntime(host: host, plugins: [EchoPlugin(host: host)])
    #expect(rt.widgets.count == 1)
    rt.setEnabled("echo", false)
    #expect(rt.widgets.isEmpty)
    #expect(rt.isEnabled("echo") == false)
}

@MainActor @Test func enabledStatePersistsAcrossRuntimes() {
    let store = UserDefaultsPluginStorage(pluginId: "runtime",
        defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!)
    let host = FakeHost(np: StubNowPlaying())
    PluginRuntime(host: host, plugins: [EchoPlugin(host: host)], enabledStore: store)
        .setEnabled("echo", false)
    let rt2 = PluginRuntime(host: host, plugins: [EchoPlugin(host: host)], enabledStore: store)
    #expect(rt2.isEnabled("echo") == false)
    #expect(rt2.widgets.isEmpty)
}

@MainActor @Test func addMergesThirdPartyPlugins() {
    let host = FakeHost(np: StubNowPlaying())
    let rt = PluginRuntime(host: host, plugins: [])
    rt.add([EchoPlugin(host: host)])
    #expect(rt.pluginSummaries.contains { $0.id == "echo" })
    #expect(rt.widgets.count == 1)
}
```

(If `EchoPlugin`/`FakeHost`/`StubNowPlaying` were left in `PluginBoxTests.swift`, promote them to a shared `Tests/OpenNotchKitTests/TestDoubles.swift` so both files use them — DRY. Do this promotion as the first move in this task if needed.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PluginRuntime`
Expected: FAIL — new API not defined.

- [ ] **Step 3: Add `settingsPane()` to the protocol**

In `Sources/OpenNotchKit/PluginAPI.swift`, add to `NotchPlugin`:

```swift
    func settingsPane() -> AnyView?
```

and to its extension:

```swift
    func settingsPane() -> AnyView? { nil }
```

- [ ] **Step 4: Rewrite `PluginRuntime`**

Replace `Sources/OpenNotchKit/PluginRuntime.swift`:

```swift
import SwiftUI

@MainActor public final class PluginRuntime {
    private let host: PluginHost
    private var plugins: [NotchPlugin]
    private let enabledStore: PluginStorage?
    private var disabledIds: Set<String>
    public private(set) var widgets: [PluginWidget] = []

    public init(host: PluginHost, plugins: [NotchPlugin], enabledStore: PluginStorage? = nil) {
        self.host = host
        self.plugins = plugins
        self.enabledStore = enabledStore
        self.disabledIds = Set(enabledStore?.stringArray(forKey: "disabledPluginIds") ?? [])
        reload()
    }

    /// Merge loaded third-party plugins into the single list.
    public func add(_ newPlugins: [NotchPlugin]) {
        plugins.append(contentsOf: newPlugins)
        reload()
    }

    public func isEnabled(_ id: String) -> Bool { !disabledIds.contains(id) }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabledIds.remove(id) } else { disabledIds.insert(id) }
        enabledStore?.set(Array(disabledIds), forKey: "disabledPluginIds")
        reload()
    }

    private var activePlugins: [NotchPlugin] {
        plugins.filter { isEnabled(type(of: $0).manifest.id) }
    }

    public func reload() {
        widgets = activePlugins.flatMap { $0.widgets() }
            .enumerated()
            .sorted { (rank($0.element.size), $0.offset) < (rank($1.element.size), $1.offset) }
            .map(\.element)
    }

    private func rank(_ s: WidgetSize) -> Int {
        switch s { case .wide: 0; case .medium: 1; case .small: 2 }
    }

    public var compactLeading: [AnyView] { activePlugins.compactMap { $0.compactLeading() } }
    public var compactTrailing: [AnyView] { activePlugins.compactMap { $0.compactTrailing() } }
    public var quickActions: [QuickAction] { activePlugins.flatMap { $0.quickActions() } }

    // MARK: Settings surface

    public var pluginSummaries: [(id: String, name: String, enabled: Bool, hasSettings: Bool)] {
        plugins.map {
            let m = type(of: $0).manifest
            return (m.id, m.name, isEnabled(m.id), $0.settingsPane() != nil)
        }
    }

    public func settingsPane(for id: String) -> AnyView? {
        plugins.first { type(of: $0).manifest.id == id }?.settingsPane() ?? nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PluginRuntime` → PASS.
Run: `swift build` → succeeds (existing widget-layout consumers unaffected).

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotchKit/PluginAPI.swift Sources/OpenNotchKit/PluginRuntime.swift Tests/OpenNotchKitTests/
git commit -m "feat(kit): runtime enable/disable, third-party merge, per-plugin settings hook"
```

---

### Task 10: Panel uses the layout engine

**Files:**
- Modify: `Sources/OpenNotch/NotchShell.swift`
- (Manual DoD — SwiftUI view code.)

**Interfaces:**
- Consumes: `PluginRuntime.widgets`, `WidgetLayout.arrange`.
- Produces: the expanded panel arranges `runtime.widgets` via `WidgetLayout.arrange(..., columns: N)` into a grid instead of assuming a single wide widget. With the current single wide media widget the output is visually unchanged (one full-width row).

- [ ] **Step 1: Read the current widget rendering**

Run: `grep -n "widgets\|ForEach\|PluginWidget" Sources/OpenNotch/NotchShell.swift`
Identify where `runtime.widgets` is rendered in the expanded panel.

- [ ] **Step 2: Replace the render with a grid driven by `WidgetLayout`**

Map `runtime.widgets` to `[(id, size)]`, call `WidgetLayout.arrange(pairs, columns: 4)`, group by `row`, render rows as `HStack`s; within a row lay each widget with a width proportional to `columnSpan / columns` of the content area. A `.wide` widget (span 4) fills the row — preserving today's look. Keep the existing padding constants.

```swift
// Sketch — adapt to the existing NotchShell structure/state:
let laid = WidgetLayout.arrange(runtime.widgets.map { ($0.id, $0.size) }, columns: 4)
let byRow = Dictionary(grouping: laid, by: \.row).sorted { $0.key < $1.key }
VStack(spacing: 8) {
    ForEach(byRow, id: \.key) { _, cells in
        HStack(spacing: 8) {
            ForEach(cells, id: \.id) { cell in
                if let w = runtime.widgets.first(where: { $0.id == cell.id }) {
                    w.content.frame(maxWidth: .infinity)   // span handled by cell count/weight
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build + run, verify the panel looks unchanged**

Run: `swift build && swift run OpenNotch`
Hover the notch, click to expand. The media widget should render as before (full-width). No layout regressions.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenNotch/NotchShell.swift
git commit -m "feat: expanded panel renders widgets through the layout engine"
```

---

### Task 11: Settings — Plugins tab

**Files:**
- Modify: `Sources/OpenNotch/SettingsWindow.swift`
- (Manual DoD — SwiftUI view code.)

**Interfaces:**
- Consumes: `PluginRuntime.pluginSummaries`, `setEnabled`, `settingsPane(for:)`; `PluginBlocklist.blocked` + `unblock`; a way to uninstall a third-party `.notchplugin` (delete its directory).
- Produces: a `PluginsTab` added to the Settings `TabView`: a list of installed plugins (name + enable/disable toggle), blocklist status with an "Unblock" button per blocked id, an "Uninstall" action for third-party plugins (deletes the folder + calls back to reload), and a disclosure/sheet showing a plugin's `settingsPane()` when it has one.

- [ ] **Step 1: Add the tab and thread dependencies**

`SettingsView` currently takes `store` + `installedApps`. Add the `runtime` (or a lightweight view-model exposing `pluginSummaries`, `setEnabled`, `settingsPane(for:)`), the `blocklist`, and an `onUninstall: (String) -> Void` closure. Thread them from `SettingsWindowController.show(...)` and `AppDelegate.openSettings()`.

- [ ] **Step 2: Implement `PluginsTab`**

```swift
private struct PluginsTab: View {
    let runtime: PluginRuntime
    let blockedIds: [String]
    let onUnblock: (String) -> Void
    let onUninstall: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !blockedIds.isEmpty {
                GroupBox("Blocked (crashed on load)") {
                    ForEach(blockedIds, id: \.self) { id in
                        HStack {
                            Text(id).font(.callout)
                            Spacer()
                            Button("Unblock") { onUnblock(id) }
                        }
                    }
                }
            }
            List(runtime.pluginSummaries, id: \.id) { p in
                HStack {
                    Toggle(p.name, isOn: Binding(
                        get: { p.enabled },
                        set: { runtime.setEnabled(p.id, $0) }))
                    Spacer()
                    if p.hasSettings, let pane = runtime.settingsPane(for: p.id) {
                        SettingsDisclosure(pane: pane)
                    }
                    // Uninstall only for third-party (first-party ids start with "cafe.notch.").
                    if !p.id.hasPrefix("cafe.notch.") {
                        Button(role: .destructive) { onUninstall(p.id) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct SettingsDisclosure: View {
    let pane: AnyView
    @State private var open = false
    var body: some View {
        Button("Settings…") { open = true }
            .popover(isPresented: $open) { pane.padding() }
    }
}
```

Add `PluginsTab(...)` to `SettingsView.body`'s `TabView` with `.tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }`.

- [ ] **Step 3: Build + run, verify the tab**

Run: `swift build && swift run OpenNotch`, open Settings → Plugins. Confirm Media + App Launcher appear, toggling disable removes the media widget from the panel (reopen the notch), and no blocked/uninstall entries show for first-party plugins.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenNotch/SettingsWindow.swift Sources/OpenNotch/AppDelegate.swift
git commit -m "feat: Settings Plugins tab (enable/disable, blocklist, uninstall, per-plugin settings)"
```

---

### Task 12: Wire the loader + blocklist + folder watch into the app

**Files:**
- Modify: `Sources/OpenNotch/AppDelegate.swift`
- Create: `Sources/OpenNotch/PluginsFolder.swift` (folder path + quarantine strip + FSEvents/DispatchSource watch)
- (Manual DoD.)

**Interfaces:**
- Consumes: `PluginLoader`, `PluginBlocklist`, `DefaultsMarkerStore`, `PluginRuntime.add`.
- Produces:
  - `PluginsFolder.url` = `~/Library/Application Support/OpenNotch/Plugins` (created if absent).
  - `PluginsFolder.stripQuarantine(_ dir: URL)` — runs `xattr -dr com.apple.quarantine <dir>` (defensive de-quarantine per the spike; the install path, so a Finder-launched host never hits a quarantined dylib).
  - `func loadInstalledPlugins(host:runtime:blocklist:) ` in AppDelegate — for each `*.notchplugin` in the folder not in `blocklist.blocked`: `stripQuarantine`, `blocklist.beginLoad(id)`, `try loader.load(...)`, on success `runtime.add([plugin])` + `blocklist.endLoad(id)`; on throw, log + leave the marker only if it was a hard crash (a thrown error is a clean failure → `endLoad` so it isn't permanently blocked; the marker's purpose is *crash* attribution, and a caught `throw` didn't crash).
  - A `DispatchSource` (or `FSEventStream`) on the folder that, on change, reloads *newly added* plugins (never unloads — dlopened code stays; log that updates need relaunch).

- [ ] **Step 1: Implement `PluginsFolder`**

```swift
import Foundation
import os

enum PluginsFolder {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("OpenNotch/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func stripQuarantine(_ dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", dir.path]
        try? p.run(); p.waitUntilExit()
    }

    /// Watch the folder; `onChange` fires on add/remove. Returns the source to retain.
    static func watch(_ onChange: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { onChange() }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }
}
```

- [ ] **Step 2: Wire loading + watching into `applicationDidFinishLaunching`**

After the runtime is built with the first-party plugins, add:

```swift
let blocklist = PluginBlocklist(store: DefaultsMarkerStore())
self.blocklist = blocklist
let loader = PluginLoader()
loadInstalledPlugins(host: host, runtime: runtime, loader: loader, blocklist: blocklist)
self.pluginWatch = PluginsFolder.watch { [weak self] in
    guard let self, let host = self.host, let runtime = self.runtime, let bl = self.blocklist else { return }
    self.loadInstalledPlugins(host: host, runtime: runtime, loader: loader, blocklist: bl)
}
```

`loadInstalledPlugins` (dedupe against already-loaded ids so a folder event doesn't double-load; never unload):

```swift
private var loadedPluginIds = Set<String>()
private func loadInstalledPlugins(host: AppHost, runtime: PluginRuntime,
                                  loader: PluginLoader, blocklist: PluginBlocklist) {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: PluginsFolder.url,
        includingPropertiesForKeys: nil) else { return }
    for dir in entries where dir.pathExtension == "notchplugin" {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? parsePluginManifest(data),
              !loadedPluginIds.contains(manifest.id),
              !blocklist.blocked.contains(manifest.id) else { continue }
        PluginsFolder.stripQuarantine(dir)
        blocklist.beginLoad(manifest.id)
        do {
            let plugin = try loader.load(pluginDirectory: dir, host: host)
            runtime.add([plugin])
            loadedPluginIds.insert(manifest.id)
            blocklist.endLoad(manifest.id)
            log.info("loaded plugin \(manifest.id)")
        } catch {
            blocklist.endLoad(manifest.id)   // clean failure, not a crash
            log.error("failed to load \(manifest.id): \(String(describing: error))")
        }
    }
    // Reopening the notch shows new widgets; DisplayCoordinator observes runtime.
}
```

Add stored properties `private var blocklist: PluginBlocklist?` and `private var pluginWatch: DispatchSourceFileSystemObject?`.

- [ ] **Step 3: Manual verification with the template plugin**

Deferred to Task 13's DoD (needs the SDK template to produce a real `.notchplugin`). For now confirm the app builds and launches with an **empty** Plugins folder (no crash, no plugins loaded).

Run: `swift build && swift run OpenNotch` → launches clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenNotch/PluginsFolder.swift Sources/OpenNotch/AppDelegate.swift
git commit -m "feat: load .notchplugin bundles from Application Support with blocklist + folder watch"
```

---

### Task 13: SDK — library product + plugin template + author contract test

**Files:**
- Modify: `Package.swift` (expose `OpenNotchKit` as a `library` product)
- Create: `Templates/PluginTemplate/manifest.json`
- Create: `Templates/PluginTemplate/Sources/WeatherPlugin/WeatherPlugin.swift`
- Create: `Templates/PluginTemplate/Package.swift`
- Create: `Templates/PluginTemplate/build.sh` (produces a `.notchplugin`)
- Create: `Templates/PluginTemplate/README.md`
- Modify: `Tests/OpenNotchKitTests/` — add the "imports only SwiftUI" contract test if not already present.

**Interfaces:**
- Consumes: `NotchPlugin`, `PluginBox`, `pluginEntryPointName`, `hostFromPointer`, `PluginManifest`.
- Produces: an installable, buildable example plugin proving the whole loop end-to-end; `OpenNotchKit` importable as an SPM dependency.

- [ ] **Step 1: Expose `OpenNotchKit` as a library product**

In `Package.swift`, add a `products:` section:

```swift
    products: [
        .library(name: "OpenNotchKit", targets: ["OpenNotchKit"]),
    ],
```

Run `swift build` to confirm no regression.

- [ ] **Step 2: Write the template plugin source (the box-ABI entry point)**

Create `Templates/PluginTemplate/Sources/WeatherPlugin/WeatherPlugin.swift`:

```swift
import SwiftUI
import OpenNotchKit

@MainActor struct WeatherPlugin: NotchPlugin {
    static let manifest = PluginManifest(
        id: "com.example.weather", name: "Weather", version: "1.0.0",
        author: "Example", apiVersion: "1.0.0", bundleName: "WeatherPlugin.bundle")
    let host: PluginHost
    init(host: PluginHost) { self.host = host }
    func widgets() -> [PluginWidget] {
        [PluginWidget(id: "weather", size: .small,
            content: AnyView(Label("72°", systemImage: "sun.max.fill").padding(8)))]
    }
}

/// The one required entry point. The SDK's helpers do the pointer dance.
@_cdecl("opennotch_plugin_create")
public func opennotch_plugin_create(_ hostPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    MainActor.assumeIsolated {
        let host = hostFromPointer(hostPtr)
        return Unmanaged.passRetained(PluginBox(WeatherPlugin(host: host))).toOpaque()
    }
}
```

- [ ] **Step 3: Template `Package.swift` + build script**

Create `Templates/PluginTemplate/Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WeatherPlugin",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Point at a tagged OpenNotchKit once published; local path for now:
        .package(path: "../..")
    ],
    targets: [
        .target(name: "WeatherPlugin", dependencies: [
            .product(name: "OpenNotchKit", package: "mac-notch")
        ])
    ]
)
```

Create `Templates/PluginTemplate/build.sh`:

```bash
#!/bin/bash
# Build WeatherPlugin.notchplugin from this template.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
OUT="WeatherPlugin.notchplugin"
BUNDLE="$OUT/WeatherPlugin.bundle/Contents/MacOS"
rm -rf "$OUT"; mkdir -p "$BUNDLE"
cp .build/release/libWeatherPlugin.dylib "$BUNDLE/WeatherPlugin"
cp manifest.json "$OUT/manifest.json"
echo "Built $OUT — copy it to ~/Library/Application Support/OpenNotch/Plugins/"
```

`chmod +x Templates/PluginTemplate/build.sh`. Create `Templates/PluginTemplate/manifest.json` mirroring the plugin's manifest, and a `README.md` documenting: the entry point, the `import SwiftUI + OpenNotchKit` only rule, and "updates require an app relaunch (dlopened code is never unloaded)".

- [ ] **Step 4: Add / confirm the "imports only SwiftUI" contract test**

Check whether a test already asserts plugin-facing kit files don't import AppKit (`grep -rn "AppKit" Tests/`). If not, add `Tests/OpenNotchKitTests/PluginImportContractTests.swift`:

```swift
import Testing
import Foundation

/// The keystone contract: plugin-visible kit files import only SwiftUI/Foundation,
/// never AppKit — so a plugin author never needs AppKit.
@Test func pluginFacingKitFilesDoNotImportAppKit() throws {
    let kit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/OpenNotchKit")
    let files = ["PluginAPI.swift", "PluginBox.swift", "EventQueue.swift", "WidgetLayout.swift"]
    for f in files {
        let src = try String(contentsOf: kit.appendingPathComponent(f), encoding: .utf8)
        #expect(!src.contains("import AppKit"), "\(f) must not import AppKit")
    }
}
```

- [ ] **Step 5: Build the template plugin and load it end-to-end (manual DoD)**

```bash
cd Templates/PluginTemplate && ./build.sh
cp -R WeatherPlugin.notchplugin ~/Library/Application\ Support/OpenNotch/Plugins/
cd ../.. && swift run OpenNotch
```
Expand the notch → the Weather widget appears alongside Media. Open Settings → Plugins → Weather is listed, toggling it off removes the widget. Confirm the `swift test` contract test passes.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Templates/PluginTemplate Tests/OpenNotchKitTests/PluginImportContractTests.swift
git commit -m "feat: OpenNotchKit SDK library product + plugin template + import contract test"
```

---

## Full test run + manual DoD

- [ ] **Run the whole suite:** `swift test` — expect all prior 56 tests + the new kit tests green.
- [ ] **Build the app bundle:** `./Scripts/make-app.sh` → `build/OpenNotch.app` launches.

### Risk #2 (shared runtime) — discovered during T13, RESOLVED

A kit-linked plugin was statically embedding its own `OpenNotchKit`, so `dlopen`
gave two copies and the host↔plugin `as! PluginHost` cast crashed. **Fixed via
`dynamic_lookup`** (owner-approved): the host exports its symbols
(`-export_dynamic`) and the plugin links with `-undefined dynamic_lookup` (no
embedded kit), binding to the host at load. Verified end-to-end in the dev build —
real template plugin loads with 0 duplicate-class warnings and no crash. Details:
`docs/superpowers/spikes/2026-07-07-m3-risk2-shared-runtime.md`.

### Definition of Done (M3) — walk on hardware

1. **Loader:** template `.notchplugin` in `~/Library/Application Support/OpenNotch/Plugins/` loads on launch; its widget renders in the expanded panel. *(Proven in the dev build; confirm once in the packaged `.app` — see risk #2 doc's on-device check.)*
2. **Quarantine:** launch the **bundled `OpenNotch.app` from Finder**, drop a freshly-downloaded (still-quarantined) plugin into the folder → strip-on-install clears it and it loads (the one behavior the Terminal spike couldn't cover — see the spike doc's caveat).
3. **API gate:** a plugin with `apiVersion` major ≠ host is refused and shown with a reason in Settings → Plugins.
4. **Blocklist:** a plugin that crashes during construct is skipped on next launch and appears as Blocked with a working Unblock action.
5. **Enable/disable:** toggling a plugin off in Settings removes its widgets; state survives relaunch.
6. **Folder watch:** dropping a new plugin into the folder loads it without relaunch; replacing an existing one logs "relaunch required" and does not hot-swap.
7. **Layout:** with two+ widgets, the grid arranges them; the single-media case looks unchanged.
8. **SDK:** `Templates/PluginTemplate/build.sh` produces a loadable `.notchplugin` against the published `OpenNotchKit` product.

---

## Deferred to M4 (built as pure kit logic here, wired when a consumer exists)

- **`events` host wiring + panel expansion render** — `EventQueue` (Task 7) is done and tested; M4's calendar/battery plugins are the first posters. Add `PluginHost.post(event:)` and the panel's transient-expansion view then.
- **Permission-gated capabilities** (calendar/EventKit, IOKit power) — declared in the manifest, surfaced in Settings, handed to the plugin only if granted. First consumer is M4's Calendar plugin.
- **Plugin-author guide** (long-form) — the template README stubs it; the full guide is an M5 deliverable.

---

## Self-review notes (done during planning)

- **Spec coverage:** package format + loader (T1–T5), apiVersion gate (T2), blocklist (T3), folder watch (T12), storage + LauncherStore migration (T6), events arbitration (T7, wiring deferred per spec YAGNI), settings pane (T9/T11), enable/disable + merge (T9), layout engine (T8/T10), Plugins tab (T11), SDK product + template + keystone test (T13). Permission-gated capabilities are M4-consumer-gated (noted above), matching the spec's "grow as M4 demands".
- **Type consistency:** `pluginEntryPointName`, `PluginCreateFn`, `PluginBox`, `hostPointer`/`hostFromPointer`/`pluginFromBoxPointer` are defined in T4 and consumed unchanged in T5/T13. `PluginStorage` (T6) is consumed by `PluginRuntime` (T9) and `LauncherStore` (T6). `WidgetLayout`/`LaidOutWidget` (T8) consumed in T10.
- **Placeholders:** none — every code step carries full code; app/UI tasks (T10–T12) are manual-DoD with concrete sketches against the real files.
