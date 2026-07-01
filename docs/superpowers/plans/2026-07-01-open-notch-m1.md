# OpenNotch Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that turns the notch into a hover-to-expand panel, showing a working now-playing media widget built entirely through a public plugin API.

**Architecture:** A Swift Package with two targets. `OpenNotchKit` (library) holds the pure, test-first logic core: notch geometry math, now-playing parsing, the expand/collapse state machine, the plugin API contract, and the plugin runtime. `OpenNotch` (executable) holds the AppKit/SwiftUI glue: the floating `NSPanel` overlay, the SwiftUI shell, and the `MediaRemote` bridge. The media feature is a plugin that touches only the public API — it never sees `MediaRemote`.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI + AppKit (macOS 14+), Swift Testing, the `mediaremote-adapter` (perl) technique for now-playing access.

## Global Constraints

- **Platform:** macOS 14.0+ (`// swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`).
- **The media plugin gets zero privileges.** `MediaPlugin` and `NowPlayingView` live in code that has NO access to `MediaRemote` or host internals — only the public `PluginHost` / `NowPlayingService`. Enforced by the keystone test (Task 9): it compiles against public API only.
- **Logic core is pure.** `OpenNotchKit` imports no AppKit/SwiftUI-window APIs (SwiftUI `View` types are allowed for widget content; window/NSPanel/MediaRemote are not). It must build and test on its own via `swift test`.
- **No new third-party Swift dependencies.** Use stdlib + system frameworks. The perl adapter is vendored, not a SwiftPM dep.
- **TDD for the logic core; manual verification for window/rendering.** Tasks 3–9 are test-first. Tasks 10–12 are build + documented manual checklist (rendering can't be unit-tested sensibly).
- **Naming:** package/product/repo use `OpenNotch`; library target `OpenNotchKit`. Plugin ids are reverse-DNS (`cafe.notch.*`).

---

### Task 1: MediaRemote spike (THROWAWAY — not test-first)

This is a deliberate spike to retire the #1 risk before building anything. It is throwaway; its only durable output is (a) a go/no-go answer and (b) a recorded sample of real adapter output saved as a test fixture for Task 5.

**Files:**
- Create: `spike/README.md` (findings)
- Create: `Tests/OpenNotchKitTests/Fixtures/nowplaying-sample.jsonl` (captured real output — used by Task 5)
- Vendor: `vendor/mediaremote-adapter/` (clone of the adapter)

- [ ] **Step 1: Vendor the adapter**

```bash
mkdir -p vendor
git clone --depth 1 https://github.com/ungive/mediaremote-adapter vendor/mediaremote-adapter
ls vendor/mediaremote-adapter
```
Expected: repo contents including the perl script and the `MediaRemoteAdapter.framework` (or build instructions for it). Read that repo's README for the exact invocation — it is the source of truth for the command strings below.

- [ ] **Step 2: Stream now-playing while music plays**

Start playing something in Apple Music or Spotify, then run the adapter's stream command (exact path/args per its README, typically):
```bash
perl vendor/mediaremote-adapter/bin/mediaremote-adapter.pl \
  vendor/mediaremote-adapter/MediaRemoteAdapter.framework stream
```
Expected: JSON lines streaming to stdout with fields like `title`, `artist`, `album`, `elapsedTime`, `duration`, `playbackRate`, `artworkData`. Copy 3–5 representative lines (playing, paused, track change) into `Tests/OpenNotchKitTests/Fixtures/nowplaying-sample.jsonl`.

- [ ] **Step 3: Send transport commands**

```bash
perl vendor/mediaremote-adapter/bin/mediaremote-adapter.pl \
  vendor/mediaremote-adapter/MediaRemoteAdapter.framework send togglePlayPause
```
Try `send nextTrack`, `send previousTrack`, `send play`, `send pause`. Expected: playback actually changes. Record the exact working command strings in `spike/README.md`.

- [ ] **Step 4: Record findings & decide**

Write `spike/README.md`: exact stream command, exact send commands, the real JSON field names/shape observed, whether artwork arrives and in what encoding, and any latency. **Go/no-go:** if read + play/pause/next all work, proceed. If not, STOP and revisit the design (the media plugin's capabilities change).

- [ ] **Step 5: Commit**

```bash
git add vendor spike Tests/OpenNotchKitTests/Fixtures/nowplaying-sample.jsonl
git commit -m "spike: verify MediaRemote now-playing via perl adapter"
```

---

### Task 2: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/OpenNotchKit/OpenNotchKit.swift` (placeholder)
- Create: `Sources/OpenNotch/main.swift`
- Create: `Tests/OpenNotchKitTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: package with library target `OpenNotchKit`, executable target `OpenNotch` (depends on `OpenNotchKit`), test target `OpenNotchKitTests`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OpenNotchKit"),
        .executableTarget(name: "OpenNotch", dependencies: ["OpenNotchKit"]),
        .testTarget(name: "OpenNotchKitTests", dependencies: ["OpenNotchKit"],
                    resources: [.copy("Fixtures")]),
    ]
)
```

- [ ] **Step 2: Placeholder library + `.gitignore`**

`Sources/OpenNotchKit/OpenNotchKit.swift`:
```swift
public enum OpenNotchKit { public static let version = "0.1.0" }
```
`.gitignore`:
```
.build/
.swiftpm/
*.xcodeproj
```

- [ ] **Step 3: Minimal executable**

`Sources/OpenNotch/main.swift`:
```swift
import AppKit
import OpenNotchKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // agent app: no dock icon
print("OpenNotch \(OpenNotchKit.version) starting")
app.run()
```

- [ ] **Step 4: Smoke test**

`Tests/OpenNotchKitTests/SmokeTests.swift`:
```swift
import Testing
@testable import OpenNotchKit

@Test func versionIsSet() {
    #expect(OpenNotchKit.version == "0.1.0")
}
```
Add an empty `Tests/OpenNotchKitTests/Fixtures/.keep` if the fixture from Task 1 is absent, so `.copy("Fixtures")` resolves.

- [ ] **Step 5: Build & test**

Run: `swift build && swift test`
Expected: builds; 1 test passes. (`swift run OpenNotch` launches an accessory process — Ctrl-C to stop.)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "feat: scaffold OpenNotch SwiftPM package"
```

---

### Task 3: NotchGeometry (pure, TDD)

**Files:**
- Create: `Sources/OpenNotchKit/NotchGeometry.swift`
- Test: `Tests/OpenNotchKitTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct NotchMetrics: Equatable {
      public let anchorRect: CGRect   // collapsed notch/pill rect in screen coords
      public let hasNotch: Bool
  }
  public enum NotchGeometry {
      // topInset == 0 → notch-less → centered pill of fallbackPillSize
      public static func metrics(screenFrame: CGRect, topInset: CGFloat,
                                 notchWidth: CGFloat,
                                 fallbackPillSize: CGSize) -> NotchMetrics
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import CoreGraphics
@testable import OpenNotchKit

@Test func notchPresentCentersOnTopInset() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let m = NotchGeometry.metrics(screenFrame: screen, topInset: 37,
                                  notchWidth: 200, fallbackPillSize: .init(width: 180, height: 32))
    #expect(m.hasNotch)
    #expect(m.anchorRect.width == 200)
    #expect(m.anchorRect.height == 37)
    #expect(m.anchorRect.midX == screen.midX)
    #expect(m.anchorRect.maxY == screen.maxY) // pinned to top
}

@Test func notchlessFallsBackToCenteredPill() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let m = NotchGeometry.metrics(screenFrame: screen, topInset: 0,
                                  notchWidth: 200, fallbackPillSize: .init(width: 180, height: 32))
    #expect(!m.hasNotch)
    #expect(m.anchorRect.size == CGSize(width: 180, height: 32))
    #expect(m.anchorRect.midX == screen.midX)
    #expect(m.anchorRect.maxY == screen.maxY)
}
```

- [ ] **Step 2: Run — verify fail**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL — `NotchGeometry` not found.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

public struct NotchMetrics: Equatable {
    public let anchorRect: CGRect
    public let hasNotch: Bool
}

public enum NotchGeometry {
    public static func metrics(screenFrame: CGRect, topInset: CGFloat,
                               notchWidth: CGFloat,
                               fallbackPillSize: CGSize) -> NotchMetrics {
        let hasNotch = topInset > 0
        let size = hasNotch ? CGSize(width: notchWidth, height: topInset) : fallbackPillSize
        let origin = CGPoint(x: screenFrame.midX - size.width / 2,
                             y: screenFrame.maxY - size.height)
        return NotchMetrics(anchorRect: CGRect(origin: origin, size: size), hasNotch: hasNotch)
    }
}
```

- [ ] **Step 4: Run — verify pass**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/NotchGeometry.swift Tests/OpenNotchKitTests/NotchGeometryTests.swift
git commit -m "feat: notch geometry with notch-less pill fallback"
```

---

### Task 4: NowPlayingInfo model (pure, trivial)

**Files:**
- Create: `Sources/OpenNotchKit/NowPlayingInfo.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct NowPlayingInfo: Equatable, Sendable {
      public var title: String?
      public var artist: String?
      public var album: String?
      public var isPlaying: Bool
      public var elapsed: TimeInterval?
      public var duration: TimeInterval?
      public var artworkData: Data?        // raw bytes; NSImage(data:) handles JPEG or PNG
      public var artworkMimeType: String?
      public init(title: String? = nil, artist: String? = nil, album: String? = nil,
                  isPlaying: Bool = false, elapsed: TimeInterval? = nil,
                  duration: TimeInterval? = nil, artworkData: Data? = nil,
                  artworkMimeType: String? = nil)
  }
  ```
  > **Spike correction (Task 1):** artwork arrives as `artworkData` (base64) +
  > `artworkMimeType` and was observed as JPEG, not PNG — hence `artworkData`
  > (raw bytes), not `artworkPNG`.

- [ ] **Step 1: Implement the model**

Create `Sources/OpenNotchKit/NowPlayingInfo.swift` with exactly the struct above (memberwise `public init` filled in assigning each property).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds. (No test — it is a plain data holder; parsing is tested in Task 5.)

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenNotchKit/NowPlayingInfo.swift
git commit -m "feat: NowPlayingInfo model"
```

---

### Task 5: NowPlayingParser (pure, TDD)

Parses one line of adapter JSON into `NowPlayingInfo`. Field names below are the REAL names the Task 1 spike observed (see `spike/README.md` and the captured fixture). **`isPlaying` comes from the boolean `playing` key — NOT `playbackRate` (which is absent entirely when paused).**

**Files:**
- Create: `Sources/OpenNotchKit/NowPlayingParser.swift`
- Test: `Tests/OpenNotchKitTests/NowPlayingParserTests.swift`
- Uses: `Tests/OpenNotchKitTests/Fixtures/nowplaying-sample.jsonl` (from Task 1)

**Interfaces:**
- Produces:
  ```swift
  public enum NowPlayingParser {
      // returns nil for blank/malformed lines instead of throwing
      public static func parse(line: String) -> NowPlayingInfo?
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import OpenNotchKit

@Test func parsesPlayingTrack() {
    let line = #"{"title":"Song","artist":"Artist","album":"Album","elapsedTime":12.5,"duration":200,"playing":true}"#
    let info = NowPlayingParser.parse(line: line)
    #expect(info?.title == "Song")
    #expect(info?.artist == "Artist")
    #expect(info?.isPlaying == true)
    #expect(info?.elapsed == 12.5)
    #expect(info?.duration == 200)
}

@Test func playingFalseMeansPaused() {
    // Real adapter output: paused lines carry "playing":false and omit playbackRate entirely.
    let line = #"{"title":"S","playing":false}"#
    #expect(NowPlayingParser.parse(line: line)?.isPlaying == false)
}

@Test func malformedOrBlankReturnsNil() {
    #expect(NowPlayingParser.parse(line: "") == nil)
    #expect(NowPlayingParser.parse(line: "not json") == nil)
}
```

- [ ] **Step 2: Run — verify fail**

Run: `swift test --filter NowPlayingParserTests`
Expected: FAIL — `NowPlayingParser` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum NowPlayingParser {
    public static func parse(line: String) -> NowPlayingInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var info = NowPlayingInfo()
        info.title = obj["title"] as? String
        info.artist = obj["artist"] as? String
        info.album = obj["album"] as? String
        info.elapsed = (obj["elapsedTime"] as? NSNumber)?.doubleValue
        info.duration = (obj["duration"] as? NSNumber)?.doubleValue
        info.isPlaying = (obj["playing"] as? NSNumber)?.boolValue ?? false
        info.artworkMimeType = obj["artworkMimeType"] as? String
        if let b64 = obj["artworkData"] as? String { info.artworkData = Data(base64Encoded: b64) }
        return info
    }
}
```

- [ ] **Step 4: Run — verify pass**

Run: `swift test --filter NowPlayingParserTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Add a fixture-backed test**

