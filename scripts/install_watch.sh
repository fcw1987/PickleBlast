#!/bin/bash
# Install a development-signed native Watch app with the selected Xcode tools.
# Build/sign separately; this helper never selects a team or accesses credentials.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf '%s\n' 'Usage: bash scripts/install_watch.sh <WATCH_DEVICE> <signed-watchOS-app.app>' >&2
  exit 2
fi

WATCH_DEVICE="$1"
WATCH_APP="$2"
SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$WATCH_APP" != /* ]]; then
  WATCH_APP="$PWD/$WATCH_APP"
fi
if [[ ! -d "$WATCH_APP" || "$WATCH_APP" != *.app || ! -f "$WATCH_APP/Info.plist" ]]; then
  printf '%s\n' 'FAILED: provide the built signed device .app directory.' >&2
  exit 2
fi

# Prefer a caller-selected Xcode; never change the global developer directory.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
umask 077
mkdir -p "$SCRIPT_ROOT/.build/device-install"
WATCH_EVIDENCE="$(mktemp -d "$SCRIPT_ROOT/.build/device-install/run.XXXXXX")"

fail() {
  printf 'FAILED: %s\nPrivate local evidence: %s\n' "$1" "$WATCH_EVIDENCE" >&2
  exit 1
}

platform="$(/usr/bin/plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$WATCH_APP/Info.plist" 2>/dev/null)" \
  || fail 'The app has no compiled platform metadata.'
[[ "$platform" == WatchOS ]] || fail 'The app is not a watchOS device build; simulator bundles cannot be installed.'
bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$WATCH_APP/Info.plist")"
[[ "$bundle_id" == com.pickleblast.watchapp ]] || fail 'The supplied app is not the PickleBlast application.'
[[ -f "$WATCH_APP/embedded.mobileprovision" ]] || fail 'The app has no embedded device provisioning profile.'

/usr/bin/codesign --verify --deep --strict "$WATCH_APP" > "$WATCH_EVIDENCE/signature-check.log" 2>&1 \
  || fail 'Code-signature verification failed.'
/usr/bin/codesign --display --entitlements - --xml "$WATCH_APP" \
  > "$WATCH_EVIDENCE/entitlements.plist" 2> "$WATCH_EVIDENCE/signature-details.log" \
  || fail 'Unable to inspect the app signature.'
development="$(/usr/bin/plutil -extract get-task-allow raw -o - "$WATCH_EVIDENCE/entitlements.plist" 2>/dev/null)" \
  || fail 'The signature does not contain a development entitlement.'
[[ "$development" == true ]] || fail 'The supplied app is not a development-signed build.'
if ! /usr/bin/python3 -c 'import plistlib, sys
with open(sys.argv[1], "rb") as source: entitlements = plistlib.load(source)
team = entitlements.get("com.apple.developer.team-identifier")
sys.exit(0 if isinstance(team, str) and team else 1)' "$WATCH_EVIDENCE/entitlements.plist"; then
  fail 'The signature has no development team entitlement.'
fi
/usr/bin/codesign --display --verbose=4 "$WATCH_APP" > "$WATCH_EVIDENCE/signing-authority.log" 2>&1 \
  || fail 'Unable to inspect the signing authority.'
if ! /usr/bin/grep -q '^Authority=' "$WATCH_EVIDENCE/signing-authority.log"; then
  fail 'The app has no certificate signing authority; ad hoc signatures cannot be installed.'
fi

run_device_step() {
  local step="$1"
  shift
  local category="$1" operation="$2" verb="$3"
  shift 3
  # Launch treats arguments after the bundle identifier as app arguments.
  # Put CoreDevice options before all positional command arguments.
  if ! /usr/bin/xcrun devicectl "$category" "$operation" "$verb" \
       --quiet --timeout 120 --json-output "$WATCH_EVIDENCE/$step.json" \
       "$@" > "$WATCH_EVIDENCE/$step.log" 2>&1; then
    fail "$step did not succeed. Inspect its local JSON/log for the exact device or signing requirement."
  fi
}

run_device_step install device install app --device "$WATCH_DEVICE" "$WATCH_APP"
run_device_step installed-app device info apps --device "$WATCH_DEVICE" --bundle-id "$bundle_id"

# Verification queries must contain an actual result, not only succeed as commands.
# Inspect actual app records, never result.matchingBundleIdentifier, which is
# merely an echoed filter and is present even when result.apps is empty.
if ! /usr/bin/plutil -extract result.apps json -o - "$WATCH_EVIDENCE/installed-app.json" \
    | /usr/bin/python3 -c 'import json, sys
def values(node):
    if isinstance(node, dict):
        for value in node.values(): yield from values(value)
    elif isinstance(node, list):
        for value in node: yield from values(value)
    else: yield node
apps = json.load(sys.stdin)
matched = isinstance(apps, list) and any(
    isinstance(app, dict) and (
        app.get("bundleIdentifier") == sys.argv[1] or
        ("bundleIdentifier" not in app and sys.argv[1] in values(app))
    ) for app in apps)
sys.exit(0 if matched else 1)' "$bundle_id"; then
  fail 'The independent installed-app query did not find PickleBlast.'
fi

# No --console or --start-stopped: launch normally without attaching a debugger.
run_device_step launch device process launch --device "$WATCH_DEVICE" "$bundle_id"
run_device_step running-process device info processes --device "$WATCH_DEVICE" --search PickleBlast
# CoreDevice returns process records in result.runningProcesses. Metadata and
# search echoes outside that list cannot establish a running application.
if ! /usr/bin/plutil -extract result.runningProcesses json -o - "$WATCH_EVIDENCE/running-process.json" \
    | /usr/bin/python3 -c 'import json, sys
def is_pickleblast_process(process):
    if not isinstance(process, dict): return False
    pid = process.get("processIdentifier")
    if type(pid) is not int or pid <= 0: return False
    strings = [value for value in process.values() if isinstance(value, str)]
    return any(value == "PickleBlast" or value.endswith("/PickleBlast.app/PickleBlast") for value in strings)
running = json.load(sys.stdin)
sys.exit(0 if isinstance(running, list) and any(is_pickleblast_process(process) for process in running) else 1)'; then
  fail 'The independent process query did not find a running PickleBlast process.'
fi

printf 'PASSED: signature verification, installation, installed-app lookup, launch, and process lookup.\nPrivate local evidence: %s\n' "$WATCH_EVIDENCE"
printf '%s\n' 'Physical Crown, touch, haptics, and independent relaunch from the Watch still require direct checks.'
