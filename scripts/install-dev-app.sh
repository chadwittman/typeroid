#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$REPO_ROOT/build/TypeRoid.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/TypeRoid.app"

cd "$REPO_ROOT"

bash ./scripts/build-app.sh

echo "Quitting running TypeRoid instances..."
pkill TypeRoid 2>/dev/null || true

mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

echo "Installed $DEST_APP"
echo
echo "Grant Accessibility and Input Monitoring to this stable app path:"
echo "$DEST_APP"
echo
echo "Launching TypeRoid..."
open "$DEST_APP"
