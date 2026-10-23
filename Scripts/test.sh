#!/bin/bash
set -euo pipefail
STUDYPILOT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STUDYPILOT_BUILD="${STUDYPILOT_BUILD_DIR:-$STUDYPILOT_ROOT/.build-tests}"
STUDYPILOT_DEVELOPER="$(xcode-select -p)"
mkdir -p "$STUDYPILOT_BUILD"
export CLANG_MODULE_CACHE_PATH="$STUDYPILOT_BUILD/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
STUDYPILOT_ARGS=(--package-path "$STUDYPILOT_ROOT" --scratch-path "$STUDYPILOT_BUILD/build" --cache-path "$STUDYPILOT_BUILD/cache" --config-path "$STUDYPILOT_BUILD/config" --security-path "$STUDYPILOT_BUILD/security" --disable-sandbox --disable-xctest)
if [[ "$STUDYPILOT_DEVELOPER" == *CommandLineTools* ]]; then
    export STUDYPILOT_TESTS_ONLY=1
    STUDYPILOT_FRAMEWORKS="$STUDYPILOT_DEVELOPER/Library/Developer/Frameworks"
    STUDYPILOT_ARGS+=(-Xswiftc -F -Xswiftc "$STUDYPILOT_FRAMEWORKS" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -rpath -Xlinker "$STUDYPILOT_FRAMEWORKS")
fi
swift test "${STUDYPILOT_ARGS[@]}" "$@"
