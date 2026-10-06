# PickleBlast

**Pickleball, made for Apple Watch.** Move with the Digital Crown, return automatically, and play quick rallies against five distinct bosses.

[Website](https://fcw1987.github.io/PickleBlast/) · [Privacy](https://fcw1987.github.io/PickleBlast/privacy/) · [Support](https://fcw1987.github.io/PickleBlast/support/)

<a href="docs/images/boss-rally.png"><img src="docs/images/boss-rally.png" alt="A live Boss Rally on Apple Watch, with the ball crossing the black court." width="142"></a>
<a href="docs/images/opponents.png"><img src="docs/images/opponents.png" alt="Build 10 individual Boss Rally selection screen." width="142"></a>
<a href="docs/images/arcade.png"><img src="docs/images/arcade.png" alt="Arcade mode during a target wave on Apple Watch." width="142"></a>

These actual build 10 captures show the accepted interface and B3 court in a watchOS 27 simulator. They are ordinary gameplay and navigation captures, not concept art. See [screenshot provenance](docs/images/README.md).

## Play

Turn the Digital Crown or drag on the court to move. Your player returns the ball automatically; your position shapes the shot. The accepted build 10 uses the selected B3 slate-blue court with illustrated night-arena scenery, a darker kitchen and white painted lines. The HUD and outer fade retain black areas.

**Boss Rally** appears first on Home. Choose The Wall, The Banger, The Poacher, The Dinker, or The Lobber individually. After a win, **Play Next** offers the next opponent in that displayed order. The Lobber ends the list without looping; Rematch, Choose Opponent, and Home remain available. Each match is first to three points and starts with no saves. Every 20 consecutive player returns can earn a save, capped at one. Won points preserve return progress and an unused save. Player misses, including a consumed save or lost point, reset progress; rematch, restart and Play Next start fresh. The Wall rewards placement, The Banger presses the pace, and The Poacher commits to a side from your shot tendencies. The Dinker mixes in soft resets; The Lobber sends elevated shots back to your normal receiving area. Your wins, best score, and longest rally for each boss stay on your Watch.

**Arcade** appears below Boss Rally and offers three target waves followed by a final rally against The Wall. Your best score is stored locally.

## Build and run

For the owner or an otherwise authorized developer: PickleBlast is a standalone watchOS app with a deployment target of watchOS 10.0. The verified local toolchain is full Xcode 27 with Swift 6.4. The project has been built on current Watch simulators; the minimum-version target does not mean every older Watch and watchOS release has been tested.

Open `PickleBlast.xcodeproj`, choose the **PickleBlast** scheme, select an Apple Watch simulator, and run. To check a clean checkout from Terminal:

```sh
python3 scripts/generate_project.py --check
python3 scripts/import_art.py --check-runtime
bash scripts/test.sh
bash scripts/validate.sh
```

The full validation script requires full Xcode for its native Watch build and reports when that toolchain is unavailable. See [Build and test](docs/BUILD_AND_TEST.md) for detailed simulator, UI test, and local signing instructions.

## Project structure

SwiftUI provides the menus, settings, pause, and results. The pure Swift `PickleBlastCore` owns gameplay positions, collisions, scores, timers, and transitions. SpriteKit renders the core's state; it does not simulate gameplay. See [Architecture](docs/ARCHITECTURE.md).

- `Sources/PickleBlastCore` — authoritative game rules and state.
- `Sources/PickleBlastRendering` — court projection, SpriteKit scene, and presentation.
- `WatchApp` — watchOS interface, session, settings, and bundled runtime artwork.
- `Tests` and `WatchUITests` — core, host, and Watch UI test sources.
- `docs` — product, build, architecture, artwork, CI, and release-readiness guides.
- `scripts` — project generation, asset checks, and validation.

## Privacy and status

Game settings and records are stored in the app's local storage. PickleBlast works offline and has no account, gameplay server, analytics, advertising, or user-tracking integration. Apple system services follow Apple's own policies; see [Privacy](PRIVACY.md) for the app's inspected behavior.

Version 1.0 (10) was physically tested and accepted by the owner. It includes the B3 arena with the moon clear of the clock, original Arcade equipment and bounded hit feedback, won-point return progress, and the approved matte chartreuse paddle icon with true-black ink. Earlier builds remain in git history. PickleBlast has not been released through the App Store or TestFlight. [App Store readiness](docs/APP_STORE_READINESS.md) describes the outstanding work.

## Issues, security, and rights

Use GitHub Issues to report bugs or request features. The project does not accept code or artwork contributions or pull requests; see [Contributing](CONTRIBUTING.md). Report security concerns privately as described in [Security](SECURITY.md), never in a public issue.

PickleBlast is **source available, not open source**. The source is provided for viewing, study, discussion, and evaluation. Repository access does not grant permission for personal or commercial use, execution, modification, redistribution, derivative works, republishing, or incorporation into another project without prior written authorization. Authorized distributed copies are governed by their applicable end user license. Artwork, characters, animations, name, and branding are also all rights reserved. See [Source license](LICENSE.md), [Asset license](ASSET_LICENSE.md), [Privacy](PRIVACY.md), and [Artwork and runtime assets](docs/ART_ASSETS.md).

## Guides

[Product specification](docs/PRODUCT_SPEC.md) · [Build and test](docs/BUILD_AND_TEST.md) · [Architecture](docs/ARCHITECTURE.md) · [Artwork and runtime assets](docs/ART_ASSETS.md) · [CI](docs/CI.md) · [App Store readiness](docs/APP_STORE_READINESS.md)
