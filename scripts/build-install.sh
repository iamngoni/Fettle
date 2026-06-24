#!/bin/bash
# Build Fettle (Release), install to /Applications, relaunch.
# Usage: scripts/build-install.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

echo "▸ Building Fettle (Release)…"
xcodebuild -project Fettle.xcodeproj -scheme Fettle -configuration Release \
  -derivedDataPath build -quiet CODE_SIGNING_ALLOWED=YES build

APP="$ROOT/build/Build/Products/Release/Fettle.app"
[ -d "$APP" ] || { echo "✗ Build product missing: $APP"; exit 1; }

echo "▸ Quitting running Fettle…"
osascript -e 'tell application "Fettle" to quit' >/dev/null 2>&1 || true
pkill -x Fettle >/dev/null 2>&1 || true
sleep 1

echo "▸ Installing to /Applications…"
rm -rf "/Applications/Fettle.app"
cp -R "$APP" "/Applications/Fettle.app"

echo "▸ Launching…"
open "/Applications/Fettle.app"
echo "✓ Installed $(defaults read /Applications/Fettle.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo '?') — check the menu bar."
