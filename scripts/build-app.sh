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
  <string>TypeRoid</string>
  <key>CFBundleDisplayName</key>
  <string>TypeRoid</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>TypeRoid uses automation-style keyboard actions to clean and replace text where you type.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>TypeRoid watches for your cleanup trigger so it can fix text when you type it.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>TypeRoid uses Accessibility to select and replace the text you ask it to clean.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