Append a test that reads `nowplaying-sample.jsonl` via `Bundle.module.url(forResource:withExtension:)`, parses each non-empty line, and `#expect` at least one yields a non-nil `title`. This guards against the real adapter shape drifting from the synthetic tests.

- [ ] **Step 6: Run & commit**

Run: `swift test --filter NowPlayingParserTests` → PASS.
```bash
git add Sources/OpenNotchKit/NowPlayingParser.swift Tests/OpenNotchKitTests/NowPlayingParserTests.swift
git commit -m "feat: now-playing adapter line parser"
```

---

### Task 6: Expand/collapse state machine (pure, TDD)

**Files:**
- Create: `Sources/OpenNotchKit/NotchState.swift`
- Test: `Tests/OpenNotchKitTests/NotchStateTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum NotchPhase: Equatable { case collapsed, expanded, hidden }
  public enum NotchEvent: Equatable { case hoverIn, hoverOut, enterFullscreen, exitFullscreen }
  public struct NotchStateMachine {
      public private(set) var phase: NotchPhase
      public init(phase: NotchPhase = .collapsed)
      public mutating func handle(_ event: NotchEvent) -> NotchPhase // returns new phase
  }
  ```
  Rules: fullscreen forces `.hidden` and swallows hover until `.exitFullscreen`. Outside fullscreen: `hoverIn` → `.expanded`, `hoverOut` → `.collapsed`. `exitFullscreen` returns to `.collapsed`.

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import OpenNotchKit

