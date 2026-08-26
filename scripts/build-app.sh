#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/VolX.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
CONFIGURATION="${CONFIGURATION:-debug}"

cd "$ROOT"
swift build -c "$CONFIGURATION"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  swift "$ROOT/scripts/generate-app-icon.swift" >/dev/null
fi

mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/.build/$CONFIGURATION/MultiOutputVolume" "$MACOS/MultiOutputVolume"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
chmod +x "$MACOS/MultiOutputVolume"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
