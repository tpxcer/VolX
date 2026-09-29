#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { printf '需要 macOS 和 Xcode 26+。\n' >&2; exit 1; }
TARGET_APP="$HOME/Applications/VolX.app"
if pgrep -x MultiOutputVolume >/dev/null; then
  printf '请先退出正在运行的 VolX，再安装。\n' >&2
  exit 1
fi
"$ROOT/scripts/test-portable.sh"
(cd "$ROOT" && swift test)
CONFIGURATION=release "$ROOT/scripts/build-app.sh"
mkdir -p "$HOME/Applications"
# Build and tests finish before touching an existing installation.
if [[ -e "$TARGET_APP" ]]; then
  BACKUP="$HOME/Applications/VolX-backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$TARGET_APP" "$BACKUP"
  printf '旧版备份：%s\n' "$BACKUP"
fi
ditto "$ROOT/.build/VolX.app" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
printf '已安装：%s\n运行：open "%s"\n' "$TARGET_APP" "$TARGET_APP"
