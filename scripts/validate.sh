#!/bin/bash
# Run from any directory. Builds never request signing credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/validation .build/module-cache .build/package-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
ARGS=(--cache-path "$PWD/.build/package-cache" --scratch-path "$PWD/.build")
python3 scripts/import_art.py --check-runtime
python3 scripts/test_import_art.py
bash scripts/test.sh
swift build "${ARGS[@]}" -c release 2>&1 | tee .build/validation/release-build.log
plutil -lint PickleBlast.xcodeproj/project.pbxproj WatchApp/Info.plist
python3 scripts/check_project.py
python3 scripts/generate_project.py --check
python3 scripts/check_public_tree.py
python3 scripts/test_public_tree.py
python3 scripts/check_docs.py
python3 scripts/check_site.py
python3 scripts/test_site.py
python3 scripts/sync_privacy.py --check
python3 scripts/test_sync_privacy.py
python3 scripts/sync_boss_policy.py --check
if xcodebuild -version > .build/validation/xcode-version.log 2>&1; then
  xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast -configuration Release -destination 'generic/platform=watchOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO clean build 2>&1 | tee .build/validation/watchos-build.log
else
  printf '%s\n' 'BLOCKED: native watchOS build and simulator validation require full Xcode. See docs/BUILD_AND_TEST.md.'
  exit 2
fi
