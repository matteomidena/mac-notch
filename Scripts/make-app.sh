#!/bin/bash
# Builds a double-clickable OpenNotch.app from the SPM release build.
# The mediaremote-adapter (perl script + framework) is embedded in Resources;
# AdapterPaths resolves it from Bundle.main at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# The helper framework is a build product and vendor/**/build/ is git-ignored, so
# a clean checkout (CI included) must build it here — otherwise the app ships
# without now-playing. Recipe from spike/README.md.
# ponytail: host-arch only. Notched Macs are all Apple Silicon; add
# `-arch x86_64 -arch arm64` if an Intel/universal build is ever needed.
FW="vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework"
if [ ! -f "$FW/MediaRemoteAdapter" ]; then
    echo "Building MediaRemoteAdapter framework..."
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

APP="build/OpenNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/OpenNotch "$APP/Contents/MacOS/OpenNotch"
cp -R vendor/mediaremote-adapter "$APP/Contents/Resources/mediaremote-adapter"
# Trim non-runtime vendor files from the bundle.
rm -rf "$APP/Contents/Resources/mediaremote-adapter/.vscode" \
       "$APP/Contents/Resources/mediaremote-adapter/.git" 2>/dev/null || true

VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/OpenNotchKit/OpenNotchKit.swift)"
[ -n "$VERSION" ] || { echo "cannot read version from OpenNotchKit.swift" >&2; exit 1; }

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenNotch</string>
    <key>CFBundleIdentifier</key><string>cafe.notch.OpenNotch</string>
    <key>CFBundleName</key><string>OpenNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature (spec M5: no Developer ID yet).
codesign --force --deep --sign - "$APP"
echo "Built $APP"
