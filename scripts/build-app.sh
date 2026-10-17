#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Lscpu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lscpu" "$APP/Contents/MacOS/Lscpu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift .build/Lscpu.iconset
iconutil -c icns .build/Lscpu.iconset -o "$APP/Contents/Resources/Lscpu.icns"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
printf 'Built %s/dist/Lscpu.app\n' "$PWD"
