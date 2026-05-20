#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.typeroid.app"
KEYCHAIN_SERVICE="com.typeroid.app"
APP_NAMES=("TypeRoid.app" "typeROID.app")
INSTALL_DIRS=("$HOME/Applications" "/Applications")
SUPPORT_DIR="$HOME/.typeroid"
KEEP_USER_DATA=0

usage() {
    cat <<'USAGE'
Usage: scripts/uninstall-typeroid.sh [--keep-user-data]

Removes typeROID from this Mac:
  - quits running TypeRoid processes
  - removes TypeRoid.app/typeROID.app from ~/Applications and /Applications
  - removes API keys from Keychain
  - removes UserDefaults for com.typeroid.app
  - resets Accessibility and Input Monitoring permissions
  - removes ~/.typeroid unless --keep-user-data is passed
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --keep-user-data)
            KEEP_USER_DATA=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

result=$(osascript <<'APPLESCRIPT'
tell application "System Events"
    activate
    set theResult to button returned of (display dialog "Are you sure you want to uninstall typeROID?

This will remove:
• typeROID from Applications
• All API keys from Keychain
• typeROID settings and preferences
• ~/.typeroid (style, custom commands)" ¬
        buttons {"Cancel", "Uninstall"} ¬
        default button "Cancel" ¬
        cancel button "Cancel" ¬
        with title "Uninstall typeROID" ¬
        with icon caution)
end tell
return theResult
APPLESCRIPT
)

if [ "$result" != "Uninstall" ]; then
    exit 0
fi

echo "Quitting typeROID..."
pkill -x TypeRoid 2>/dev/null || true
pkill -x typeROID 2>/dev/null || true

remove_app_bundle() {
    local path="$1"
    [ -e "$path" ] || return 0

    if rm -rf "$path" 2>/dev/null; then
        echo "Removed $path"
        return 0
    fi

    echo "Admin permission is needed to remove $path"
    osascript - "$path" <<'APPLESCRIPT'
on run argv
    set appPath to item 1 of argv
    do shell script "rm -rf " & quoted form of appPath with administrator privileges
end run
APPLESCRIPT
    echo "Removed $path"
}

echo "Removing installed app bundles..."
for dir in "${INSTALL_DIRS[@]}"; do
    for app in "${APP_NAMES[@]}"; do
        remove_app_bundle "$dir/$app"
    done
done

echo "Removing saved preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "Removing API keys from Keychain..."
for account in openai_api_key anthropic_api_key google_api_key groq_api_key; do
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 || true
done

echo "Resetting macOS privacy permissions..."
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

if [ "$KEEP_USER_DATA" -eq 1 ]; then
    echo "Kept $SUPPORT_DIR"
else
    echo "Removing user data..."
    rm -rf "$SUPPORT_DIR"
    echo "Removed $SUPPORT_DIR"
fi

echo "typeROID has been uninstalled."
