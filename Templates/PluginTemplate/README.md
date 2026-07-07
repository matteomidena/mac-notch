# OpenNotch Plugin Template

A minimal `.notchplugin` you can copy to start a new plugin.

## Build & install

```bash
./build.sh
cp -R WeatherPlugin.notchplugin ~/Library/Application\ Support/OpenNotch/Plugins/
```

Restart OpenNotch (or drop it in while running) and expand the notch — the
Weather widget appears. Manage it under **Settings → Plugins**.

## The contract

- **Import only `SwiftUI` and `OpenNotchKit`.** Everything the OS can do for a
  plugin goes through the `PluginHost` passed to your `init` — a plugin never
  imports AppKit. (The host enforces this on its own plugin-facing code with a
  test; follow the same rule and your plugin stays portable.)
- **One entry point.** Export exactly one `@_cdecl("opennotch_plugin_create")`.
  Copy it verbatim from `WeatherPlugin.swift`; the SDK's `hostFromPointer` /
  `PluginBox` helpers do the pointer marshalling.
- **`apiVersion` must match the host's major.** The host declares
  `OPENNOTCH_API_VERSION`; a plugin whose `apiVersion` major differs is refused
  and shown with a reason in Settings.

## Updating a plugin

Dropping a *new* plugin loads it live. **Replacing an already-loaded plugin
requires relaunching OpenNotch** — dlopened code is never unloaded (unloading is
unsafe), so an update can't hot-swap.

## Package format

```
WeatherPlugin.notchplugin/
  manifest.json                 # { id, name, version, author, apiVersion, bundleName }
  WeatherPlugin.bundle/
    Contents/MacOS/WeatherPlugin  # the Mach-O the host dlopens
```
