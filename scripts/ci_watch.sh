#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"
XCODE_VERSION="unavailable"
REQUIRED_STATUS="pending"
UI_STATUS="not run"

write_summary() {
  local exit_code="$?"
  local result="failed"
  if [[ "$exit_code" -eq 0 ]]; then result="passed"; fi
  if [[ -n "$SUMMARY_PATH" ]]; then
    {
      printf '### PickleBlast Watch validation: %s\n\n' "$result"
      printf -- '- Xcode: `%s`\n' "$XCODE_VERSION"
      printf -- '- Required source and unsigned generic Debug/Release builds: %s\n' "$REQUIRED_STATUS"
      printf -- '- Optional native Watch UI checks: %s\n' "$UI_STATUS"
      printf -- '- Signing: disabled. Unsigned UI result bundles are retained as workflow artifacts for seven days; other products remain in ignored `.build`.\n'
    } >> "$SUMMARY_PATH"
  fi
  return "$exit_code"
}
trap write_summary EXIT

# This route requires full Xcode. Missing tools and real check failures fail CI.
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2 }')"
[[ -n "$XCODE_VERSION" ]] || { printf '%s\n' 'Full Xcode is required.' >&2; exit 2; }
mkdir -p .build/CI

# Includes all portable checks and the unsigned generic watchOS Release build.
bash scripts/validate.sh
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast -configuration Debug \
  -destination 'generic/platform=watchOS' -derivedDataPath .build/CI/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
REQUIRED_STATUS="passed"

# Discover available Watch devices instead of requiring a fixed runtime/model.
# A failed discovery command or malformed inventory is a real failure.
UI_STATUS="discovery failed"
xcrun simctl list devices available -j > .build/CI/simulators.json
SIMULATOR_UDID="$(python3 - .build/CI/simulators.json <<'PYSELECT'
import json
import re
import sys
with open(sys.argv[1]) as source:
    devices = json.load(source)['devices']
choices = []
for runtime, entries in devices.items():
    if '.watchOS-' not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit('.watchOS-', 1)[1].split('-'))
    for device in entries:
        if device.get('isAvailable') and device.get('name', '').startswith('Apple Watch'):
            identifier = device['udid']
            if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', identifier):
                raise SystemExit('Invalid simulator identifier in Xcode inventory.')
            choices.append((version, device['name'], identifier))
if choices:
    print(sorted(choices, key=lambda item: (item[0], item[1]), reverse=True)[0][2])
PYSELECT
)"
if [[ -z "$SIMULATOR_UDID" ]]; then
  UI_STATUS="SKIPPED: no available Watch simulator runtime/device"
  printf '%s\n' "$UI_STATUS"
  exit 0
fi

UI_STATUS="failed"
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast -configuration Debug \
  -destination "platform=watchOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .build/CI/DerivedData \
  -resultBundlePath ".build/CI/watch-ui-$$.xcresult" -collect-test-diagnostics never \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 360 \
  -only-testing:PickleBlastWatchUITests/PickleBlastWatchUITests/testBossRallyHomeOrderRosterAndBack \
  -only-testing:PickleBlastWatchUITests/PickleBlastWatchUITests/testBossRallySelectEachOpponentPauseResumeAndHome \
  -only-testing:PickleBlastWatchUITests/PickleBlastWatchUITests/testScriptedPlayNextAdvancesAllFiveOpponents \
  -only-testing:PickleBlastWatchUITests/PickleBlastWatchUITests/testPrivacyAndSupportScrollBackPreserveSettings \
  -only-testing:PickleBlastWatchUITests/PickleBlastWatchUITests/testPrivacyAndSupportShowReadableAddressesWithoutWebLaunchControls \
  CODE_SIGNING_ALLOWED=NO test
UI_STATUS="passed"
