#!/usr/bin/env bash
# Build Kuroko in Release and install it into /Applications so Spotlight and
# Launchpad can find it. Safe to re-run; replaces any existing install.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Kuroko"
BUNDLE_ID="dev.kuroko.Kuroko"
DEST="/Applications/${APP_NAME}.app"

say() { printf '\033[38;5;108m%s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m%s\033[0m\n' "$*"; }
die() {
  printf '\033[38;5;167m%s\033[0m\n' "$*" >&2
  exit 1
}

# ── Preflight ─────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Darwin" ]] || die "Kuroko is macOS only."
[[ "$(uname -m)" == "arm64" ]] || die "Kuroko needs Apple Silicon."

command -v xcodebuild >/dev/null || die "xcodebuild not found. Install Xcode."
command -v xcodegen >/dev/null || die "xcodegen not found. Run: brew install xcodegen"

if [[ "$(xcode-select -p)" != *"Xcode.app"* ]]; then
  die "xcode-select points at the Command Line Tools. Run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

# A real certificate is what keeps Screen Recording and Accessibility grants
# alive across rebuilds; see the signing notes in README.md.
if ! security find-identity -v -p codesigning | grep -q "Apple Development"; then
  warn "No valid Apple Development identity found."
  if security find-identity -p codesigning | grep -q "Apple Development"; then
    die "A certificate exists but is invalid, usually a missing WWDR G3 intermediate:
  curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
  security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer"
  fi
  die "Add an Apple ID in Xcode > Settings > Accounts, then
Manage Certificates > + > Apple Development."
fi

# ── Build ─────────────────────────────────────────────────────────────────
cd "$REPO"
say "Generating project..."
xcodegen generate >/dev/null

say "Building Release (this takes a minute)..."
# Deliberately using Xcode's default DerivedData rather than a path inside the
# repo. Apple already excludes DerivedData from Spotlight; a build directory
# here gets indexed, and then searching "Kuroko" returns several identical
# looking apps. A .metadata_never_index marker does not reliably prevent it.
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
  -configuration Release build >/tmp/kuroko-install.log 2>&1 ||
  die "Build failed. See /tmp/kuroko-install.log"

PRODUCTS_DIR="$(
  xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Release -showBuildSettings 2>/dev/null |
    awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}'
)"
BUILT="${PRODUCTS_DIR}/${APP_NAME}.app"

[[ -d "$BUILT" ]] || die "Expected app at $BUILT but it is missing."

# ── Install ───────────────────────────────────────────────────────────────
# Quit the running copy first, or the replaced bundle keeps running from a
# deleted path and the menu-bar icon stops responding.
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null; then
  say "Quitting the running copy..."
  osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
  sleep 1
  pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
fi

say "Installing to ${DEST}..."
rm -rf "$DEST"
# ditto rather than cp: it preserves the code signature and extended attributes.
ditto "$BUILT" "$DEST"

codesign --verify --deep --strict "$DEST" ||
  die "Installed app fails signature verification."

# Drop the bundle we just copied out of DerivedData. Spotlight indexes it on
# some machines, and a second identical "Kuroko" in the launcher is confusing.
# Only the .app goes; the compiled object files stay cached, so the next build
# just relinks rather than starting over.
rm -rf "$BUILT"

# Nudge Launch Services so Spotlight indexes it immediately rather than
# whenever it next feels like it.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" 2>/dev/null || true

say "Installed. Launching..."
open "$DEST"

cat <<EOF

$(say "${APP_NAME} is in /Applications and will show up in Spotlight.")

If this is the first install, grant its permissions once:
  Menu bar eye icon > Grant Permissions

To have it start with the Mac: Settings (Cmd-comma) > Launch Kuroko at login.
EOF
