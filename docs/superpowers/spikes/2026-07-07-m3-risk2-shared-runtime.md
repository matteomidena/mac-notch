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

## What's fixed so far

- `OpenNotchKit` is now a **dynamic** library product (`type: .dynamic` in
  `Package.swift`).
- The template plugin now links `@rpath/libOpenNotchKit.dylib` instead of
  embedding the kit (confirmed via `otool -L`).

## What remains (the decision)

SPM links a **same-package** target dependency **statically** into the executable,
so the host `OpenNotch` still embeds its own static `OpenNotchKit` — the plugin's
`@rpath/libOpenNotchKit.dylib` would resolve to a *different* file → still two copies.

To get a single shared instance:

1. **Split `OpenNotchKit` into its own SPM package** (or make the executable depend
   on the dynamic *product*, not the target). Then the host links the dynamic
   `libOpenNotchKit.dylib` too.
2. **Embed `libOpenNotchKit.dylib` in `OpenNotch.app`** (`Contents/Frameworks/`) and
   set the host's `LC_RPATH` to `@executable_path/../Frameworks` — update
   `Scripts/make-app.sh`.
3. **Plugins resolve to the bundled dylib**: the plugin's `@rpath/libOpenNotchKit.dylib`
   binds to the host's already-loaded copy (same install name), so no second copy loads.

This is a packaging change that can only be validated by launching the **bundled
`.app`** and loading a real plugin — owner/on-device territory, like the risk-#1
quarantine caveat.

## Recommendation

Do the package split + `make-app.sh` embedding as the **first task of the M3
finish** (before M4 plugins depend on the loader working). Until then, the loader,
blocklist, apiVersion gate, folder watch, Settings tab, and all pure-kit logic are
complete and tested; only the host↔plugin **shared-runtime linkage** is open.

Everything else in M3 (Tasks 1–12, plus T13's product/template/contract test) is done.
