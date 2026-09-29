#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"${SWIFTC:-swiftc}" "$ROOT/Sources/MultiOutputVolume/SafeVolumeCore.swift" "$ROOT/Sources/MultiOutputVolume/AudioDevice.swift" "$ROOT/Tests/Portable/main.swift" -o "$TMP/volx-tests"
"$TMP/volx-tests"
