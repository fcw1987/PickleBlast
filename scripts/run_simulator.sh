#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  printf '%s\n' 'Usage: bash scripts/run_simulator.sh <Watch-device-UDID from xcrun simctl list devices available>'
  exit 2
fi
DEVICE_ID="$1"
xcodebuild -version
xcrun simctl list devices available
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast -configuration Debug \
  -destination "platform=watchOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
# bootstatus -b boots an unbooted selected device and waits until usable.
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" .build/DerivedData/Build/Products/Debug-watchsimulator/PickleBlast.app
xcrun simctl launch "$DEVICE_ID" com.pickleblast.watchapp