@Test func hoverExpandsAndCollapses() {
    var m = NotchStateMachine()
    #expect(m.handle(.hoverIn) == .expanded)
    #expect(m.handle(.hoverOut) == .collapsed)
}

@Test func fullscreenHidesAndSwallowsHover() {
    var m = NotchStateMachine()
    #expect(m.handle(.enterFullscreen) == .hidden)
    #expect(m.handle(.hoverIn) == .hidden)      // swallowed
    #expect(m.handle(.exitFullscreen) == .collapsed)
    #expect(m.handle(.hoverIn) == .expanded)
}
```

- [ ] **Step 2: Run — verify fail**

Run: `swift test --filter NotchStateTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement**

```swift
public enum NotchPhase: Equatable { case collapsed, expanded, hidden }
public enum NotchEvent: Equatable { case hoverIn, hoverOut, enterFullscreen, exitFullscreen }

public struct NotchStateMachine {
    public private(set) var phase: NotchPhase
    public init(phase: NotchPhase = .collapsed) { self.phase = phase }

    public mutating func handle(_ event: NotchEvent) -> NotchPhase {
        switch event {
        case .enterFullscreen: phase = .hidden
        case .exitFullscreen:  phase = .collapsed
        case .hoverIn:  if phase != .hidden { phase = .expanded }
        case .hoverOut: if phase != .hidden { phase = .collapsed }
        }
        return phase
    }
}
```
(Hover-out grace timing lives in the window layer, Task 11 — the FSM stays clock-free and pure.)

