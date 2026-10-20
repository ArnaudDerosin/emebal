#!/usr/bin/env bash
# Builds Emebal in release mode and wraps the binary into build/Emebal.app.
# A menu-bar app needs a real .app bundle (Info.plist with LSUIElement), which
# `swift build` alone does not produce.
#
# With --install, moves the app to /Applications and opens it from there.
set -euo pipefail

INSTALL=false
case "${1:-}" in
  "") ;;
  --install) INSTALL=true ;;
  *) echo "Usage: $0 [--install]" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

swift build -c release

APP="build/Emebal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/Emebal" "$APP/Contents/MacOS/Emebal"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Emebal.icns "$APP/Contents/Resources/Emebal.icns"

# macOS ties the Accessibility permission to the app's signature. An ad-hoc
# signature changes on every build, so the permission is lost after each
# rebuild. Set EMEBAL_SIGN_IDENTITY to a stable code-signing identity (for
# example a self-signed "Emebal Local Signing" certificate) to keep it.
IDENTITY="${EMEBAL_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"

if [ "$IDENTITY" = "-" ]; then
  echo "Built $APP (ad-hoc signed: re-allow Accessibility after each rebuild)"
else
  echo "Built $APP (signed with \"$IDENTITY\")"
fi

if [ "$INSTALL" = true ]; then
  # Quit the running copy, then move (not copy) the app, so /Applications holds
  # the only one: two copies with the same bundle ID confuse macOS about which
  # one is Emebal, for example which icon System Settings shows.
  if pgrep -xq Emebal; then
    osascript -e 'quit app id "io.github.arnaudderosin.emebal"' || true
    while pgrep -xq Emebal; do sleep 0.2; done
  fi
  rm -rf /Applications/Emebal.app
  mv "$APP" /Applications/Emebal.app
  open /Applications/Emebal.app
  echo "Installed /Applications/Emebal.app"
fi
