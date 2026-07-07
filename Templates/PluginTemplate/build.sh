#!/bin/bash
# Build WeatherPlugin.notchplugin.
#
# The plugin compiles against the OpenNotchKit module but links with
# `-undefined dynamic_lookup`, so it does NOT embed its own copy of the kit.
# At dlopen, its OpenNotchKit symbols bind to the running host (which links
# OpenNotchKit statically and exports it via -export_dynamic). One shared
# runtime → no duplicate classes, no cast crashes.
set -euo pipefail
cd "$(dirname "$0")"

# Locate the host package's built OpenNotchKit module (builds the host if needed).
HOST_PKG="../.."
KIT_MODULES="$(cd "$HOST_PKG" && swift build --show-bin-path)/Modules"
if [ ! -f "$KIT_MODULES/OpenNotchKit.swiftmodule" ]; then
    echo "OpenNotchKit module not found — run 'swift build' in the OpenNotch repo first." >&2
    exit 1
fi

OUT="WeatherPlugin.notchplugin"
BUNDLE="$OUT/WeatherPlugin.bundle/Contents/MacOS"
rm -rf "$OUT"; mkdir -p "$BUNDLE"

swiftc -emit-library \
    -module-name WeatherPlugin \
    -I "$KIT_MODULES" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    -o "$BUNDLE/WeatherPlugin" \
    Sources/WeatherPlugin/WeatherPlugin.swift

cp manifest.json "$OUT/manifest.json"
echo "Built $OUT — copy it to ~/Library/Application Support/OpenNotch/Plugins/"