- [ ] **Step 4: Run — verify pass**

Run: `swift test --filter NotchStateTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/NotchState.swift Tests/OpenNotchKitTests/NotchStateTests.swift
git commit -m "feat: notch expand/collapse state machine"
```

---

### Task 7: Plugin API contract (types + protocols)

**Files:**
- Create: `Sources/OpenNotchKit/PluginAPI.swift`

**Interfaces:**
- Produces:
  ```swift
  import SwiftUI

  public struct PluginManifest: Equatable, Sendable {
      public let id: String
      public let name: String
      public let version: String
      public let author: String
      public init(id: String, name: String, version: String, author: String)
  }

  public enum WidgetSize: Equatable, Sendable { case small, medium, wide }

  public struct PluginWidget: Identifiable {
      public let id: String
      public let size: WidgetSize
      public let content: AnyView
      public init(id: String, size: WidgetSize, content: AnyView)
  }

  @MainActor public protocol NowPlayingService: AnyObject {
      var current: NowPlayingInfo? { get }
      func play(); func pause(); func toggle()
      func next(); func previous()
      func seek(to time: TimeInterval)
  }

  @MainActor public protocol PluginHost: AnyObject {
      var nowPlaying: NowPlayingService { get }
  }

  @MainActor public protocol NotchPlugin {
      static var manifest: PluginManifest { get }
      init(host: PluginHost)
      func widgets() -> [PluginWidget]
  }
  ```

