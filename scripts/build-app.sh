#!/usr/bin/env bash
# Builds Emebal in release mode and wraps the binary into build/Emebal.app.
# A menu-bar app needs a real .app bundle (Info.plist with LSUIElement), which
# `swift build` alone does not produce.
set -euo pipefail

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
