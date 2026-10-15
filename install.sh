#!/bin/bash
# Installs or updates Nameplate from the latest GitHub release. No developer tools needed.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/mmzeller/nameplate/main/install.sh)
#
# Run the same line again any time to update.
set -euo pipefail

ZIP_URL="https://github.com/mmzeller/nameplate/releases/latest/download/Nameplate.zip"

bold() { printf "\n\033[1m%s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m%s\033[0m\n" "$1"; exit 1; }

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 13 ]; then
  fail "Nameplate needs macOS 13 Ventura or newer. This Mac has $(sw_vers -productVersion)."
fi

DEST=/Applications
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bold "Downloading the latest Nameplate…"
if ! curl -fL --progress-bar -o "$WORK/Nameplate.zip" "$ZIP_URL"; then
  fail "Couldn't download Nameplate. Check your internet connection, or see https://github.com/mmzeller/nameplate/releases"
fi
ditto -x -k "$WORK/Nameplate.zip" "$WORK"
[ -d "$WORK/Nameplate.app" ] || fail "The download didn't contain Nameplate.app."

if pgrep -x Nameplate >/dev/null 2>&1; then
  bold "Quitting the running copy…"
  osascript -e 'tell application id "com.mmzeller.Nameplate" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -x Nameplate >/dev/null 2>&1 || break
    sleep 1
  done
  pkill -x Nameplate 2>/dev/null || true
fi

bold "Installing to $DEST…"
rm -rf "$DEST/Nameplate.app"
ditto "$WORK/Nameplate.app" "$DEST/Nameplate.app"
xattr -dr com.apple.quarantine "$DEST/Nameplate.app" 2>/dev/null || true
open "$DEST/Nameplate.app"

version=$(defaults read "$DEST/Nameplate.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
bold "Nameplate ${version} is installed and running. Look for its icon in the menu bar."

# The `nameplate` Terminal command (optional).
TOOL="$DEST/Nameplate.app/Contents/Helpers/nameplate"
LINK=/usr/local/bin/nameplate
if [ "$(readlink "$LINK" 2>/dev/null || true)" = "$TOOL" ]; then
  exit 0
fi
if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  ln -sf "$TOOL" "$LINK"
  echo "Added the 'nameplate' Terminal command."
  exit 0
fi
printf "\nAlso add the 'nameplate' command for Terminal? It needs your Mac password. [y/N] "
read -r reply < /dev/tty || reply=""
case "$reply" in
  [yY]*)
    if sudo mkdir -p /usr/local/bin && sudo ln -sf "$TOOL" "$LINK"; then
      echo "Added. Try:  nameplate"
    else
      echo "Skipped. You can add it later from the menu bar icon: right-click › Install Command-Line Tool…"
    fi
    ;;
  *)
    echo "Skipped. You can add it later from the menu bar icon: right-click › Install Command-Line Tool…"
    ;;
esac
