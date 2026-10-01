#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/validation .build/module-cache .build/package-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
FLAGS=(--cache-path "$PWD/.build/package-cache" --scratch-path "$PWD/.build" --disable-xctest --enable-swift-testing)
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
# Standalone Command Line Tools omit these bundled Testing paths from SwiftPM.
# Full Xcode provides its own test framework configuration; no override there.
if [[ "$DEVELOPER_PATH" == */CommandLineTools ]]; then
  FRAMEWORK_PATH="$DEVELOPER_PATH/Library/Developer/Frameworks"
  INTEROP_PATH="$DEVELOPER_PATH/Library/Developer/usr/lib"
  FLAGS+=(-Xswiftc -F -Xswiftc "$FRAMEWORK_PATH" -Xlinker -F -Xlinker "$FRAMEWORK_PATH"
          -Xlinker -rpath -Xlinker "$FRAMEWORK_PATH" -Xlinker -rpath -Xlinker "$INTEROP_PATH")
fi
swift test "${FLAGS[@]}" "$@" 2>&1 | tee .build/validation/tests.log
