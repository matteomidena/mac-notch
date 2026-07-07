# M3 risk-#2 finding — shared OpenNotchKit runtime for in-process plugins

**Date:** 2026-07-07 · surfaced while building the M3 SDK template (plan Task 13).

## The problem

The in-process plugin model needs the host **and** every plugin to share **one**
copy of `OpenNotchKit` at runtime. When a plugin statically embeds its own copy,
`dlopen` produces two copies of every kit class. The runtime warns:

```
objc[…]: Class _TtC12OpenNotchKit9PluginBox is implemented in both
  …/OpenNotch and …/WeatherPlugin.bundle/…/WeatherPlugin.
  This may cause spurious casting failures and mysterious crashes.
```

Concretely, `hostFromPointer`'s `… as! PluginHost` casts an object built against
the **host's** `PluginHost` to the **plugin's** copy of `PluginHost` — a different
type — so the cast fails and the force-unwrap crashes. This breaks every real
(kit-linked) plugin. The risk-#1 spike used a *kit-free* fixture, which is why it
didn't surface there.

## RESOLVED — via `dynamic_lookup` (owner-approved)

The chosen fix keeps the host statically linking `OpenNotchKit` (as always) and
makes plugins resolve kit symbols **against the running host** instead of embedding
their own copy:

1. **Host exports its symbols.** `Package.swift` adds
   `linkerSettings: [.unsafeFlags(["-Xlinker", "-export_dynamic"])]` to the
   `OpenNotch` executable target. Confirmed: `nm -gU` shows the host exports
   `_$s…OpenNotchKit9PluginBox…` etc.
2. **Plugins don't embed the kit.** `Templates/PluginTemplate/build.sh` compiles
   against the kit module (`-I <bin>/Modules`) but links with
   `-Xlinker -undefined -Xlinker dynamic_lookup` — no `libOpenNotchKit` in the
   plugin's load commands (confirmed via `otool -L`; only system dylibs remain).
   Undefined `OpenNotchKit` symbols bind to the host process at `dlopen`.

### Verified end-to-end (dev build, this machine)

Installed the real kit-linked template plugin and launched the host:

```
loaded com.example.weather widgets=1     # dlopen → box ABI → as! PluginHost cast OK → widgets()
duplicate-class warnings: 0              # single shared OpenNotchKit runtime
load marker cleared after run            # clean load, no crash
```

Before the fix: 12+ "Class … implemented in both" warnings and a crash on the cast.

### Remaining on-device check (owner)

Confirm the bundled **`OpenNotch.app`** (via `Scripts/make-app.sh`) still exports its
symbols — i.e. the packaging step doesn't strip them — so a plugin loaded by the
Finder-launched app resolves the same way. `make-app.sh` currently copies the
executable as-is (no `strip`), so this should hold; verify by loading the template
plugin into the packaged app once. This is the only shared-runtime item left, and it
sits with the risk-#1 quarantine check on the on-device DoD.

M3 is otherwise complete: Tasks 1–13 done, 85 kit tests green, and the full load
chain proven with a real third-party plugin.
