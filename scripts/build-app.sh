#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/VolX.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
CONFIGURATION="${CONFIGURATION:-release}"
[[ "$(uname -s)" == Darwin ]] || { printf 'macOS required\n' >&2; exit 1; }
# NSGlassEffectView requires the macOS 26 SDK, even with runtime availability guards.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[[ "${SDK_VERSION%%.*}" -ge 26 ]] || { printf '需要 Xcode 26+ 的 macOS SDK\n' >&2; exit 1; }

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
