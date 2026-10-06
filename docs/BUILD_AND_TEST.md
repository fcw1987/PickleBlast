# Build and test

These instructions are for the copyright holder and developers with written authorization under the source license.

PickleBlast ships as a standalone Watch app. Open `PickleBlast.xcodeproj`, select the shared **PickleBlast** scheme, and choose a Watch destination. The Swift package supplies the game core, renderer, and host tests; opening `Package.swift` does not replace the native Watch project.

## Requirements and verified compatibility

The configured application minimum is **watchOS 10.0**. The verified local toolchain is **Xcode 27.0**, with watchOS and Watch Simulator 27.0 SDKs. Native validation uses an Ultra 4 (49 mm) and SE 3 (40 mm) simulator on watchOS 27.0. These tested displays do not establish compatibility testing on every Watch or older OS release. See [Testing](TESTING.md) for regression coverage and physical validation limits.

Use a Mac supported by the selected full Xcode installation, Python 3.9 or later, and its bundled Swift compiler. The application has no external Swift packages or runtime services. Project generation and asset verification use the Python standard library. Image conversion in importer tests and optional master regeneration uses macOS `sips`. The host package targets macOS 14 or later. Swift Testing requires a compatible compiler; the package's Swift 5 language mode is not a claim that older Xcode versions pass this suite.

Select Xcode for the current shell without changing the machine's global developer settings. Adjust the application location if necessary:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcodebuild -showsdks
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast -showdestinations
xcrun simctl list devices available
```

Install an available Watch simulator runtime through Xcode if no Watch destination appears. Choose identifiers from the current list; device names and identifiers differ between machines.

## Clean checkout or source ZIP

Run these commands from the project directory. All application sources, selected runtime assets, icons, shared scheme, configuration defaults, and importer test fixtures are included in the repository. Git metadata, personal signing configuration, and the optional complete source-art handoff are not required for simulator builds or required validation.

The native project is tracked and reproducibly generated:

```sh
python3 scripts/generate_project.py --check
python3 scripts/check_project.py
bash scripts/validate.sh
```

If intentionally changing Watch source or atlas membership, regenerate and review the project:

```sh
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
```

Generation never reads an Apple team from the environment or the existing project. Local signing stays in an ignored configuration file, described below.

`validate.sh` checks committed runtime integrity, importer fixtures, Swift core/rendering/session tests, host Release compilation, project metadata, shared policy synchronization, and an unsigned native watchOS Release build. It returns failure when a required check fails. Read its native-tooling result: host tests alone do not establish a passing Watch build. Watch UI automation is a separate step.

Focused checks are:

```sh
python3 scripts/import_art.py --check-runtime
python3 scripts/test_import_art.py
bash scripts/test.sh
python3 scripts/sync_boss_policy.py --check
python3 scripts/check_project.py
```

The runtime check validates the committed resources without the optional full master pack. Importer tests use committed fixtures and isolated temporary output. Full master regeneration is an optional maintenance operation described in [Artwork and runtime assets](ART_ASSETS.md); it is not part of a newcomer's setup.

## Continuous integration

Every push to `main` runs the **Watch validation** workflow. Its **Source and unsigned Watch validation** check always runs a validation route; documentation changes do not leave that check skipped or pending.

Documentation-only changes use [the lightweight suite](../scripts/ci_docs.sh): Markdown links, website and App Store draft metadata, site regressions, privacy synchronization, and public-tree checks. This route covers root Markdown files except `PRIVACY.md`, Markdown under `.github`, and ordinary text/image/site files under `docs`. It does not import artwork, compile Swift, build Watch products, or launch simulator UI tests.

Changes to application code, runtime assets, projects, configuration, build/test scripts, tests, workflows, root `PRIVACY.md`, or the bundled Watch policy retain [the full Watch suite](../scripts/ci_watch.sh). Mixed changes, unknown file types/paths, empty diffs, and unavailable comparison commits also take the full route. Routing compares the entire push range and checks both old and new paths for renames and deletions. Concurrency is scoped to each commit so a later documentation-only push cannot cancel an earlier app-affecting full run.

Examples of main-push routing:

| Changed paths | Validation |
| --- | --- |
| `README.md`, `docs/index.html`, website CSS/images | Lightweight documentation suite |
| `docs/app_store/metadata_en_US.json` | Lightweight, including store-draft checks |
| `docs/privacy/index.html` only | Lightweight, with required policy synchronization |
| `PRIVACY.md` or `WatchApp/Policy/Privacy.txt` | Full Watch suite |
| `Sources`, `WatchApp/Art`, project, generator, tests, or workflow files | Full Watch suite |
| A source file deleted or moved into `docs` | Full Watch suite |
| Missing comparison, unknown path, or manual workflow request | Full Watch suite |

To run the full suite regardless of changed paths, use **Run workflow** on Watch validation in GitHub Actions (`workflow_dispatch`). CI remains unsigned and does not need Apple credentials. The existing main-push and manual triggers remain in place; no pull-request trigger was added.

Focused local checks for this routing are:

```sh
python3 scripts/test_route_ci.py
bash scripts/ci_docs.sh
```

## Unsigned Watch simulator builds

Select a current simulator identifier:

```sh
WATCH_SIM='<available-watch-simulator-identifier>'
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast \
  -configuration Debug -destination "platform=watchOS Simulator,id=$WATCH_SIM" \
  -derivedDataPath .build/WatchSimulator CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast \
  -configuration Release -destination "platform=watchOS Simulator,id=$WATCH_SIM" \
  -derivedDataPath .build/WatchSimulator CODE_SIGNING_ALLOWED=NO clean build
