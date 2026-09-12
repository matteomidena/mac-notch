# OpenNotch v2 — Design

**Date:** 2026-07-07
**Status:** Approved (brainstorming)
**Baseline:** the current codebase at branch `feature/open-notch-m1` (M1 + quick-actions increment) is the behavioral spec. v2 **evolves it in place** — same repo, same `OpenNotchKit`/`OpenNotch` split, same plugin contract philosophy, same test discipline.
**Audience:** an implementing Claude instance. Everything needed to plan the work is in this document plus the codebase itself.

## Goal

Evolve OpenNotch from a personal M1 daily-driver into a shippable, extensible notch platform, 10x-ing four dimensions at once:

1. **Polish & robustness** — animation substrate worthy of the Dynamic Island, multi-display, event-driven fullscreen detection, media completeness, bridge supervision.
2. **Plugin platform** — the deferred hard part: runtime-loadable third-party plugin bundles plus the host capabilities real plugins need.
3. **Feature breadth** — file shelf, calendar, battery, HUD replacement — every one built *as a plugin*, dogfooding the platform.
4. **Shippable product** — an unsigned but real `.app` on GitHub Releases with CI, onboarding, docs, and an update check.

## Inherited rules (non-negotiable, from the M1 spec)

- **Pure/executable split.** Domain logic lives in `OpenNotchKit` and is unit-tested test-first with `swift-testing` (`@Test`/`#expect`, no XCTest). Window/AppKit/rendering code lives in `OpenNotch` and is verified by a manual DoD checklist per milestone.
- **Plugins import only SwiftUI.** Anything a plugin needs from the OS comes through `PluginHost`. The keystone import-check test is the guardrail and extends to every new plugin.
- **First-party plugins get zero privileges.** Media, launcher, and every M4 plugin go through the exact same public API a third-party plugin would. If a feature can't be built through the public API, that's an API gap to fix — never a reason to special-case.
- **Event-driven, always-on discipline.** No polling loops unless no notification exists (and then documented, adaptive, and suspended when idle/locked).

## Milestone map

Each milestone is independently shippable and de-risks the next. Order matters.

| Milestone | Track | Ships |
|---|---|---|
| **M2** | Foundation hardening | A real `.app` you can double-click; island-quality animation; multi-display; robust media |
| **M3** | Plugin platform | Runtime-loadable `.notchplugin` bundles + host API v2 |
| **M4** | Feature breadth | Shelf, calendar, battery, HUD — each a plugin |
| **M5** | Ship it | GitHub Releases, CI, onboarding, docs, update check |

---

## M2 — Foundation hardening

### M2.0 Animation substrate rewrite (first item — everything else builds on it)

The current shell animates the **NSPanel frame** (`animator().setFrame` + custom `CASpringAnimation` in `NotchWindow.swift`). That is the root cause of: main-thread re-layout every animation frame (jank under load), the hover-wobble bug and its `hoverLocked`/`lockHover` DispatchWorkItem hack, the asymmetric open/close feel, non-interruptible transitions, and the disjointed two-speed window-vs-content animation.

**Replace with the static-window pattern** (the approach boringNotch / NotchNook / DynamicNotchKit converged on):