- [ ] **Step 1: Implement the contract**

Create `Sources/OpenNotchKit/PluginAPI.swift` with exactly the declarations above (fill in each memberwise `init`).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds. (Behavior is exercised by Tasks 8 & 9.)

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenNotchKit/PluginAPI.swift
git commit -m "feat: plugin API contract (NotchPlugin, PluginHost, NowPlayingService)"
```

---

### Task 8: PluginRuntime (pure, TDD)

**Files:**
- Create: `Sources/OpenNotchKit/PluginRuntime.swift`
- Test: `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`

**Interfaces:**
- Consumes: `NotchPlugin`, `PluginHost`, `PluginWidget`, `NowPlayingService`, `NowPlayingInfo` (Task 7, 4).
- Produces:
  ```swift
  @MainActor public final class PluginRuntime {
      public init(host: PluginHost, plugins: [NotchPlugin])
      public private(set) var widgets: [PluginWidget]   // widened order: wide, then medium, then small; stable within a size
      public func reload()
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import SwiftUI
@testable import OpenNotchKit

// Test doubles — public API only, no host internals.
@MainActor final class FakeNowPlaying: NowPlayingService {
    var current: NowPlayingInfo?
    var calls: [String] = []
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func toggle() { calls.append("toggle") }
    func next() { calls.append("next") }
    func previous() { calls.append("previous") }
    func seek(to time: TimeInterval) { calls.append("seek:\(time)") }
}
@MainActor final class FakeHost: PluginHost {
    let np = FakeNowPlaying()
    var nowPlaying: NowPlayingService { np }
}
@MainActor struct StubPlugin: NotchPlugin {
    static let manifest = PluginManifest(id: "test.stub", name: "Stub", version: "1", author: "t")
    let host: PluginHost
    let sizes: [WidgetSize]
    init(host: PluginHost) { self.host = host; self.sizes = [.medium] }
    init(host: PluginHost, sizes: [WidgetSize]) { self.host = host; self.sizes = sizes }
    func widgets() -> [PluginWidget] {
        sizes.enumerated().map { i, s in PluginWidget(id: "w\(i)", size: s, content: AnyView(EmptyView())) }
    }
}

@MainActor @Test func collectsAndOrdersWidgetsBySize() {
    let host = FakeHost()
    let p = StubPlugin(host: host, sizes: [.small, .wide, .medium])
    let rt = PluginRuntime(host: host, plugins: [p])
    #expect(rt.widgets.map(\.size) == [.wide, .medium, .small])
}
```

- [ ] **Step 2: Run — verify fail**

Run: `swift test --filter PluginRuntimeTests`
Expected: FAIL — `PluginRuntime` not found.

- [ ] **Step 3: Implement**

```swift
import SwiftUI

@MainActor public final class PluginRuntime {
    private let host: PluginHost
    private let plugins: [NotchPlugin]
    public private(set) var widgets: [PluginWidget] = []

    public init(host: PluginHost, plugins: [NotchPlugin]) {
        self.host = host
        self.plugins = plugins
        reload()
    }

    public func reload() {
        let rank: [WidgetSize: Int] = [.wide: 0, .medium: 1, .small: 2]
        widgets = plugins.flatMap { $0.widgets() }
            .enumerated()
            .sorted { (rank[$0.element.size]!, $0.offset) < (rank[$1.element.size]!, $1.offset) }
            .map(\.element)
    }
}
```

- [ ] **Step 4: Run — verify pass**

Run: `swift test --filter PluginRuntimeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/PluginRuntime.swift Tests/OpenNotchKitTests/PluginRuntimeTests.swift
git commit -m "feat: plugin runtime collects and orders widgets"
```

---

### Task 9: Media plugin + keystone test (TDD)

The reference plugin. Lives in `OpenNotchKit` alongside the API — but touches ONLY public types. The keystone test injects a fake host and asserts transport wiring; it compiles against public API only, which is the "zero privileges" guardrail.

**Files:**
- Create: `Sources/OpenNotchKit/MediaPlugin.swift`
- Create: `Sources/OpenNotchKit/NowPlayingView.swift`
- Test: `Tests/OpenNotchKitTests/MediaPluginTests.swift`

**Interfaces:**
- Consumes: `NotchPlugin`, `PluginHost`, `NowPlayingService`, `PluginWidget` (Task 7).
- Produces:
  ```swift
  @MainActor public struct MediaPlugin: NotchPlugin {
      public static let manifest: PluginManifest   // id "cafe.notch.media"
      public init(host: PluginHost)
      public func widgets() -> [PluginWidget]       // one .wide widget id "now-playing"
  }
  ```

- [ ] **Step 1: Write failing keystone test**

Reuse `FakeHost`/`FakeNowPlaying` from Task 8 (same test target). If Task 8's doubles are in a separate file, they are visible here; otherwise duplicate them.
```swift
import Testing
import SwiftUI
@testable import OpenNotchKit

@MainActor @Test func mediaPluginEmitsOneWideNowPlayingWidget() {
    let host = FakeHost()
    let plugin = MediaPlugin(host: host)
    let ws = plugin.widgets()
    #expect(ws.count == 1)
    #expect(ws.first?.id == "now-playing")
    #expect(ws.first?.size == .wide)
    #expect(MediaPlugin.manifest.id == "cafe.notch.media")
}

@MainActor @Test func transportButtonsCallHostService() {
    let host = FakeHost()
    let vm = NowPlayingViewModel(service: host.nowPlaying)
    vm.toggle(); vm.next(); vm.previous()
    #expect(host.np.calls == ["toggle", "next", "previous"])
}
```

- [ ] **Step 2: Run — verify fail**

Run: `swift test --filter MediaPluginTests`
Expected: FAIL — `MediaPlugin` / `NowPlayingViewModel` not found.

- [ ] **Step 3: Implement view model + view**

`Sources/OpenNotchKit/NowPlayingView.swift`:
```swift
import SwiftUI

@MainActor public final class NowPlayingViewModel {
    private let service: NowPlayingService
    public init(service: NowPlayingService) { self.service = service }
    public var info: NowPlayingInfo? { service.current }
    public func toggle() { service.toggle() }
    public func next() { service.next() }
    public func previous() { service.previous() }
    public func seek(to t: TimeInterval) { service.seek(to: t) }
}

public struct NowPlayingView: View {
    private let vm: NowPlayingViewModel
    public init(service: NowPlayingService) { self.vm = NowPlayingViewModel(service: service) }
    public var body: some View {
        HStack(spacing: 12) {
            if let bytes = vm.info?.artworkData, let img = NSImage(data: bytes) {
                Image(nsImage: img).resizable().frame(width: 44, height: 44).cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3)).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading) {
                Text(vm.info?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                Text(vm.info?.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: vm.previous) { Image(systemName: "backward.fill") }
            Button(action: vm.toggle) { Image(systemName: (vm.info?.isPlaying ?? false) ? "pause.fill" : "play.fill") }
            Button(action: vm.next) { Image(systemName: "forward.fill") }
        }.padding(12).frame(width: 360)
    }
}
```

- [ ] **Step 4: Implement the plugin**

`Sources/OpenNotchKit/MediaPlugin.swift`:
```swift
import SwiftUI

@MainActor public struct MediaPlugin: NotchPlugin {
    public static let manifest = PluginManifest(
        id: "cafe.notch.media", name: "Media", version: "1.0.0", author: "OpenNotch")
    private let host: PluginHost
    public init(host: PluginHost) { self.host = host }
    public func widgets() -> [PluginWidget] {
        [PluginWidget(id: "now-playing", size: .wide,
                      content: AnyView(NowPlayingView(service: host.nowPlaying)))]
    }
}
```

- [ ] **Step 5: Run — verify pass**

Run: `swift test --filter MediaPluginTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotchKit/MediaPlugin.swift Sources/OpenNotchKit/NowPlayingView.swift Tests/OpenNotchKitTests/MediaPluginTests.swift
git commit -m "feat: media plugin as zero-privilege reference plugin"
```

---

### Task 10: MediaRemote bridge (host-internal `NowPlayingService`)

Lives in the executable target so `OpenNotchKit` stays pure. Implements `NowPlayingService` by streaming the perl adapter and parsing with `NowPlayingParser`. Use the EXACT command strings recorded in `spike/README.md` (Task 1).

**Files:**
- Create: `Sources/OpenNotch/MediaRemoteBridge.swift`
- Manual verification (no unit test — spawns a real subprocess; covered by the smoke test in Step 4).

**Interfaces:**
- Consumes: `NowPlayingService`, `NowPlayingInfo`, `NowPlayingParser` (kit).
- Produces: `@MainActor final class MediaRemoteBridge: NowPlayingService` with a configurable adapter path.

- [ ] **Step 1: Implement the bridge**

```swift
import Foundation
import OpenNotchKit

@MainActor public final class MediaRemoteBridge: NowPlayingService {
    public private(set) var current: NowPlayingInfo?
    private let perl = "/usr/bin/perl"
    private let script: String       // vendor/.../mediaremote-adapter.pl
    private let framework: String    // vendor/.../MediaRemoteAdapter.framework
    private var stream: Process?

    public init(script: String, framework: String) {
        self.script = script; self.framework = framework
    }

    public func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        // "--no-diff" so each streamed line is a complete snapshot (the adapter
        // diffs by default, emitting only changed keys — see spike/README.md).
        p.arguments = [script, framework, "stream", "--no-diff"]
        let pipe = Pipe(); p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self, let s = String(data: h.availableData, encoding: .utf8) else { return }
            for line in s.split(separator: "\n") {
                if let info = NowPlayingParser.parse(line: String(line)) {
                    Task { @MainActor in self.current = info }
                }
            }
        }
        try? p.run(); stream = p
    }

    // Adapter transport commands are NUMERIC IDs (spike/README.md):
    // 0=play 1=pause 2=togglePlayPause 4=nextTrack 5=previousTrack.
    private func send(_ id: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        p.arguments = [script, framework, "send", String(id)]
        try? p.run()
    }

    public func play() { send(0) }
    public func pause() { send(1) }
    public func toggle() { send(2) }
    public func next() { send(4) }
    public func previous() { send(5) }
    // "seek" is a separate top-level command taking MICROSECONDS, not "send".
    public func seek(to time: TimeInterval) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        p.arguments = [script, framework, "seek", String(Int(time * 1_000_000))]
        try? p.run()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 3: Manual smoke — read**

