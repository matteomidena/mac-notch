# M3 risk-#1 spike — dlopen of a native plugin bundle with an unsigned host

**Date:** 2026-07-07 · **Host:** macOS 26.5.1 (arm64), Swift 6.3.2
**Question (spec risk #1):** Can a de-quarantined `.notchplugin` native bundle be `dlopen`ed by the *unsigned* OpenNotch host on current macOS — before we build the loader?

## Verdict: GO ✅

An unsigned (adhoc / linker-signed) host successfully `dlopen`ed a `.notchplugin` bundle
executable, `dlsym`ed the versioned `@_cdecl("opennotch_plugin_create")` entry point,
called it, and read back the returned value across the C boundary. **The in-process
native-plugin architecture is viable with the unsigned host.** No signing identity needed
for the mechanism to work.

Reproduce: `scratchpad/spike.sh` (builds plugin via `swiftc -emit-library`, unsigned host
via `swiftc`, dlopen/dlsym/call). dlopen a dylib and a loadable bundle are identical, so a
`-emit-library` binary faithfully answers the risk.

## Caveat to validate on-device when the loader exists

The spec assumes a quarantined plugin must be de-quarantined before dlopen. In the spike the
quarantine xattr was **present** on the bundle executable yet dlopen **still succeeded** — quarantine
is *not* enforced on dlopen from a Terminal-launched adhoc host. Gatekeeper's dlopen
quarantine check only fires when the **host `.app` is launched via LaunchServices** (Finder),
possibly translocated. That's the real deployment path and the spike did not reproduce it.

**Implication for M3, not a blocker:**
- Still implement the defensive de-quarantine step the spec calls for: strip
  `com.apple.quarantine` (`xattr -dr`) on plugin **install**, so a Finder-launched host never
  hits a quarantined dylib.
- Add one on-device validation to the M3 loader DoD: launch the bundled `OpenNotch.app` from
  Finder and load a freshly-downloaded (still-quarantined) plugin — confirm the strip-on-install
  path actually clears it. This is the only quarantine behavior the Terminal spike couldn't cover.

## Bottom line for the M3 plan

Proceed with the loader design as specced (dlopen + dlsym `opennotch_plugin_create`). The
dlopen mechanics can be exercised in CI against fixture `.notchplugin` bundles built during the
test run, exactly as the spec proposes — the spike is that harness in miniature.
