#!/usr/bin/env bash
# build-dmg.sh — Create a styled drag-to-install DMG for typeROID
#
# Goal: Slack/Discord-style DMG with:
#   - Branded background image (build/dmg_background.png)
#   - TypeRoid.app icon on the left
#   - /Applications symlink on the right
#   - Window size ~600x400, icon size 96px
#
# TODO: AppleScript approach failed with error -10006.
# Replace this stub with a working implementation using one of:
#   - create-dmg (npm install -g create-dmg)
#   - appdmg (npm install -g appdmg)
#   - hdiutil + Python DS_Store manipulation
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/TypeRoid.app"
BACKGROUND="$BUILD/dmg_background.png"
OUT="$BUILD/typeROID.dmg"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run build-app.sh first."
    exit 1
fi

echo "Building DMG..."

# TODO: implement styled DMG here
# Example with create-dmg:
#   create-dmg \
#     --volname "typeROID" \
#     --background "$BACKGROUND" \
#     --window-size 600 400 \
#     --icon-size 96 \
#     --icon "TypeRoid.app" 150 200 \
#     --app-drop-link 450 200 \
#     "$OUT" \
#     "$APP"

echo "Error: build-dmg.sh is not yet implemented." >&2
exit 1
