#!/usr/bin/env bash
# Remove Nota from /Applications and forget the permissions it was granted.
set -euo pipefail

APP_NAME="Nota"
BUNDLE_ID="dev.nota.Nota"
DEST="/Applications/${APP_NAME}.app"

say() { printf '\033[38;5;108m%s\033[0m\n' "$*"; }

if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null; then
  say "Quitting ${APP_NAME}..."
  osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
  sleep 1
  pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
fi

if [[ -d "$DEST" ]]; then
  say "Removing ${DEST}..."
  rm -rf "$DEST"
else
  say "Nothing installed at ${DEST}."
fi

say "Resetting privacy grants..."
for service in Accessibility ScreenCapture Microphone AppleEvents; do
  tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
done

say "Done. The source tree and its build directory were left alone."
