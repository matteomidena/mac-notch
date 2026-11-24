#!/bin/bash
# Builds a double-clickable OpenNotch.app from the SPM release build.
# The mediaremote-adapter (perl script + framework) is embedded in Resources;
# AdapterPaths resolves it from Bundle.main at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
swift build -c release

APP="build/OpenNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/OpenNotch "$APP/Contents/MacOS/OpenNotch"
cp -R vendor/mediaremote-adapter "$APP/Contents/Resources/mediaremote-adapter"
cp -R vendor/inter "$APP/Contents/Resources/inter"   # InterVariable.ttf + OFL.txt
# App icon: assets/AppIcon.png (1024², from Codex) → AppIcon.icns.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Trim non-runtime vendor files from the bundle.
rm -rf "$APP/Contents/Resources/mediaremote-adapter/.vscode" \
       "$APP/Contents/Resources/mediaremote-adapter/.git" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenNotch</string>
    <key>CFBundleIdentifier</key><string>cafe.notch.OpenNotch</string>
    <key>CFBundleName</key><string>OpenNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__VERSION__</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

sed -i '' "s/__VERSION__/$VERSION/g" "$APP/Contents/Info.plist"

# Ad-hoc signature (spec M5: no Developer ID yet).
codesign --force --deep --sign - "$APP"
echo "Built $APP ($VERSION)"

# Installable disk image: drag OpenNotch into Applications.
DMG="build/OpenNotch-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "OpenNotch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
