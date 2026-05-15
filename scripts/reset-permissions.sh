#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-$HOME/TypeRoid/build/TypeRoid.app}"
BUNDLE_ID="com.typeroid.app"

echo "Quitting TypeRoid..."
pkill TypeRoid 2>/dev/null || true

echo "Resetting macOS privacy entries for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true

echo "Opening privacy settings..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

echo
echo "In both Accessibility and Input Monitoring, add and enable:"
echo "$APP_PATH"
echo
echo "After both toggles are enabled, relaunch with:"
echo "open \"$APP_PATH\""
