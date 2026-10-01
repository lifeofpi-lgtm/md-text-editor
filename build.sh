#!/bin/bash
# Build MDmaster.app without Xcode: swift build, then wrap the binary in a bundle.
#   ./build.sh            release build -> outputs/MDmaster.app
#   ./build.sh debug      debug build
#   ./build.sh run        release build and launch
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-release}"
CONF=release
[ "$MODE" = "debug" ] && CONF=debug

swift build -c "$CONF"
BIN="$(swift build -c "$CONF" --show-bin-path)/MDmaster"
APP="outputs/MDmaster.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MDmaster"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" 2>/dev/null
echo "→ $APP"

[ "$MODE" = "run" ] && open "$APP"
exit 0
