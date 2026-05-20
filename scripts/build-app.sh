#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/build/TypeRoid.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp "$ROOT/.build/release/TypeRoid" "$MACOS/TypeRoid"
chmod +x "$MACOS/TypeRoid"

# Resources
RESOURCES="$CONTENTS/Resources"
mkdir -p "$RESOURCES"
if [ -f "$ROOT/AppIcon.icns" ]; then
    cp "$ROOT/AppIcon.icns" "$RESOURCES/AppIcon.icns"
elif [ -f "$ROOT/icon.png" ]; then
    sips -s format icns "$ROOT/icon.png" --out "$RESOURCES/AppIcon.icns" 2>/dev/null || true
fi
# Copy branding assets
for asset in logo.png banner.png; do
    src="$ROOT/Sources/TypeRoidApp/$asset"
    [ -f "$src" ] && cp "$src" "$RESOURCES/$asset"
done

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TypeRoid</string>
  <key>CFBundleIdentifier</key>
  <string>com.typeroid.app</string>
  <key>CFBundleName</key>
  <string>typeROID</string>
  <key>CFBundleDisplayName</key>
  <string>typeROID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.7</string>
  <key>CFBundleVersion</key>
  <string>8</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>TypeRoid uses automation-style keyboard actions to clean and replace text where you type.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>TypeRoid watches for your cleanup trigger so it can fix text when you type it.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>TypeRoid uses Accessibility to select and replace the text you ask it to clean.</string>
</dict>
</plist>
PLIST

DMG="$ROOT/build/typeROID.dmg"

# --- Signing & Notarization ---
# Requires env vars: TYPEROID_APPLE_ID, TYPEROID_NOTARY_PASSWORD, TYPEROID_TEAM_ID
# Add to ~/.zshrc:
#   export TYPEROID_APPLE_ID="you@example.com"
#   export TYPEROID_NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password
#   export TYPEROID_TEAM_ID="XXXXXXXXXX"
DEVELOPER_ID="${TYPEROID_DEVELOPER_ID:-Developer ID Application: Applum, LLC (P5TCS8AHVW)}"
HAS_DEVELOPER_ID=0
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEVELOPER_ID"; then
    HAS_DEVELOPER_ID=1
fi

if [ "$HAS_DEVELOPER_ID" -eq 1 ] && [ -n "${TYPEROID_APPLE_ID:-}" ] && [ -n "${TYPEROID_NOTARY_PASSWORD:-}" ] && [ -n "${TYPEROID_TEAM_ID:-}" ]; then
    echo "Signing with Developer ID..."
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEVELOPER_ID" "$APP_DIR"

    echo "Building DMG..."
    SIGNING_IDENTITY="$DEVELOPER_ID" bash "$ROOT/scripts/build-dmg.sh"

    echo "Notarizing DMG..."
    xcrun notarytool submit "$DMG" \
        --apple-id "$TYPEROID_APPLE_ID" \
        --password "$TYPEROID_NOTARY_PASSWORD" \
        --team-id "$TYPEROID_TEAM_ID" \
        --wait

    echo "Stapling..."
    xcrun stapler staple "$DMG"

    echo "Done: $DMG (signed + notarized)"
elif [ "$HAS_DEVELOPER_ID" -eq 1 ]; then
    echo "Signing with Developer ID..."
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEVELOPER_ID" "$APP_DIR"

    echo "Building signed DMG..."
    SIGNING_IDENTITY="$DEVELOPER_ID" bash "$ROOT/scripts/build-dmg.sh"

    echo "No notarization credentials found."
    echo "Set TYPEROID_APPLE_ID, TYPEROID_NOTARY_PASSWORD, TYPEROID_TEAM_ID to notarize."
    echo "Built $DMG (signed, not notarized)"
else
    echo "No Developer ID identity found — using ad-hoc signature."
    echo "Set TYPEROID_DEVELOPER_ID or install the Developer ID certificate to sign."
    codesign --force --deep --sign - "$APP_DIR"
    echo "Building unsigned DMG..."
    bash "$ROOT/scripts/build-dmg.sh"
    echo "Built $DMG (unsigned)"
fi