```

These builds need no Apple account. Debug uses `-Onone`; Release uses `-O` and whole-module compilation. The accepted B3 graphics and earned-save/HUD build is version 1.0 (10), with its existing bundle identifier and local data domain. Build 7's pre-B3 prototype remains preserved separately.

Install and launch the Debug product after building it:

```sh
xcrun simctl bootstatus "$WATCH_SIM" -b
xcrun simctl install "$WATCH_SIM" .build/WatchSimulator/Build/Products/Debug-watchsimulator/PickleBlast.app
xcrun simctl launch "$WATCH_SIM" com.pickleblast.watchapp
```

The helper below performs a Debug build, boot, installation, and ordinary launch using `.build/DerivedData`:

```sh
bash scripts/run_simulator.sh "$WATCH_SIM"
```

A simulator bundle cannot be installed on a physical Watch. Serialize builds that share an output directory and run one simulator UI suite at a time.

## Native Watch UI tests

Run the shared scheme's real Watch test bundle on the selected simulator:

```sh
mkdir -p .build/validation
WATCH_RESULT_BUNDLE=".build/validation/watch-ui-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast \
  -configuration Debug -destination "platform=watchOS Simulator,id=$WATCH_SIM" \
  -derivedDataPath .build/WatchSimulator -resultBundlePath "$WATCH_RESULT_BUNDLE" \
  -collect-test-diagnostics never -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
  -maximum-test-execution-time-allowance 420 CODE_SIGNING_ALLOWED=NO test
```

Use a new result path for every attempt, and repeat on a materially smaller available Watch display. The suite covers ordinary navigation, settings, Crown movement, all five individual boss selections, post-win Play Next through the displayed order, end-of-list behavior, rematch, Back/Home, Pause/Resume, interruptions, Arcade, and scene ownership. Legacy series tests exercise internal compatibility only. Inspect actual test results and screenshot attachments; historical counts and test source are not current execution evidence.

Ordinary UI cases use the normal application. Clearly named controlled-input and scripted-run cases use DEBUG-only launch arguments, isolated validation defaults, and public movement controls. Scripted victories establish progression and accounting, not human difficulty or physical performance. Those controllers and diagnostic activation paths are excluded from Release. The host `PickleBlastAppUITests` exercise session logic on macOS and are not Watch UI automation.

Scripted autoplay advances four simulation updates per callback unless `--validation-realtime` is also supplied. Label accelerated captures accordingly. Use the realtime flag when inspecting ordinary animation timing; a realtime public-input oracle still does not represent human play.

Capture ordinary gameplay after normal navigation:

```sh
mkdir -p .build/screenshots
xcrun simctl io "$WATCH_SIM" screenshot .build/screenshots/ordinary-gameplay.png
```

`scripts/capture_simulator.sh` captures direct DEBUG presentation fixtures. Label them as fixtures; they do not prove that ordinary navigation reached a state. Its final launch returns to ordinary Home. Host `RenderEvidence` output is a macOS offscreen diagnostic, never a Watch simulator screenshot. Simulator observations cannot establish Crown feel, haptics, battery use, or physical frame pacing.

## Local physical signing

The public configuration has no team selected. `Configuration/Signing.xcconfig` optionally includes ignored `Configuration/Signing.local.xcconfig` for both app and UI-test Debug and Release settings. If you already have a working local file, keep it. For a new physical development setup:

```sh
cp Configuration/Signing.example.xcconfig Configuration/Signing.local.xcconfig
```

Enter your existing Xcode team identifier in the local file. Keep automatic signing, and manage any account setup directly in Xcode. Do not commit the local file or write personal team settings into the generated project. Regeneration preserves the local file. For an existing installation, retain its team and `com.pickleblast.watchapp` identity so updates keep the same local records and settings.

Follow [Run on a physical Watch](../RUN_ON_MY_WATCH.md) for signing, auditing, installation, and direct checks. That route uses a development signature and is separate from App Store distribution. The game has no iPhone companion. A paired iPhone may still participate in Apple's development-device setup; [Apple's current Device Hub guidance](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac) describes the pairing and Developer Mode prerequisites, verified on 2026-09-28.

## Archive preparation

Create an unsigned archive locally without account access:

```sh
xcodebuild -project PickleBlast.xcodeproj -scheme PickleBlast \
  -configuration Release -destination 'generic/platform=watchOS' \
  -derivedDataPath .build/Archive \
  -archivePath .build/archives/PickleBlast-unsigned.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

The shared Archive action uses Release, and the application is installable in the archive. An unsigned archive establishes packaging only. A development-signed Release or archive does not establish App Store distribution eligibility or approval. Distribution validation, owner decisions, current Apple requirements, and submission blockers are tracked in [App Store readiness](APP_STORE_READINESS.md). Archives, result bundles, logs, and signed products remain under ignored `.build`.

## Troubleshooting and known warning

If only Command Line Tools are selected, point `DEVELOPER_DIR` at full Xcode before native work. `scripts/test.sh` can account for standalone Command Line Tools testing paths, but this does not supply a Watch SDK or simulator. A missing runtime, unavailable device, signing prerequisite, or timed-out UI setup must be reported separately from tests that actually ran.

The Watch scene host emits a known warning for the deprecated public `WKInterfaceSKScene` initializer. Its explicit `presentScene(nil)` teardown is retained because native lifetime probes established that the previous host kept prior scenes alive. The warning is documented rather than suppressed; see [Architecture](ARCHITECTURE.md) for the supported API path and future migration condition.

Xcode skips App Intents metadata extraction because the app has no App Intents dependency.

Do not erase app data, uninstall the working Watch build, change account settings, revoke certificates, or alter pairing merely to obtain a passing result. Keep raw device logs, profiles, signing information, and screenshots of account screens private. Report sanitized commands, versions, pass/fail results, and relevant application-only screenshots.
