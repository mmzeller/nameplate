#!/bin/bash
# Builds Nameplate.app from source.
#
#   ./build.sh                build, install to /Applications, link the `nameplate` command, launch it
#   ./build.sh --no-install   build only (result: build/Nameplate.app)
#   ./build.sh --pkg          also make build/Nameplate-<version>.pkg for NinjaOne / MDM deployment
#   ./build.sh --universal    one binary for Apple silicon and Intel (needs the full Xcode app)
#
# Needs Apple's command-line developer tools (xcode-select --install) or Xcode, macOS 13 or later.
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=1
UNIVERSAL=0
PKG=0
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --universal) UNIVERSAL=1 ;;
    --pkg) PKG=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run:  xcode-select --install   then run ./build.sh again."
  exit 1
fi

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/NameplateCore/Models.swift)
BUILD=$(date +%Y%m%d%H%M)
ARCH_FLAGS=""
if [ "$UNIVERSAL" = 1 ]; then ARCH_FLAGS="--arch arm64 --arch x86_64"; fi

echo "==> Compiling Nameplate $VERSION (first build takes a minute or two)"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN=$(swift build -c release $ARCH_FLAGS --show-bin-path)

APP=build/Nameplate.app
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Nameplate" "$APP/Contents/MacOS/Nameplate"
cp "$BIN/NameplateCLI" "$APP/Contents/Helpers/nameplate"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
if ! iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    (couldn't build the icon; carrying on without it)"
fi

echo "==> Signing (ad hoc, so macOS will run it on this Mac)"
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/nameplate"
codesign --force --sign - --timestamp=none "$APP"

if [ "$PKG" = 1 ]; then
  echo "==> Making the installer package"
  rm -rf build/pkgroot build/pkg-scripts build/component.plist
  mkdir -p build/pkgroot/Applications build/pkg-scripts
  ditto "$APP" build/pkgroot/Applications/Nameplate.app
  cat > build/pkg-scripts/postinstall <<'EOS'
#!/bin/bash
# Link the command-line tool and start Nameplate for whoever is logged in.
mkdir -p /usr/local/bin
ln -sf "/Applications/Nameplate.app/Contents/Helpers/nameplate" /usr/local/bin/nameplate
console_user=$(stat -f %Su /dev/console)
if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ "$console_user" != "loginwindow" ]; then
  uid=$(id -u "$console_user")
  launchctl asuser "$uid" sudo -u "$console_user" open -g "/Applications/Nameplate.app" || true
fi
exit 0
EOS
  chmod +x build/pkg-scripts/postinstall
  pkgbuild --analyze --root build/pkgroot build/component.plist >/dev/null
  /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" build/component.plist
  pkgbuild --root build/pkgroot --component-plist build/component.plist --install-location / \
    --identifier com.mmzeller.Nameplate --version "$VERSION" --scripts build/pkg-scripts \
    "build/Nameplate-$VERSION.pkg" >/dev/null
  echo "    build/Nameplate-$VERSION.pkg"
fi

if [ "$INSTALL" = 1 ]; then
  DEST=/Applications
  if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; fi
  mkdir -p "$DEST"
  echo "==> Installing to $DEST"
  if pgrep -x Nameplate >/dev/null 2>&1; then
    pkill -x Nameplate || true
    sleep 1
  fi
  rm -rf "$DEST/Nameplate.app"
  ditto "$APP" "$DEST/Nameplate.app"

  TOOL="$DEST/Nameplate.app/Contents/Helpers/nameplate"
  if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    ln -sf "$TOOL" /usr/local/bin/nameplate
    echo "    Linked /usr/local/bin/nameplate"
  else
    echo "    For the 'nameplate' Terminal command, right-click the menu bar icon and choose"
    echo "    Install Command-Line Tool…, or run:"
    echo "    sudo mkdir -p /usr/local/bin && sudo ln -sf \"$TOOL\" /usr/local/bin/nameplate"
  fi
  open "$DEST/Nameplate.app"
  echo "==> Done. Nameplate is running; look for its icon in the menu bar."
else
  echo "==> Built $APP"
fi
