# Run on a physical Watch

These instructions are for the copyright holder and developers with written authorization under the source license.

PickleBlast is a standalone watchOS 10 or later app. It runs without a phone companion. Building for a Watch uses your local Xcode account, development team, and paired device setup. Simulator builds need no account; start with [Build and test](docs/BUILD_AND_TEST.md) if you only want to try the game on your Mac.

This guide describes a local development installation. Follow the [physical regression checklist](docs/PHYSICAL_WATCH_TEST.md) after installation.

## Preserve an existing installation

Keep the existing development team and `com.pickleblast.watchapp` bundle identifier. An update should replace the application in place and retain Crown sensitivity, haptic preferences, Arcade best, and boss records. Do not uninstall the app or erase its data during validation. Record the current settings and records before an update and check them afterward.

The public project uses `Configuration/Signing.xcconfig`, which optionally includes ignored `Configuration/Signing.local.xcconfig`. If your local file already works, keep it. Otherwise copy `Configuration/Signing.example.xcconfig` to that local filename and enter the existing team identifier. Do not put account details, credentials, certificates, or provisioning exports in either public configuration or chat. Project regeneration never changes the local override.

Use the existing account and automatic signing in Xcode. Apple's [developer-account overview](https://developer.apple.com/help/account/basics/about-your-developer-account), checked on 2026-09-28, says Personal Team provisioning profiles expire seven days after issuance and need rebuilding and reinstalling. Audit the actual current product rather than relying on an old expiry date. Personal Team device testing does not supply TestFlight or App Store distribution readiness.

## Development-device prerequisites

Select the intended Watch in Xcode's destination menu or Device Hub. Follow any specific trust, unlock, or Developer Mode message on the devices. Apple's [Device Hub guidance](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac), verified on 2026-09-28, describes pairing the companion iPhone first for cable setup and enabling Developer Mode on both the iPhone and Watch for Watch pairing. These development prerequisites do not make the game dependent on an iPhone app.

Keep an already working pairing. Do not change account or certificate settings, revoke certificates, or repeatedly unpair devices to work around an unrelated build or automation failure.

## Build and audit a signed Release

Run from the project directory with the local team configured:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/generate_project.py --check
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast \
  -configuration Release -destination 'generic/platform=watchOS' \
  -derivedDataPath .build/PhysicalRelease clean build
python3 scripts/audit_release.py \
  .build/PhysicalRelease/Build/Products/Release-watchos/PickleBlast.app --expected-build 5
python3 scripts/measure_resources.py \
  .build/PhysicalRelease/Build/Products/Release-watchos/PickleBlast.app
```

Keep signing enabled for this device build. If Xcode reports a missing or expired profile, address that specific requirement locally in Xcode with the existing team and automatic signing. The audit checks the application identity/build, Watch platform, strict signature, expected development entitlements, future profile expiry, privacy manifest, selected resources, and absence of DEBUG activation paths and source/evidence. Its report omits account and device identifiers. A valid development signature is not distribution approval.

## Install, launch, and verify

List devices locally, then choose the identifier of the intended physical Apple Watch:

```sh
xcrun devicectl list devices
WATCH_DEVICE='<intended-physical-watch-identifier>'
bash scripts/install_watch.sh "$WATCH_DEVICE" \
  .build/PhysicalRelease/Build/Products/Release-watchos/PickleBlast.app
```

The helper verifies the signature, installs the app, independently checks its installed record, launches without a debugger, and confirms a running process. It only prints `PASSED` when those checks succeed. Device and signing diagnostics remain under ignored `.build/device-install`; do not share the raw files publicly.

Then open PickleBlast directly from the Watch launcher after stopping any debugger. Confirm a separate relaunch succeeds. Installation/process checks do not establish touch response, gameplay quality, haptic feel, or human playtesting.

For iterative work, open `PickleBlast.xcodeproj`, select **PickleBlast** and the intended Watch, retain automatic signing and the local team, and use **Product > Run** with Debug. Regenerate the project only when source/resource membership changes; the local signing override remains separate.

## Direct on-wrist checks

- Confirm existing records, Crown sensitivity, and haptic preference survive the update.
- Play individual rallies against The Wall, The Banger, The Poacher, The Dinker, and The Lobber. Automatic returns, receiving assistance, court/background, and approved animation should retain their accepted feel.
- In Boss Rally, deliberately miss: the first two saves preserve points; a later miss awards the opponent a point. A match ends at three points. Pause and Resume do not refill saves.
- Choose All Three. A win advances Wall to Banger to Poacher, each starting with two saves; a loss ends the sequence, and Retry starts at Wall.
- Check center and edge contact for one visible paddle, aligned ball departure, immediate Crown reversal at the boundary, and unchanged sensitivity.
- Tap Pause away from the small icon, then Resume and Home. Lower/raise the wrist and interrupt through the system UI; active gameplay must wait for Resume.
- Open Arcade and confirm its waves, scoring, recoveries, cleanup, The Wall, replay, and existing best record still work.
- Check readability and haptics, then basic gameplay without a network connection where your development installation permits it.

Keep simulator results, automated physical results, and human observations distinct. Measure memory, CPU, frame pacing, heat, and battery only with suitable tools; a short battery observation does not establish an improvement.