- The panel is created **once**, sized to the expanded frame plus overshoot margin, and never resizes. Delete `frameSpring`, `NotchWindow.animation(forKey:)`, `hoverLocked`, `lockHover(for:)`, and the frame-animation branches of `applyFrame`.
- `NotchPanelShape` morphs between collapsed / ambient / expanded footprints entirely in SwiftUI, driven by one spring. One continuously interpolated blob — interruptible and velocity-preserving for free (macOS 14 springs retarget natively).
- Content transitions synchronized with the morph: `.scale(anchor: .top)` + `.opacity` + blur, so content materializes with the shape, island-style.
- **Feel targets:** open `spring(response: ~0.4, dampingFraction: ~0.7)`; close `.snappy` (or `spring(response: ~0.3, dampingFraction: ~0.85)`). Expose the two springs as named constants in one file — they are calibration knobs, expect on-device tuning.
- **New problem this creates (well-trodden):** the oversized transparent window must pass mouse events through outside the visible shape. Override `hitTest` on the hosting view (or a subview) to return nil over transparent regions; hover tracking keys off the *shape's* current footprint, not the window edge.
- `NotchStateMachine` (`OpenNotchKit/NotchState.swift`) is unchanged — this rewrite swaps the FSM's renderer, not the FSM.
- **No animation library.** macOS 14 native springs (`spring(response:dampingFraction:)`, `.bouncy/.snappy/.smooth`, `PhaseAnimator`) are sufficient and are what the island itself uses. Read DynamicNotchKit (MrKai77, MIT) as a *reference* for hit-testing/morph tricks; do not adopt it. Pow (EmergeTools, MIT) may be considered in M3/M4 for transient-event flourishes only.

Manual DoD: rapid hover in/out mid-animation retargets smoothly — no loop, no dead zone, no wobble; clicks land on apps behind the transparent window region.

### M2.1 App-bundle packaging

The app currently only works when run from the package root (the perl adapter script + `MediaRemoteAdapter.framework` are resolved relative to cwd in `AppDelegate`/`MediaRemoteBridge`). Consequence: the existing Launch-at-Login toggle registers a binary that silently can't stream media.

- Embed `vendor/mediaremote-adapter` (script + built framework) as app resources; resolve via `Bundle.main` with the cwd-relative path kept as a dev-mode fallback for `swift run`.
- A build script (`Scripts/make-app.sh` or similar) produces a proper `OpenNotch.app` (Info.plist: `LSUIElement`, bundle id, version) from the SPM build output.
- Launch at Login must work from the bundled app.

### M2.2 Multi-display

`NSScreen.main` is hardcoded throughout `NotchController`; the M1 DoD line "notch on built-in, pill fallback on external" is unimplemented.

- One controller+panel **per screen**: notch shape on the built-in display, pill on externals (`NotchGeometry` already computes both).
- A display coordinator owns the controller set and rebuilds it on `NSApplication.didChangeScreenParametersNotification` (lid close/open, monitor plug/unplug, resolution change).
- Fullscreen evaluation becomes **per-display** (a fullscreen app on the external monitor must not hide the built-in notch). `FullscreenDetector.coversNotch` already takes a display frame; feed it each screen's frame in CG coordinates.

### M2.3 Fullscreen detection, event-driven first

Keep the geometric `FullscreenDetector` (it is the only thing that catches Chromium in-window video fullscreen), but restructure:

- Primary triggers: `NSWorkspace.activeSpaceDidChangeNotification` + frontmost-app change (`didActivateApplicationNotification`) → immediate evaluation.
- The 1s poll is demoted to fallback and made adaptive: suspended while the screen is locked/asleep (`screensDidSleep/WakeNotification`, session lock notifications) and while our panel is hidden.

### M2.4 Media completeness

- **Bridge supervision (bug):** if the perl stream process dies today, now-playing silently freezes forever. Watch `Process.terminationHandler`; restart with capped exponential backoff; after 3 consecutive failures within a minute surface a "media unavailable" state (`current = nil` + a host-visible flag) instead of stale data.
- **Scrubber + live progress:** progress bar in `NowPlayingView` interpolating `elapsed` between adapter events while `isPlaying` (timeline-driven; no polling of the adapter), draggable to `seek(to:)`. Pure interpolation logic (`elapsed`, timestamp, rate → display position) goes in the kit, test-first.
- **Real source badge:** the adapter payload identifies the playing app; replace the hardcoded red music-note badge with the source app's icon (resolved by the host, exposed through `NowPlayingInfo`).

### M2.5 Interaction upgrades

Extend `NotchStateMachine` (test-first, new events/phases):

