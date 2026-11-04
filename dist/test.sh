#!/bin/bash
# Offline, terminating unit tests. Never launches the Walter executable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="${SWIFT:-swift}"
ARGS=(test --package-path "$ROOT/Walter" --disable-automatic-resolution)

# Some Command Line Tools installations ship Testing as a framework outside
# SwiftPM's default search path, with an incomplete Foundation cross-overlay.
# Use only the selected local toolchain; never download test dependencies.
DEVELOPER="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER/Library/Developer/Frameworks"
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    ARGS+=(-Xswiftc "-F$FRAMEWORKS"
           -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
           -Xlinker -rpath -Xlinker "$FRAMEWORKS")
fi
exec "$SWIFT" "${ARGS[@]}" "$@"
