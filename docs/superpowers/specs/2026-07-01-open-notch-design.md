# OpenNotch — Design (Milestone 1)

**Status:** Approved design, ready for implementation planning
**Date:** 2026-07-01
**Name:** `OpenNotch` (placeholder — rename freely)

## Goal

An open-source, native macOS app that turns the MacBook notch into an interactive hub — a **plugin shell**. Users download the notch app, then install plugins to add features. The app is a personal daily driver first, open-sourced so others can use and extend it.

The core product is the **shell + plugin contract**, not any single feature. Media controls is the *first plugin*, built to prove the plugin API is real.

## Guiding rules

- **The shell is native.** The signature notch feel (fluid expansion, spring animation, hardware-matching shape, native rendering) is SwiftUI/AppKit. Apple users expect native quality; the base must deliver it.
- **Plugins are native SwiftUI**, conforming to a `NotchPlugin` protocol. Scope for M1: plugins render UI (widgets) and consume host-provided data only — no raw system access. A sandboxed-by-design model; permissions are added later only when a plugin needs to escape it (YAGNI).
- **The media plugin gets zero privileges.** It goes through the exact same public API a third-party plugin would. It never imports host internals and never touches `MediaRemote` directly. If media can't be built cleanly through the public API, that's an API bug — not a reason to special-case it.
- **Stage the hard part honestly.** Runtime loading of third-party plugin bundles is deferred to Milestone 2. M1 registers plugins at compile time but designs the API to be loadable later.

## Architecture

### Components

| Component | Responsibility | Tech |
|---|---|---|
| **NotchWindow** | Borderless, non-activating floating `NSPanel` pinned over the notch at menubar window level. Owns hover-in/out → expand/collapse. Follows across Spaces, doesn't steal focus. | AppKit |
| **NotchGeometry** | Detects notch size/position per screen (`NSScreen.safeAreaInsets`); falls back to a top-center pill on notch-less Macs/displays. | AppKit |
| **NotchShell** | Collapsed notch shape (hardware curve) + expanded panel with spring animation. Lays out plugin widgets in the composed dashboard. | SwiftUI |
| **PluginRuntime** | Registry: constructs plugins with a `PluginHost`, collects their widgets, arranges them by declared size. M1 = compiled-in registration; same path intended for M2 external loading. | Swift |
| **Host Services** | The only surface plugins may touch. M1 ships one: `NowPlayingService`. | Swift |
| **MediaRemote bridge** | Host-internal only. Implements `NowPlayingService` via the mediaremote-adapter technique. No plugin imports this. | Swift + `/usr/bin/perl` adapter |

### Layout model

**Composed dashboard:** when expanded, multiple plugins are visible at once. Each plugin contributes one or more **widgets** with a declared size (`.small` / `.medium` / `.wide`); the host arranges them. In M1, media is the only plugin → one wide widget, so layout is barely exercised (acceptable).

## Plugin API (the contract)

```swift
// What every plugin implements
protocol NotchPlugin {
    static var manifest: PluginManifest { get }
    init(host: PluginHost)
    func widgets() -> [PluginWidget]
}

struct PluginManifest {           // maps 1:1 to a future manifest.json (M2)
    let id: String                // reverse-DNS, e.g. "cafe.notch.media"
    let name: String
    let version: String
    let author: String
}

struct PluginWidget: Identifiable {
    let id: String
    let size: WidgetSize          // .small | .medium | .wide — host does layout
    let content: AnyView          // SwiftUI, built via @ViewBuilder
}

// The ONLY surface a plugin can reach. Host-provided, dependency-injected.
protocol PluginHost {
    var nowPlaying: NowPlayingService { get }
    // M2+: notifications, storage, permission-gated capabilities…
}

protocol NowPlayingService: Observable {
    var current: NowPlayingInfo? { get }   // title, artist, artwork, elapsed, duration, isPlaying
    func play(); func pause(); func toggle()
    func next(); func previous()
    func seek(to: TimeInterval)
}
```

### Media plugin — reference implementation

