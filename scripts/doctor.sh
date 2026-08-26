#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLED_APP="/Applications/VolX.app/Contents/MacOS/MultiOutputVolume"
DEBUG_BIN="$ROOT/.build/debug/MultiOutputVolume"

if [[ -x "$INSTALLED_APP" ]]; then
  BIN="$INSTALLED_APP"
elif [[ -x "$DEBUG_BIN" ]]; then
  BIN="$DEBUG_BIN"
else
  "$ROOT/scripts/build-app.sh" >/dev/null
  BIN="$DEBUG_BIN"
fi

"$BIN" --doctor
"$BIN" --check-interface
