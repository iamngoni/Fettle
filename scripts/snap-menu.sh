#!/bin/bash
# Open the Fettle menu-bar popover and screenshot it, so the UI can be verified
# after a build. Requires the controlling terminal to have Accessibility access
# (System Settings → Privacy & Security → Accessibility).
# Usage: scripts/snap-menu.sh [output.png]
set -euo pipefail

OUT="${1:-/tmp/fettle-menu.png}"

osascript -e 'tell application "System Events" to tell process "Fettle" to perform action "AXPress" of menu bar item 1 of menu bar 2' \
  || { echo "✗ Could not open the menu (grant this terminal Accessibility access)."; exit 1; }

sleep 0.6
screencapture -x "$OUT"
echo "✓ Captured $OUT"
