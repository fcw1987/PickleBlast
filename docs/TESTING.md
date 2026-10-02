# Testing

Run `bash scripts/validate.sh` from an authorized checkout with full Xcode selected. It verifies runtime assets, importer fixtures, Swift core/rendering/session tests, host Release compilation, project consistency, documentation links, publication hygiene and an unsigned native watchOS Release build. A missing native toolchain is a failure, not a successful Watch build.

The [build guide](BUILD_AND_TEST.md) documents individual commands, simulator setup, Debug/Release builds, native UI tests and unsigned archive creation. [CI](CI.md) describes hosted coverage and explicit simulator skips.

## Regression coverage

Host tests cover court geometry, swept collisions, Crown boundary reversal, receiving assistance, scoring, two-save match rules, first-to-three outcomes, All Three transitions, lifecycle, corrupt local data recovery, rendering registration and resource lifetime. Importer tests cover canonical fixtures, manifests, PNG bounds, integrity, and filesystem safety.

The native Watch suite covers Home, Settings persistence, Crown movement, all five opponents, Arcade, Pause/Resume/Restart, interruptions, results, rematch, app icon, and repeated scene lifetimes. Run it serially on a larger and smaller available Watch simulator. Tests labeled scripted use controlled input or accelerated simulation; they establish rules and reachability, not human difficulty or enjoyment.

A fresh source copy must pass without optional art masters, local signing, historical source folders or pre-existing build outputs. Compare gameplay source and runtime asset hashes when making packaging-only changes.

Ability tests measure actual flight pace, response time, cooldowns, active recovery, and the Lobber’s single analytic contact across callback cadences and interruptions. Saved-format fixtures preserve the original three record keys while initializing new opponents independently.

For clean real-time simulator recordings, `testRealtimeFiveBossAbilityRecording` navigates the normal selection screen with a delayed, bounded public-input controller. Capture the simulator with `simctl io … recordVideo`; keep recordings local and label them scripted. Compare ordinary and special shots on both display sizes.

## Human and distribution checks

Follow [Physical Watch regression](PHYSICAL_WATCH_TEST.md). Installation and process launch alone do not establish Crown feel, touch comfort, haptics, readability, accessibility, heat or battery life. Do not claim those checks from simulator automation.

The configured watchOS 10 minimum needs representative older-device validation before broad compatibility claims. Current local development uses Xcode 27 and watchOS 27 simulators. Distribution validation and App Store review are separate from unsigned builds; see [App Store readiness](APP_STORE_READINESS.md).