Temporarily in `main.swift`, construct the bridge with the vendored paths, call `start()`, and every 2s print `bridge.current?.title`. `swift run OpenNotch` with music playing.
Expected: prints the current track title; updates on track change. Revert the temporary print after.

- [ ] **Step 4: Manual smoke — commands**

Add temporary calls to `bridge.toggle()` / `bridge.next()`; confirm playback changes. Revert temporary code.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/MediaRemoteBridge.swift
git commit -m "feat: MediaRemote bridge via perl adapter stream"
```

---

### Task 11: NotchWindow + NotchShell (AppKit + SwiftUI, manual verify)

**Files:**
- Create: `Sources/OpenNotch/NotchWindow.swift`
- Create: `Sources/OpenNotch/NotchShell.swift`

**Interfaces:**
- Consumes: `NotchGeometry`, `NotchStateMachine`, `PluginRuntime` (kit).
- Produces: `@MainActor final class NotchController` owning an `NSPanel` + `NSHostingView(rootView: NotchShell)`, wiring mouse-enter/exit and fullscreen notifications through `NotchStateMachine`.

- [ ] **Step 1: Implement `NotchShell` (SwiftUI)**

```swift
import SwiftUI
import OpenNotchKit

struct NotchShell: View {
    let phase: NotchPhase
    let widgets: [PluginWidget]
    var body: some View {
        Group {
            if phase == .expanded {
                HStack(spacing: 16) { ForEach(widgets) { $0.content } }
                    .padding(16)
                    .background(.black, in: RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.black).frame(height: 32) // collapsed shape
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: phase)
    }
}
```

- [ ] **Step 2: Implement `NotchWindow` / `NotchController`**

Create a borderless non-activating `NSPanel`: `styleMask = [.borderless, .nonactivatingPanel]`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`. Position via `NotchGeometry.metrics(...)` using the main screen's `frame` and `safeAreaInsets.top` (fall back to a fixed pill size when 0). Size the panel to the collapsed anchor when collapsed and to a fixed expanded size when expanded. Add an `NSTrackingArea` (or a mouse-monitor) that feeds `.hoverIn`/`.hoverOut` (with a ~0.2s hover-out grace via a cancelable `DispatchWorkItem`) into a `NotchStateMachine`, and observe `NSWorkspace.activeSpace`/fullscreen to feed `.enterFullscreen`/`.exitFullscreen`. On each new phase, resize/reposition the panel and update the `NSHostingView`'s `rootView` with `NotchShell(phase:widgets:)`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 4: Manual checklist** (defer full wiring test to Task 12, which supplies real widgets)

Expected after Task 12 wiring: panel sits over the notch; hover expands with spring; mouse-out collapses after grace.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/NotchWindow.swift Sources/OpenNotch/NotchShell.swift
git commit -m "feat: notch overlay window and SwiftUI shell"
```

---

### Task 12: App wiring, status menu & DoD walkthrough

**Files:**
- Modify: `Sources/OpenNotch/main.swift`
- Create: `Sources/OpenNotch/AppDelegate.swift`
- Create: `README.md` (manual verification checklist + run instructions)

**Interfaces:**
- Consumes: everything — `MediaRemoteBridge`, `MediaPlugin`, `PluginRuntime`, `NotchController`.
- Produces: a running app assembling the real host and the media plugin.

- [ ] **Step 1: Implement the host + AppDelegate**

`Sources/OpenNotch/AppDelegate.swift`: define `final class AppHost: PluginHost { let bridge: MediaRemoteBridge; var nowPlaying: NowPlayingService { bridge } }`. In `applicationDidFinishLaunching`: build `AppHost` with the vendored adapter paths, call `bridge.start()`, create `PluginRuntime(host:plugins:[MediaPlugin(host:host)])`, create `NotchController` with the runtime, show its panel. Add an `NSStatusItem` with a menu: "Launch at Login" (toggle via `SMAppService.mainApp`) and "Quit".

- [ ] **Step 2: Wire `main.swift`**

```swift
import AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 3: Build & run**

Run: `swift build && swift run OpenNotch`
Expected: app launches, panel appears over the notch, now-playing widget shows current track.

- [ ] **Step 4: Walk the Definition of Done checklist** (write results into `README.md`)

- Hover notch → expands into panel with now-playing card. ▢
- Play/pause/next/previous buttons control playback. ▢
- Track change updates title/artist/artwork. ▢
- Multi-display: notch on built-in, pill fallback on external. ▢
- Fullscreen app → notch hides; exit → returns. ▢
- Notch-less display → pill fallback. ▢

- [ ] **Step 5: Full test suite**

Run: `swift test`
Expected: all logic-core tests green.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotch/main.swift Sources/OpenNotch/AppDelegate.swift README.md
git commit -m "feat: wire OpenNotch app, status menu, and DoD checklist"
```

---

## Definition of Done (M1)

Hovering the notch expands it into a panel showing a now-playing card with working play/pause/next/scrub, driven entirely through the plugin API. Survives multi-display and fullscreen. Logic core green (`swift test`); adapter verified live; manual checklist walked. The media plugin reaches nothing beyond the public `PluginHost` / `NowPlayingService` — proven by the keystone test compiling against public API only.