- **Click-to-pin:** click expands and pins open (hover-out doesn't collapse); Escape or click-outside closes.
- **Drag-hover event:** a file drag entering the notch region expands the panel (groundwork for the M4 shelf; the FSM event and expansion land in M2, the drop handling in M4).

---

## M3 — Plugin platform

The core architectural bet, decided: **in-process native plugin bundles** (crash-isolation traded for native SwiftUI, zero-copy host services, and author simplicity — the guiding "plugins are native SwiftUI" rule survives).

### Package format & loader

```
~/Library/Application Support/OpenNotch/Plugins/
  Weather.notchplugin/
    manifest.json      { id, name, version, author, apiVersion, bundleName }
    Weather.bundle     (native bundle; @_cdecl entry point returns the plugin)
```

- `manifest.json` mirrors `PluginManifest` + `apiVersion` (semver). The host declares `OPENNOTCH_API_VERSION`; loader refuses incompatible majors with a user-visible reason in Settings.
- Entry point: a versioned `@_cdecl("opennotch_plugin_create")` returning an opaque pointer to a `NotchPlugin` factory. `dlopen` the bundle executable, `dlsym` the entry point, construct with the host.
- **Crash-attribution blocklist:** persist "loading `<id>`" before each dlopen/construct; clear on success. On next launch, an uncleared marker blocklists that plugin (skipped, flagged in Settings with an unblock action).
- Manifest parsing, apiVersion gating, and blocklist state machine are pure kit logic, test-first. The dlopen mechanics live in the executable, exercised in CI against fixture `.notchplugin` bundles built during the test run.
- Plugins folder watched (DispatchSource/FSEvents) → install/remove without relaunch where safe; dlopened code is never unloaded (unsafe), so *updates* require relaunch — document this.

### Host API v2

Grow `PluginHost` only as M4 plugins demand (YAGNI enforced by dogfooding). Known-needed:

- **`storage`** — per-plugin namespaced key-value store (UserDefaults suite keyed by plugin id). `LauncherStore` migrates onto it.
- **`events`** — a plugin requests a **transient expansion** (island-style alert: charge started, meeting in 5 min): `post(event: NotchEvent)` with priority + duration; the host arbitrates via a priority queue (pure kit logic, test-first) so plugins cannot fight over the notch. Expansion renders the event's view, auto-collapses, defers to user hover.
- **`settings`** — a plugin contributes a settings pane (`AnyView`); the Settings window gains a per-plugin section.
- Permission-gated capabilities (calendar etc.) are **declared in the manifest**, surfaced to the user in Settings, and handed to the plugin only if granted (M4's calendar plugin is the first consumer).

### Runtime & layout

- `PluginRuntime` gains enable/disable per plugin id (persisted), and merges compiled-in first-party plugins with loaded third-party ones behind one list.
- **Real layout engine** for `.small/.medium/.wide` widgets: a grid arranging multiple widgets in the expanded panel, plugin order user-configurable in Settings. (Currently `rank()` sorting is dead weight over a single wide widget.) Pure layout computation in the kit, test-first.
- Settings gains a **Plugins tab**: installed list, enable/disable, uninstall, blocklist status, per-plugin settings entry.

### SDK

- `OpenNotchKit` published as the SDK (SPM package) + a template plugin repo (manifest, build script producing a `.notchplugin`, CI recipe).
- The keystone "imports only SwiftUI" test pattern documented as the contract; a plugin-author guide (written in M5, stubbed here).

---

## M4 — Feature breadth

Every feature is a plugin using only public API. Priority order; each independently shippable:

1. **File Shelf** (flagship). Drag files onto the notch → panel expands (M2.5 event) → drop onto a shelf strip; items are stashed (bookmark/security-scoped URLs), draggable out, shareable via AirDrop (share sheet). Needs host capabilities: drop-session forwarding, share-sheet presentation. Shelf model (items, add/remove/expiry) is pure kit logic, test-first.
2. **Calendar.** EventKit behind a permission-gated host service (manifest-declared). Widget: next event + countdown; join button (detect meeting URLs in notes/location); transient event "meeting in 5 min" through `events`.
3. **Battery/charging.** IOKit power source data behind a host service. Ambient-bar charge indicator; transient event on charger connect/disconnect + low battery.
4. **HUD replacement** (high-risk, isolated). Volume/brightness OSD replacement rendered in the notch. Requires suppressing the system OSD (`OSDUIHelper` interference — private API) and key-event taps. Explicitly allowed to fail/ship-late without dragging M4; everything it needs from the OS stays in host-side code so the risk never leaks into the plugin API.
5. **Stretch:** camera mirror, timers, clipboard history.

---

## M5 — Ship it (unsigned track)

No paid Apple Developer account for now; structure so signing can be added later without rework.

- **Release artifact:** ad-hoc-signed (`codesign -s -`) `OpenNotch.app`, zipped, on GitHub Releases. README documents Gatekeeper bypass (right-click → Open / `xattr -dr com.apple.quarantine`).
- **Plugin quarantine:** downloaded `.notchplugin` bundles carry the quarantine xattr and an unsigned host dlopening them will be blocked — the **install flow must de-quarantine** (documented, explicit user action). This is spiked in M3 (see Risks) and finalized here.
- **CI:** GitHub Actions — build, `swift test`, fixture-plugin build + loader test, release artifact on tag.
- **Onboarding:** first-run window (what the notch does, how to open Settings, permission explainers before first prompt).
- **Update check:** lightweight check against the GitHub Releases API ("new version available" → link). Sparkle deferred until a signing identity exists.
- **Docs:** README overhaul (features, install, screenshots), plugin-author guide, CONTRIBUTING.

---

## Cross-cutting

- `os.Logger` (subsystem `cafe.notch`, per-area categories) replaces `NSLog` everywhere.
- Error surfaces: bridge dead → visible "media unavailable"; plugin load failure → Settings badge; never silent freezes.
- Artwork `Data` handling: de-dup identical payloads (adapter re-sends ~80KB artwork on every snapshot) before publishing to observers.
- The `installedApps()` lifetime cache gains invalidation (re-scan on Settings open or folder watch) — currently a new app requires relaunch.

## Testing approach (unchanged religion, new subjects)

- **Kit, test-first:** elapsed-time interpolation; manifest parsing + apiVersion gating; blocklist FSM; event-queue arbitration; layout engine; shelf model; extended `NotchStateMachine` (pin, drag-hover); storage namespacing.
- **Integration:** CI builds a fixture `.notchplugin` and asserts the loader loads/gates/blocklists it. The existing adapter smoke test stays.
- **Manual DoD per milestone**, appended to the README checklist (animation retargeting, multi-display matrix, drag-drop, Gatekeeper walk-through on a clean machine/VM).

## Top risks

1. **dlopen + Gatekeeper quarantine (M3/M5).** An unsigned app loading downloaded unsigned bundles is exactly what Gatekeeper exists to stop. **Spike first, at the start of M3:** confirm de-quarantined bundles load on current macOS; if blocked, fallback is source-distribution of plugins (build locally) until signing exists.
2. **HUD replacement private API (M4).** Isolated in one plugin + host service; allowed to fail.
3. **MediaRemote adapter breakage** on future macOS. Mitigated: smoke test catches it; the bridge remains swappable in one file; M2.4 supervision turns breakage into a visible degraded state instead of a freeze.
4. **Animation rewrite regressions (M2.0).** The current feel is good; the rewrite must not lose it. Mitigation: feel targets pinned above, springs as named tunable constants, manual DoD walked on hardware before merging.

## Out of scope (YAGNI, unchanged from M1 + new)

- Mac App Store (private frameworks preclude it).
- Plugin marketplace/discovery/auto-update of plugins.
- Out-of-process plugin isolation; scripted/declarative plugin tier (possible later additive tier, not the foundation).
- Sparkle auto-updates (until signing exists).
- Reordering/custom titles for launcher pills; non-app quick actions.
