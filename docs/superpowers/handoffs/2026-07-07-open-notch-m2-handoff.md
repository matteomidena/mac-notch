# OpenNotch — M2 Handoff

**Date:** 2026-07-07
**Branch:** `feature/open-notch-m1` (not yet merged to `master`)
**Status:** M2 fully implemented + on-device UX polish complete. Working tree clean.

Read alongside:
- Spec: `docs/superpowers/specs/2026-07-07-open-notch-v2-design.md`
- M2 plan: `docs/superpowers/plans/2026-07-07-open-notch-v2-m2.md`

---

## Where things stand

All 13 M2 tasks are done and committed (test-first for kit logic; **56 tests pass**, `swift test`). On top of the plan, a round of on-device polish fixed real bugs the plan's manual DoD surfaced. The app builds a real double-clickable bundle (`./Scripts/make-app.sh` → `build/OpenNotch.app`) and runs cwd-independently.

**Owner sign-off:** animation feel, panel size, and padding are confirmed good on hardware. Hover/click scoping and menu-bar interaction confirmed working.

### M2 commits (oldest → newest), `57f506b..HEAD`
- FSM: `pinned` phase + click/escape/drag events (kit, tested)
- `NotchFootprint` per-phase size + hit rect (kit, tested)
- Static-window animation substrate (SwiftUI morph, hit-test passthrough)
- `AdapterPaths` bundle-first resolution (kit, tested) + `make-app.sh`
- `CoordinateSpaces` AppKit→CG (kit, tested)
- Multi-display via `DisplayCoordinator` (one controller per screen, per-screen fullscreen frame)
- Event-driven fullscreen triggers + poll suspended while locked/asleep
- Adapter supervision: `RestartPolicy` backoff + "media unavailable" state (kit, tested)
- Live progress + drag-to-seek scrubber; snapshot de-dup (`PlaybackProgress`, kit, tested)
- Real source-app icon badge (parser + `MediaPlugin`, tested)
- `os.Logger` everywhere; installed-apps cache re-scans on Settings open
- README: packaged-app instructions + M2 manual DoD checklist

### Post-plan polish commits (the interactive tuning)
- **Fullscreen detection rewrite** (`cda8177`): keys off *menubar coverage* (window top ≈ 0), not the old 1px-bottom-gap heuristic. The old rule falsely flagged a maximized window as fullscreen when the Dock is auto-hidden (window reaches the true bottom), which hid the notch permanently. See "Known trade-off" below.
- **Open-trigger scoping** (`1c907f6`, `fa69937`): the notch opens **only on hover of the physical notch**. Two fixes: `hoverFootprint()` returns just the notch rect when collapsed (not the wider ambient bar); and the click monitor checks the click lands inside the notch hit-rect, not merely that `event.window == panel` (which is true for the whole 600×184 frame incl. transparent regions). Clicks beside/below now fall through instead of opening it.
- **Hover dwell** (0.14s) so a cursor passing over the notch toward the menu bar doesn't fling it open.
- **Panel shape / padding**: full-coverage panel (covers the menu bar when open — this is intended), side padding 16 = a touch more than bottom 10, expanded size 416×124.

> Note: `ac561b7`/`48c467d`/`9edf612` were a wrong turn (transparent "neck" that kept the menubar visible). Reverted — the owner wants the panel to **cover** the menu bar when open. Don't re-introduce the neck idea.

---

## Key files & tunable knobs

Feel/geometry constants live in `Sources/OpenNotch/NotchWindow.swift` (`NotchController`):
- `expandedSize = 416×124` — panel size when open.
- `hoverInDwell = 0.14s` — dwell before hover opens it. Raise if it still opens too eagerly.
- `hoverOutGrace = 0.2s` — grace before hover-out collapses.
- `notchWidth = 200` — physical notch width; drives the collapsed hover/hit region via `hoverFootprint()`.
- Open/close springs are in `NotchShell.swift` → `NotchViewModel.spring` (open `response 0.4/damping 0.7`, close `response 0.3/damping 0.85`).
- Content padding: `NotchShell.swift` content HStack `.padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 4)`.
- Fullscreen detector tuning: `FullscreenDetector.coversNotch(..., topTolerance: 2)` in `Sources/OpenNotchKit/FullscreenDetector.swift`.

Architecture reminders:
- Pure logic → `Sources/OpenNotchKit` (test-first, `import Testing`). AppKit/window → `Sources/OpenNotch` (manual DoD).
- `PassthroughHostingView` does hit-test passthrough for the oversized static window; `interactiveRect` = `hitRect()` (notch when collapsed, full panel when open).

---

## Still open before calling M2 fully shipped

1. **Walk the manual DoD checklist on hardware** (README "Definition of Done (M2)"). Verified by owner so far: animation, size, padding, hover/click scoping. **Not yet confirmed:** external-display pill + per-display fullscreen, unplug/lid rebuild, lock-screen return, `pkill -f mediaremote-adapter` recovery + "media unavailable" after 3 kills, Launch-at-Login from the bundled app, YouTube in-window fullscreen (see trade-off).
2. **Decide the branch finish** (owner deferred): merge `feature/open-notch-m1` → `master`, or open a PR. Use superpowers:finishing-a-development-branch.

## Known trade-off to validate on-device (fullscreen detection)

The new detector treats **menubar coverage** as the fullscreen signal. Consequence: **native macOS fullscreen** still hides the notch (covers the menubar + fires `activeSpaceDidChange`), but **in-window video fullscreen that keeps the system menubar visible** (some Chromium/YouTube "f" modes) is no longer caught geometrically. This was a deliberate choice — the previous heuristic couldn't distinguish an in-window-fullscreen window from a maximized window with the Dock hidden (identical geometry), and the maximized case was breaking the notch. If in-window YouTube fullscreen needs to hide the notch again, revisit `FullscreenDetector` — likely needs a non-geometric signal (menubar-hidden state), not a tolerance tweak.

---

## Next milestone: M3 — Plugin platform

Per the spec's milestone map, M3 is next. **Before writing the M3 plan, run the spec's risk-#1 spike first:** confirm a de-quarantined `.notchplugin` bundle `dlopen`s on the current macOS with the unsigned host — *before* building the loader. If blocked, the fallback is source-distribution of plugins until a signing identity exists.

Then write the M3 plan from the spec (§ "M3 — Plugin platform") using the superpowers:writing-plans skill: package format & loader, host API v2 (`storage`/`events`/`settings`), runtime enable/disable + real layout engine, Plugins settings tab, SDK. Pure kit logic (manifest parsing, apiVersion gating, blocklist FSM, event-queue arbitration, layout, storage namespacing) stays test-first. M4 (feature plugins) and M5 (ship it) follow, one plan per milestone.
