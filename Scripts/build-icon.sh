#!/bin/bash
set -euo pipefail
STUDYPILOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STUDYPILOT_ICON_BUILD="$STUDYPILOT_ROOT/.build-local/icon-artwork"
mkdir -p "$STUDYPILOT_ROOT/.build-local/ModuleCache" "$STUDYPILOT_ROOT/Resources/Brand"
export CLANG_MODULE_CACHE_PATH="$STUDYPILOT_ROOT/.build-local/ModuleCache"
swift "$STUDYPILOT_ROOT/Scripts/render-icon.swift" "$STUDYPILOT_ICON_BUILD"
iconutil -c icns "$STUDYPILOT_ICON_BUILD/StudyPilot.iconset" -o "$STUDYPILOT_ROOT/Resources/StudyPilot.icns"
cp "$STUDYPILOT_ICON_BUILD/StudyPilot-icon.png" "$STUDYPILOT_ROOT/Resources/Brand/StudyPilot-icon.png"
