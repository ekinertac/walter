#!/bin/bash
# build-release.sh — Build, sign, notarize, and package Walter.app as a DMG
#
# Prerequisites:
#   - "Developer ID Application: EKIN ERTAC (QKN7RYV5PD)" certificate in keychain
#   - Notarytool keychain profile "AC_PASSWORD" configured
#   - create-dmg installed (brew install create-dmg)
#
# Usage:
#   ./dist/build-release.sh          → builds + signs + notarizes + DMG
#   ./dist/build-release.sh --skip-notarize  → skip notarization (faster for testing)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFT_DIR="$PROJECT_DIR/Walter"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$DIST_DIR/build"

APP_NAME="Walter"
BUNDLE_ID="com.ekinertac.walter"
SIGNING_IDENTITY="Developer ID Application: EKIN ERTAC (QKN7RYV5PD)"
KEYCHAIN_PROFILE="AC_PASSWORD"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DIST_DIR/Info.plist")

SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

echo "=========================================="
echo "  Walter v${VERSION} — Release Build"
echo "=========================================="

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1. Build release binary
# ---------------------------------------------------------------------------
echo ""
echo "→ Building release binary..."
cd "$SWIFT_DIR"
swift build -c release 2>&1 | tail -3

BINARY="$SWIFT_DIR/.build/release/Walter"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY ($(du -h "$BINARY" | cut -f1) )"

# ---------------------------------------------------------------------------
# 2. Create .app bundle
# ---------------------------------------------------------------------------
echo ""
echo "→ Creating Walter.app bundle..."

APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Binary
cp "$BINARY" "$MACOS/Walter"

# Info.plist
cp "$DIST_DIR/Info.plist" "$CONTENTS/Info.plist"

# Icon
if [[ -f "$SWIFT_DIR/.build/release/Walter_Walter.bundle/Contents/Resources/AppIcon.icns" ]]; then
    cp "$SWIFT_DIR/.build/release/Walter_Walter.bundle/Contents/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
elif [[ -f "$SWIFT_DIR/Sources/Walter/Resources/AppIcon.icns" ]]; then
    cp "$SWIFT_DIR/Sources/Walter/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Resource bundle (contains icons, etc.)
RESOURCE_BUNDLE=$(find "$SWIFT_DIR/.build/release" -name "Walter_Walter.bundle" -maxdepth 1 2>/dev/null | head -1)
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"
fi

echo "  Bundle: $APP_DIR"

# ---------------------------------------------------------------------------
# 3. Code sign with hardened runtime
# ---------------------------------------------------------------------------
echo ""
echo "→ Signing with: $SIGNING_IDENTITY"

codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$DIST_DIR/Walter.entitlements" \
    --timestamp \
    "$APP_DIR"

echo "  Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"
echo "  ✓ Signature valid"

# ---------------------------------------------------------------------------
# 4. Notarize
# ---------------------------------------------------------------------------
if [[ "$SKIP_NOTARIZE" == true ]]; then
    echo ""
    echo "→ Skipping notarization (--skip-notarize)"
else
    echo ""
    echo "→ Creating ZIP for notarization..."
    NOTARIZE_ZIP="$BUILD_DIR/Walter-notarize.zip"
    ditto -c -k --keepParent "$APP_DIR" "$NOTARIZE_ZIP"

    echo "→ Submitting to Apple notary service..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$APP_DIR"
    echo "  ✓ Notarization complete"

    rm "$NOTARIZE_ZIP"
fi

# ---------------------------------------------------------------------------
# 5. Create DMG
# ---------------------------------------------------------------------------
echo ""
echo "→ Creating DMG..."

DMG_NAME="Walter-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# Remove old DMG if exists
rm -f "$DMG_PATH"

create-dmg \
    --volname "Walter" \
    --volicon "$RESOURCES/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Walter.app" 175 190 \
    --app-drop-link 425 190 \
    --hide-extension "Walter.app" \
    "$DMG_PATH" \
    "$APP_DIR" \
    2>&1 | grep -v "^$"

# Sign the DMG too
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

echo ""
echo "=========================================="
echo "  ✓ Done!"
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "=========================================="
