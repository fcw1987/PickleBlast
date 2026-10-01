#!/bin/bash
# Explicit DEBUG fixtures; these captures do not prove ordinary navigation.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 2 ]] || { echo 'Usage: capture_simulator.sh <booted-watch-udid> <output-directory>' >&2; exit 2; }
WATCH_SIM="$1"
EVIDENCE="$2"
mkdir -p "$EVIDENCE"
for fixture in wave1 wave2 wave3 forehand backhand block boss boss-contact receiving saved charged-miss cleanup combo cascade blackout forehand-left forehand-right backhand-left backhand-right; do
  xcrun simctl launch --terminate-running-process "$WATCH_SIM" com.pickleblast.watchapp --validation-fixture "$fixture"
  sleep 2
  xcrun simctl io "$WATCH_SIM" screenshot "$EVIDENCE/$fixture.png"
done
# Never leave a validation fixture running after evidence capture.
xcrun simctl launch --terminate-running-process "$WATCH_SIM" com.pickleblast.watchapp
