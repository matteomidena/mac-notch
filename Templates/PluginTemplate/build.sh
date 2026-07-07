#!/bin/bash
# Build WeatherPlugin.notchplugin from this template.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
OUT="WeatherPlugin.notchplugin"
BUNDLE="$OUT/WeatherPlugin.bundle/Contents/MacOS"
rm -rf "$OUT"; mkdir -p "$BUNDLE"
cp .build/release/libWeatherPlugin.dylib "$BUNDLE/WeatherPlugin"
cp manifest.json "$OUT/manifest.json"
echo "Built $OUT — copy it to ~/Library/Application Support/OpenNotch/Plugins/"
