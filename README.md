# OpenNotch

A native macOS notch app (M1). Hovering the notch expands it into a panel
showing a now-playing card with play/pause/next/previous, driven through a
small plugin API (`OpenNotchKit`) so the notch UI never touches MediaRemote
directly.

## Running

```bash
swift build
swift run OpenNotch
```

This launches an agent app (no Dock icon, `.accessory` activation policy).
A status bar item appears with a menu: "Launch at Login" and "Quit".

The app streams now-playing info via the vendored MediaRemote adapter at
`vendor/mediaremote-adapter/`. `swift run` must be invoked from the package
root so the bridge can resolve the adapter's relative paths.

## Tests

```bash
swift test
```

Runs the logic-core test suite (`OpenNotchKitTests`) — pure logic, no UI or
live MediaRemote dependency.

## Definition of Done (M1) — manual checklist

Walk this after `swift run OpenNotch` on a physical MacBook with a notch:

- [ ] Hover notch → expands into panel with now-playing card.
- [ ] Play/pause/next/previous buttons control playback.
- [ ] Track change updates title/artist/artwork.
- [ ] Multi-display: notch on built-in, pill fallback on external.
- [ ] Fullscreen app → notch hides; exit → returns.
- [ ] Notch-less display → pill fallback.
