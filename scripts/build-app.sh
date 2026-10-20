#!/usr/bin/env bash
# Builds Emebal in release mode and wraps the binary into build/Emebal.app.
# A menu-bar app needs a real .app bundle (Info.plist with LSUIElement), which
# `swift build` alone does not produce.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/Emebal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$(swift build -c release --show-bin-path)/Emebal" "$APP/Contents/MacOS/Emebal"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS can remember the Accessibility permission
# for this app between launches.
codesign --force --sign - "$APP"

echo "Built $APP"
