#!/bin/bash
# Build a locally-usable Walter.app with Swift CLI tools and ad-hoc signing.
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo "Usage: $0 (no arguments; builds dist/build/Walter.app)" >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
    echo "ERROR: Building Walter requires macOS." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFT_DIR="$PROJECT_DIR/Walter"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/Walter.app"
SWIFT="${SWIFT:-swift}"

# Build before replacing the previous bundle, and use SwiftPM's actual output
# path rather than assuming a particular architecture or toolchain layout.
echo "→ Building Walter for this Mac..."
"$SWIFT" build --package-path "$SWIFT_DIR" -c release --disable-automatic-resolution
BIN_DIR="$("$SWIFT" build --package-path "$SWIFT_DIR" -c release --disable-automatic-resolution --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/Walter_Walter.bundle"
[[ -f "$BIN_DIR/Walter" && -d "$RESOURCE_BUNDLE" ]] || {
    echo "ERROR: SwiftPM executable or resource bundle is missing." >&2
    exit 1
}

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Walter" "$APP_DIR/Contents/MacOS/Walter"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SWIFT_DIR/Sources/Walter/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
# WalterResources prefers the embedded bundle over SwiftPM's build-tree path.
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "→ Applying an ad-hoc signature (no certificate or account)..."
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
echo "Quit Walter before replacing an installed copy. Install manually under /Applications."
