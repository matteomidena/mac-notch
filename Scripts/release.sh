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