```swift
struct MediaPlugin: NotchPlugin {
    static let manifest = PluginManifest(
        id: "cafe.notch.media", name: "Media", version: "1.0.0", author: "you")

    let host: PluginHost
    init(host: PluginHost) { self.host = host }

    func widgets() -> [PluginWidget] {
        [PluginWidget(id: "now-playing", size: .wide,
            content: AnyView(NowPlayingView(service: host.nowPlaying)))]
    }
}
```

`NowPlayingView` touches only `host.nowPlaying`. It does not know `MediaRemote` exists.

## Risks

1. **MediaRemote locked down (macOS 15.4+) — #1 risk.** `mediaremoted` checks a private entitlement; `MRMediaRemoteGetNowPlayingInfo` returns `nil` for third-party apps. Workaround: the [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) technique — shell out to the entitled `/usr/bin/perl`, load a helper framework that streams now-playing + accepts transport commands over stdout/stdin. No SIP disable, no private entitlement on our app. Lives entirely inside `NowPlayingService`; swappable in one file. **Implementation step 1 is a throwaway spike proving read + play/pause/next on the actual macOS version before any UI is built.**
2. **Overlay window placement.** Non-activating `NSPanel`, correct window level, above menubar, follows Spaces, no focus steal. Edge cases: multiple displays; **fullscreen apps hide the notch** → rule: hide/disable when active space is fullscreen.
3. **Notch-less Macs/displays.** `NotchGeometry` falls back to a top-center floating pill.
4. **Compiled-in → dynamic-loading seam.** Risk the M1 API can't be loaded from an external bundle in M2 (Swift ABI/signing/crash isolation are hard). Mitigation: `PluginManifest` is pure data (mirrors future `manifest.json`); no host internals in the API. Honest caveat: M2 may conclude third-party plugins need out-of-process or a different mechanism. We design toward loadability; M1 does not prove it.
5. **Private frameworks → distribution.** No Mac App Store. Distribute a notarized DMG (or unsigned, run-at-own-risk).
6. **Always-on cost.** Adapter *streams* events → stay event-driven, no polling loop.

## Testing approach

Separate the pure **logic core** (test-first) from **window/rendering** (manually verified).

**Automated (Swift Testing, no new deps), written test-first:**
- `NotchGeometry` — screen frame + insets → notch rect; none → pill rect.
- `PluginRuntime` — plugins declaring widget sizes → expected ordered layout.
- `NowPlayingParser` — recorded adapter stdout fixtures → `NowPlayingInfo`, incl. malformed/partial lines.
- Expand/collapse **state machine** — hover/grace-timer/fullscreen events → states, driven by injected events + clock; the `NSPanel` just renders FSM output.
- **Keystone test:** `MediaPlugin` against a `FakeNowPlayingService` injected via a public-only `PluginHost`. Asserts one wide widget + transport calls. If the plugin ever reached host internals, this test would not compile — the test *is* the "zero privileges" guardrail.

**Integration smoke test:** spawn the real mediaremote-adapter, assert it emits a well-formed line within a timeout (catches Apple rule changes). Downstream uses fixtures.

**Manual checklist (README):** pixel-accurate placement; animation feel; multi-display; fullscreen hide; notch-less pill fallback.

No snapshot framework, no UI-automation rig.

## M1 scope

**In:** native shell (panel/expand/collapse/animation/shape); `NotchGeometry` + pill fallback; fullscreen-hide; `NotchPlugin`/`PluginHost`/`NowPlayingService` API; `PluginRuntime` (compiled-in); MediaRemote adapter bridge; media plugin (public API, zero privileges); the test suite.

**Non-goals (deferred by design):**
- Runtime loading of external plugin bundles → **Milestone 2** (own spec).
- Permission/consent system; system access (files/network/shell) → until a plugin needs it.
- Plugin marketplace / discovery / auto-update.
- Multiple third-party widgets; drag-to-rearrange layout.
- File shelf, notifications, calendar, timers, AirDrop, battery → later plugins.
- Preferences UI beyond a minimal quit / launch-at-login menu.
- Mac App Store (private frameworks preclude it).

**Definition of done (M1):** Hovering the notch expands it into a panel showing a now-playing card with working play/pause/next/scrub, driven entirely through the plugin API. Survives multi-display and fullscreen. Logic core green; adapter smoke test passes; manual checklist walked.
