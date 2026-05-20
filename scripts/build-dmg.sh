#!/usr/bin/env bash
# build-dmg.sh — Create a styled drag-to-install DMG for typeROID using dmgbuild.
# dmgbuild writes DS_Store directly (no Finder/AppleScript) so background works on any Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/TypeRoid.app"
BACKGROUND="$BUILD/dmg_background.png"
OUT="$BUILD/typeROID.dmg"
SETTINGS="$BUILD/dmg_settings.py"
DEFAULT_SIGNING_IDENTITY="${TYPEROID_DEVELOPER_ID:-Developer ID Application: Applum, LLC (P5TCS8AHVW)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run build-app.sh first."
    exit 1
fi

if [ ! -f "$BACKGROUND" ]; then
    echo "Error: $BACKGROUND not found."
    exit 1
fi

if ! command -v dmgbuild >/dev/null 2>&1; then
    echo "Error: dmgbuild not found. Run: pip3 install dmgbuild --break-system-packages"
    exit 1
fi

if [ -z "$SIGNING_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEFAULT_SIGNING_IDENTITY"; then
    SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
fi

rm -f "$OUT" "$SETTINGS"

cat > "$SETTINGS" <<PYEOF
import os

application = '$APP'
appname = 'typeROID.app'

# Output
filename = '$OUT'
volume_name = 'typeROID'

# Appearance
format = 'UDZO'
filesystem = 'HFS+'
size = None

files = [(application, appname)]
symlinks = {'Applications': '/Applications'}

icon_locations = {
    appname:        (140, 280),
    'Applications': (624, 280),
}

background = '$BACKGROUND'

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180

window_rect = ((100, 100), (764, 509))

default_view = 'icon-view'
show_icon_preview = False

icon_size = 96
text_size = 12
arrange_by = None
PYEOF

echo "Building DMG at $OUT..."
dmgbuild -s "$SETTINGS" "typeROID" "$OUT"

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing DMG..."
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUT"
fi

echo "Done: $OUT"
