# OpenNotch M5-minimal (v0.1.0 release) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a downloadable, runnable `OpenNotch.app` on GitHub Releases as **v0.1.0**, without waiting for M4.

**Architecture:** M5 in the spec is six workstreams. This plan ships the three that a user cannot install without, and explicitly defers the other three (see "Deliberately skipped"). `Scripts/make-app.sh` already produces the bundle, so the release path is: single-source the version, wrap the bundle in a `ditto` zip, and let one GitHub Actions workflow own both CI and the tag→draft-release step.

**Tech Stack:** Swift 6 SPM, `codesign -s -` (ad-hoc), `ditto`, GitHub Actions (macOS runner), `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-07-07-open-notch-v2-design.md` § "M5 — Ship it (unsigned track)"

## Global Constraints

- Platform floor: macOS 14. Swift tools 6.0.
- **No new dependencies** — including no third-party GitHub Actions. Use the preinstalled `gh` CLI with the built-in `GITHUB_TOKEN`.
- Unsigned track: ad-hoc signature (`codesign -s -`), no Developer ID, no notarization, no Sparkle.
- **One source of truth for the version:** `OpenNotchKit.version` in `Sources/OpenNotchKit/OpenNotchKit.swift`. Info.plist, the zip name, and the git tag all derive from or are checked against it.
- Release artifacts are created as **drafts**. Publishing is a human action gated on the hardware DoD walk.

## Deliberately skipped (YAGNI for v0.1.0)

| Spec item | Why not now | Add when |
|---|---|---|
| First-run onboarding window | README covers what the notch does; a first-run window is UI work with its own DoD | v0.2, alongside M4's permission prompts (calendar/EventKit needs explainers anyway) |
| Update check against the Releases API | Nothing to update *to* until a second release exists | v0.2, when there is a prior version in the wild |
| Long-form plugin-author guide | `Templates/PluginTemplate/README.md` already documents the contract, package format, and update semantics | Third-party plugin authors actually appear |

---

### Task 1: Ship M2 + M3 to `master`

**Files:** none (git operations only)

- [x] **Step 1: Push the unpushed feature branch**

```bash
git push origin feature/open-notch-m1
```

- [x] **Step 2: Open the PR and merge it**

```bash
gh pr create --base master --head feature/open-notch-m1 \
  --title "feat: M2 foundation hardening + M3 plugin platform"
gh pr merge 3 --merge
```

- [x] **Step 3: Fast-forward the release worktree**

```bash
git fetch origin && git merge --ff-only origin/master
```

---

### Task 2: Single-source the version + produce a release zip

**Files:**
- Modify: `Scripts/make-app.sh` (Info.plist version block)
- Create: `Scripts/release.sh`

**Interfaces:**
- Produces: `Scripts/release.sh` → `build/OpenNotch-<version>.zip`, and echoes the version on stdout as the last line. Task 3's workflow consumes both.
- `make-app.sh` gains a `VERSION` it reads from `Sources/OpenNotchKit/OpenNotchKit.swift`.

- [x] **Step 1: Read the version out of the kit instead of hardcoding it**

`make-app.sh` currently hardcodes `<string>2.0.0</string>` while the kit says `0.1.0`. Replace the heredoc's static version. Above the `cat > Info.plist` block:

```bash
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OpenNotchKit/OpenNotchKit.swift)"
[ -n "$VERSION" ] || { echo "cannot read version from OpenNotchKit.swift" >&2; exit 1; }
```

Then switch the heredoc from `<<'PLIST'` (quoted, no expansion) to `<<PLIST` (unquoted, expands) and use:

```
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
```

- [x] **Step 1b: Build the helper framework during packaging** *(added during execution — release blocker)*

`vendor/mediaremote-adapter/build/` is git-ignored, so `MediaRemoteAdapter.framework` is a build product that exists only on a machine that has run the `spike/README.md` recipe by hand. `make-app.sh` copied `vendor/mediaremote-adapter` wholesale, which silently picked the framework up locally and would silently omit it on a clean checkout or CI — shipping an app with no now-playing. Build it in `make-app.sh`, right after `swift build -c release` and before the `cp -R`:

```bash
FW="vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework"
if [ ! -f "$FW/MediaRemoteAdapter" ]; then
    mkdir -p "$FW"
    clang -dynamiclib -fobjc-arc -fvisibility=default \
        -Ivendor/mediaremote-adapter/include -Ivendor/mediaremote-adapter/src \
        vendor/mediaremote-adapter/src/adapter/*.m \
        vendor/mediaremote-adapter/src/private/*.m \
        vendor/mediaremote-adapter/src/utility/*.m \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -o "$FW/MediaRemoteAdapter"
    codesign --force --sign - "$FW/MediaRemoteAdapter"
fi
```

Host-arch only, deliberately — notched Macs are all Apple Silicon, and the GitHub `macos-15` runner is arm64. `-arch x86_64 -arch arm64` if that ever changes.

