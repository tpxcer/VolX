#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/.build/VolX.app"
TARGET_APP="/Applications/VolX.app"

"$ROOT/scripts/build-app.sh" >/dev/null
ditto "$SOURCE_APP" "$TARGET_APP"

echo "$TARGET_APP"
