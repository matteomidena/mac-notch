# Task 1 Spike — MediaRemote now-playing access

**Verdict: ✅ GO.** Now-playing read and transport control both work on this Mac
(macOS 26 / Apple Silicon, Swift 6.3) via the `ungive/mediaremote-adapter`
perl-shim technique. Verified against a live Spotify session.

This is a throwaway spike. Its durable outputs are this file, the captured
fixture (`Tests/OpenNotchKitTests/Fixtures/nowplaying-sample.jsonl`), and the
build recipe below.

## Adapter

- Source: https://github.com/ungive/mediaremote-adapter — vendored at
  `vendor/mediaremote-adapter` (`.git` stripped).
- License: **BSD 3-Clause** (Jonas van den Berg and contributors) — permissive,
  safe to vendor.
- Technique: `/usr/bin/perl` is Apple-entitled to use the private MediaRemote
  framework; the perl script `dl_load_file`s a small helper framework and calls
  MediaRemote from inside the entitled interpreter. No SIP disable, no private
  entitlement on our app.

## Building the helper framework (no cmake required)

The repo ships a CMake build, but cmake was not installed. The framework is
plain Objective-C and builds directly with clang. The perl script only
`dl_load_file`s the binary at `<name>.framework/<name>`, so the full bundle
structure is unnecessary — just the binary at that path.

```bash
cd vendor/mediaremote-adapter
mkdir -p build/MediaRemoteAdapter.framework
clang -dynamiclib -fobjc-arc -fvisibility=default \
  -Iinclude -Isrc \
  src/adapter/*.m src/private/*.m src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -o build/MediaRemoteAdapter.framework/MediaRemoteAdapter
codesign --force --sign - build/MediaRemoteAdapter.framework/MediaRemoteAdapter
```

Note: this produces a host-arch (arm64) binary. cmake's build is universal
(x86_64 + arm64); add `-arch x86_64 -arch arm64` to the clang line if a
universal binary is needed for distribution. `build/` is git-ignored; Task 10
(or a build step) rebuilds it.

## Exact commands

Let `FW=$(realpath vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework)`
and `PL=vendor/mediaremote-adapter/bin/mediaremote-adapter.pl`.

- **Read once:** `/usr/bin/perl "$PL" "$FW" get` (add `--no-artwork` to omit base64 artwork)
- **Stream updates:** `/usr/bin/perl "$PL" "$FW" stream` (diffed JSON lines; `--no-diff` for full each time)
- **Send transport command:** `/usr/bin/perl "$PL" "$FW" send <ID>` — **IDs are numeric:**
  - `0` = play, `1` = pause, `2` = togglePlayPause, `3` = stop
  - `4` = nextTrack, `5` = previousTrack
- **Seek:** `/usr/bin/perl "$PL" "$FW" seek <POSITION>` — POSITION is **microseconds** (a separate top-level command, NOT `send`).

## Observed JSON shape (real output)

```json
{"playbackRate":1,"album":"Eye Of The Storm","mediaType":"kMRMediaRemoteNowPlayingInfoTypeAudio","trackNumber":1,"elapsedTime":32.472,"timestamp":"2026-07-01T17:22:59Z","bundleIdentifier":"com.spotify.client","processIdentifier":22189,"title":"Eye Of The Storm","totalDiscCount":1,"totalTrackCount":1,"duration":176.614,"artist":"IRAH","contentItemIdentifier":"...","playing":true}
```

Artwork (`get` without `--no-artwork`) adds `artworkData` (base64) and
`artworkMimeType`. Observed artwork was **JPEG** (`/9j/…`), not PNG.

## ⚠️ Corrections for downstream tasks (plan assumptions were wrong)

1. **"Is playing" is the boolean `playing`, NOT `playbackRate`.** When paused,
   `playbackRate` is *absent entirely* (there is no `playbackRate:0`). Task 5's
   parser must read `playing` (bool). The plan's `playbackRate > 0` logic is wrong.
2. **Artwork is not necessarily PNG.** It arrives as `artworkData` (base64) +
   `artworkMimeType`. Task 4's model field `artworkPNG: Data?` should be renamed
   `artworkData: Data?` (raw bytes; `NSImage(data:)` handles JPEG/PNG either way),
   optionally with an `artworkMimeType: String?`.
3. **`send` uses numeric IDs, not string command names.** Task 10's bridge must
   send `"2"`/`"4"`/`"5"`, not `"togglePlayPause"`/`"nextTrack"`/`"previousTrack"`.
4. **Seek is `seek <microseconds>`, a separate command** — not
   `send setElapsedTime`. Task 10's `seek(to:)` must call
   `seek` with `Int(time * 1_000_000)`.
5. Mandatory keys that are always present when valid: `bundleIdentifier`,
   `playing`, `title`. If any can't be determined the command prints `null`.
6. `stream` diffs by default — a streamed line may contain only *changed* keys,
   so the bridge should merge updates into the last-known state rather than
   replacing it wholesale. (Or pass `--no-diff`.)

## Verified

- ✅ `get` returns full metadata for the live Spotify track.
- ✅ `send 2` toggled play/pause (`playing` flipped true↔false).
- ✅ `send 4` advanced to the next track ("White Wine" by Brodie).
- ✅ `send 5` returned to the previous track.
- ✅ `send 1` / `send 0` paused / resumed.
