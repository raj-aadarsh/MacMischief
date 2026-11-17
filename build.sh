#!/bin/bash
# Builds MacMischief.app into ./build.
#   ./build.sh            build only
#   ./build.sh --run      build and launch from ./build
#   ./build.sh --install  build, copy to /Applications, and launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

APP=build/MacMischief.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacMischief" "$APP/Contents/MacOS/MacMischief"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime \
  --entitlements Resources/MacMischief.entitlements "$APP" >/dev/null

echo "Built $APP"

case "${1:-}" in
  --run)
    pkill -x MacMischief 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    pkill -x MacMischief 2>/dev/null || true
    rm -rf /Applications/MacMischief.app
    cp -R "$APP" /Applications/MacMischief.app
    echo "Installed /Applications/MacMischief.app"
    open /Applications/MacMischief.app
    ;;
esac
