#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Pulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pulse" "$APP/Contents/MacOS/Pulse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift .build/Pulse.iconset
iconutil -c icns .build/Pulse.iconset -o "$APP/Contents/Resources/Pulse.icns"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
printf 'Built %s/dist/Pulse.app\n' "$PWD"
