# PickleBlast

**Neon pickleball, made for Apple Watch.** Move with the Digital Crown, return automatically, and play quick rallies against three distinct bosses.

<a href="docs/images/boss-rally.png"><img src="docs/images/boss-rally.png" alt="A live Boss Rally on Apple Watch, with the ball crossing the neon court." width="142"></a>
<a href="docs/images/opponents.png"><img src="docs/images/opponents.png" alt="The Boss Rally selection screen with the All Three option and The Wall." width="142"></a>
<a href="docs/images/arcade.png"><img src="docs/images/arcade.png" alt="Arcade mode during a neon target wave on Apple Watch." width="142"></a>

These are captures of the actual app in the watchOS 27.0 simulator. They show the current interface, not a physical-device or App Store listing.

## Play

Turn the Digital Crown or drag on the court to move. Your player returns the ball automatically; your position shapes the shot. The court glows against a true-black background, with a neon OLED-focused look.

**Boss Rally** is the main mode. Play The Wall, The Banger, and The Poacher one at a time, or challenge all three in sequence. Each match is first to three points, with two saves. The Wall rewards placement, The Banger presses the pace, and The Poacher adapts to your shot tendencies. Your wins, best score, and longest rally for each boss stay on your Watch.

**Arcade** offers three target waves followed by a final rally against The Wall. Your best score is stored locally.

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

The current development build is 1.0 (4). PickleBlast has not been released through the App Store or TestFlight. [App Store readiness](docs/APP_STORE_READINESS.md) describes the outstanding work.

## Issues, security, and rights

Use GitHub Issues to report bugs or request features. The project does not accept code or artwork contributions or pull requests; see [Contributing](CONTRIBUTING.md). Report security concerns privately as described in [Security](SECURITY.md), never in a public issue.

PickleBlast is **source available, not open source**. The source is provided for viewing, study, discussion, and evaluation. No permission is granted for personal or commercial use, execution, modification, redistribution, derivative works, republishing, or incorporation into another project without prior written authorization. Artwork, characters, animations, name, and branding are also all rights reserved. See [Source license](LICENSE.md), [Asset license](ASSET_LICENSE.md), [Privacy](PRIVACY.md), and [Artwork and runtime assets](docs/ART_ASSETS.md).

## Guides

[Product specification](docs/PRODUCT_SPEC.md) · [Build and test](docs/BUILD_AND_TEST.md) · [Architecture](docs/ARCHITECTURE.md) · [Artwork and runtime assets](docs/ART_ASSETS.md) · [CI](docs/CI.md) · [App Store readiness](docs/APP_STORE_READINESS.md)