- [x] **Step 2: Write the release script**

`ditto`, not `zip` — `zip` mangles the bundle's symlinks and resource forks and breaks the ad-hoc signature.

```bash
#!/bin/bash
# Builds OpenNotch.app and wraps it in a release zip.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/make-app.sh

VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OpenNotchKit/OpenNotchKit.swift)"
ZIP="build/OpenNotch-${VERSION}.zip"
rm -f "$ZIP"
# ditto, not zip: preserves the bundle layout and the ad-hoc signature.
ditto -c -k --sequesterRsrc --keepParent build/OpenNotch.app "$ZIP"

codesign --verify --deep --strict build/OpenNotch.app
echo "Built $ZIP"
echo "$VERSION"
```

`chmod +x Scripts/release.sh`.

- [x] **Step 3: Run it and verify the artifact**

```bash
./Scripts/release.sh
unzip -l build/OpenNotch-0.1.0.zip | head
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/OpenNotch.app/Contents/Info.plist
```

Expected: zip contains `OpenNotch.app/Contents/MacOS/OpenNotch`, `codesign --verify` is silent (exit 0), PlistBuddy prints `0.1.0`.

- [x] **Step 4: Commit**

```bash
git add Scripts/make-app.sh Scripts/release.sh
git commit -m "feat: release zip + version single-sourced from OpenNotchKit"
```

---

### Task 3: CI workflow — test on push/PR, draft release on tag

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Scripts/release.sh` from Task 2.
- Produces: a draft GitHub Release per `v*` tag, with the zip attached.

- [ ] **Step 1: Write the workflow**

Two jobs. `test` runs everywhere. `release` runs only on a `v*` tag and asserts the tag matches `OpenNotchKit.version`, so a mistyped tag fails loudly instead of shipping a mislabelled build.

```yaml
name: CI

on:
  push:
    branches: [master]
    tags: ['v*']
  pull_request:

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift build
      - run: swift test

  release:
    needs: test
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: macos-15
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Check the tag matches OpenNotchKit.version
        run: |
          KIT="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OpenNotchKit/OpenNotchKit.swift)"
          TAG="${GITHUB_REF_NAME#v}"
          [ "$KIT" = "$TAG" ] || { echo "tag $TAG != OpenNotchKit.version $KIT"; exit 1; }
      - run: ./Scripts/release.sh
      - name: Create the draft release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            --draft --title "$GITHUB_REF_NAME" --generate-notes \
            build/OpenNotch-*.zip
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build + test on push/PR, draft release on v* tag"
```

---

### Task 4: README — make the app installable by a stranger

**Files:**
- Modify: `README.md`

The current README is a developer's file: it opens with `swift build`. A downloader needs Install first, and needs the Gatekeeper bypass or the app simply will not open.

- [ ] **Step 1: Restructure**

Order: what it is → Install (download, unzip, right-click → Open, why) → Plugins (folder path, pointer to the template) → Building from source → Tests → the existing M2/M3 DoD checklists (kept, they are the release gate).

Gatekeeper section must state: the app is ad-hoc-signed, not notarized; **right-click → Open** the first time (double-click will be refused); `xattr -dr com.apple.quarantine /Applications/OpenNotch.app` as the terminal equivalent.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: install instructions + Gatekeeper bypass for the unsigned build"
```

---

### Task 5: Hardware DoD gate, then publish (owner action)

CI cannot walk a notch. The draft release exists so this gate is real rather than aspirational.

- [ ] **Step 1: Walk the M2 checklist** (README) — the unconfirmed half: external-display pill + per-display fullscreen, unplug/lid rebuild, lock-screen return, `pkill -f mediaremote-adapter` recovery and "media unavailable" after 3 rapid kills, Launch at Login from the bundled app.
- [ ] **Step 2: Walk the M3 DoD** (`docs/superpowers/plans/2026-07-07-open-notch-v2-m3.md` § "Definition of Done (M3)") — in particular #2, the quarantine flow: drop a freshly-downloaded, still-quarantined `.notchplugin` into the folder with the app launched **from Finder**. This is the one behaviour no spike or CI job has ever covered, and the whole unsigned-distribution story rests on it.
- [ ] **Step 3: Publish** — `gh release edit v0.1.0 --draft=false`.

If step 2 fails, the fallback in the spec's risk #1 stands: document source-distribution of plugins for v0.1.0 and keep the loader as-is.

---

## Self-review notes

- **Spec coverage (M5):** release artifact → T2; CI → T3; plugin quarantine → already implemented (`PluginsFolder.stripQuarantine`), validated in T5 step 2; docs → T4 (README) + the existing template README. Onboarding and update check are consciously deferred with a trigger, in the table above.
- **Type consistency:** the `sed` version expression appears in `make-app.sh` (T2 S1), `release.sh` (T2 S2), and `ci.yml` (T3) — identical in all three, reading the same `OpenNotchKit.version`.
- **Placeholders:** none — every step carries the literal file content or command.
