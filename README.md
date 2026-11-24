# OpenNotch

[![OpenNotch in 20 seconds](docs/media/opennotch.gif)](docs/media/opennotch.mp4)

<sub>Music: “We Love Tech House (Instrumental Mix)” by Hasenchat, [Jamendo](https://www.jamendo.com/track/1246299), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).</sub>

A native macOS notch app. Hover the notch and it expands into a panel — a
now-playing card with play/pause/next/previous, a live progress scrubber you can
drag to seek, a source badge for the app that's playing, and your quick-launch
apps. On Macs without a notch it draws a pill in the same spot.

Everything in the panel is a **plugin**. Now-playing and the app launcher are
first-party plugins built on the same public `OpenNotchKit` API a third-party
plugin gets — the notch UI never touches MediaRemote directly.

## Install

1. Download `OpenNotch-<version>.zip` from
   [Releases](https://github.com/matteomidena/mac-notch/releases).
2. Unzip and drag `OpenNotch.app` to `/Applications`.
3. **Right-click the app → Open**, then confirm. Do this the first time only.

Step 3 is not optional. OpenNotch is ad-hoc signed and **not notarized** — there
is no paid Apple Developer account behind it — so double-clicking gets you
"Apple could not verify OpenNotch is free of malware" with no way through.
Right-click → Open is the documented Gatekeeper bypass. The terminal equivalent:

```bash
xattr -dr com.apple.quarantine /Applications/OpenNotch.app
```

Requires macOS 14 or later on Apple Silicon. There's no Dock icon — OpenNotch is
a menu-bar agent; its status item holds Settings and Quit.

## Plugins

Third-party plugins are `.notchplugin` bundles in:

```
~/Library/Application Support/OpenNotch/Plugins/
```

Drop one in and it loads without a relaunch (*replacing* one already loaded does
need a relaunch — dlopened code can't be safely unloaded). Manage, disable, or
uninstall them under **Settings → Plugins**.

To write one, copy [`Templates/PluginTemplate/`](Templates/PluginTemplate/) —
its README documents the entry point, the package format, and the API-version
contract.

## Building from source

```bash
./Scripts/make-app.sh   # → build/OpenNotch.app, double-clickable
./Scripts/release.sh    # → build/OpenNotch-<version>.zip, as shipped
```

`make-app.sh` embeds the MediaRemote adapter (and builds its helper framework if
missing) into the bundle's Resources, so the app runs from anywhere. This is the
path that makes "Launch at Login" work.

For a dev loop, `swift build && swift run OpenNotch` also works, but only from
the package root — in dev mode the bridge resolves the adapter relative to the
working directory.

The version in `Sources/OpenNotchKit/OpenNotchKit.swift` is the single source of
truth: it stamps the Info.plist, names the release zip, and CI refuses a release
tag that disagrees with it.

## Tests

```bash
swift test
```

The logic-core suite (`OpenNotchKitTests`) — pure logic, no UI, no live
MediaRemote. Includes an integration test that compiles a fixture plugin and
loads it through the real `dlopen` path.

---

## Definition of Done (M2) — manual checklist

Walk this on a physical MacBook with a notch, running `build/OpenNotch.app`
launched from Finder (not the repo root):

- [ ] Hover notch → expands with a bouncy spring; hover out → snappy close.
- [ ] Rapid hover in/out mid-animation retargets smoothly — no loop, no dead zone.
- [ ] Clicks land on apps behind the transparent window margins.
- [ ] Click the notch/panel → pins open (hover-out keeps it open); click
      anywhere else → unpins.
- [ ] Drag a file over the notch → panel expands; drag away → collapses.
- [ ] Play/pause/next/previous work; progress bar advances live; drag it to seek.
- [ ] Source badge shows the playing app's icon.
- [ ] `pkill -f mediaremote-adapter` → stream recovers; kill it 3× fast →
      "Media unavailable" (no frozen stale card).
- [ ] External display: pill appears there; fullscreen on one display hides
      only that display's notch/pill.
- [ ] Unplug display / close lid → panels rebuild, no strays, no crash.
- [ ] Native fullscreen hides the notch immediately; YouTube in-window
      fullscreen hides it within ~1s; exiting restores it.
- [ ] Lock screen + unlock → notch returns.
- [ ] Launch at Login works from the bundled app.

## Definition of Done (M3) — manual checklist

- [ ] Template `.notchplugin` in the Plugins folder loads on launch and renders
      its widget in the expanded panel.
- [ ] A freshly-downloaded (still-quarantined) plugin dropped into the folder is
      de-quarantined on install and loads — with the app launched from Finder.
- [ ] A plugin whose `apiVersion` major differs from the host is refused, with a
      reason shown in Settings → Plugins.
- [ ] A plugin that crashes during construct is skipped on the next launch,
      appears as Blocked, and Unblock works.
- [ ] Toggling a plugin off removes its widgets; the state survives relaunch.
- [ ] Dropping a new plugin loads it without relaunch; replacing an existing one
      logs "relaunch required" and does not hot-swap.
- [ ] With two or more widgets the grid arranges them; the single-media case
      looks unchanged.
- [ ] `Templates/PluginTemplate/build.sh` produces a loadable `.notchplugin`.
