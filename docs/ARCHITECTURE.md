# Architecture

## Authority and presentation

`PickleBlastCore` is a dependency-free Swift module. It owns positions, swept collisions, scores, lives, saves, timers, formations, opponents and transitions in court feet and seconds. `GameTuning.swift` centralizes tuning. The 1/120-second fixed step has bounded catch-up and collision iterations; SpriteKit physics never moves gameplay objects.

`PickleBlastRendering` consumes authoritative state and events. `CourtProjection` maps the unchanged 20 × 44 court into shallow perspective. Touch inverts that mapping at the player's receiving depth. Approved alpha bounds and paddle attachments align visible contact without defining collision reach. Programmatic net, kitchens and service lines retain regulation relationships. The decorative background supplies no physics.

`WatchApp` is one watch-only SwiftUI application. `GameSession` adapts local settings, input, lifecycle and semantic UI observations. SwiftUI owns navigation, Pause and results. Crown and drag update the same clamped core position; the Crown binding reads that position, leaving no hidden boundary overshoot.

## Modes

Home exposes Arcade and individual `BossID` matches, with Boss Rally first. The shared displayed roster is Wall → Banger → Poacher → Dinker → Lobber. `GameMode` also retains the legacy three-match `RunPlan` for internal compatibility; no public menu starts it. Arcade retains its accepted Wall policy and random path. Boss Rally uses delayed observation, finite acceleration/braking and strategy-specific shot selection. Only real paddle-region crossings produce contact; no invulnerability or scripted surrender extends a match. Optional contact motion influence is disabled.

A successful individual result can explicitly start the next displayed opponent using Play Next. The session creates a fresh core engine while reusing its scene and input surface; the next match begins with a fresh score, two saves and cleared transient state. Each completed match persists its own opponent record once; Play Next does not carry a series score. The final Lobber result has no next opponent and never wraps. Rematch/Retry keeps the selected opponent.

The retained legacy series advances Wall → Banger → Poacher after wins, accumulates run score and ends on a loss. Its tests preserve compatibility behavior; it is not an advertised play route. Individual matches and Arcade retain separate results and records.

## Special flights

Boss Rally tags prepared and launched shots with rally/shot identifiers. The core owns their selection, cooldown, response bounds and recovery. Rendering follows those decisions. Dinker changes contact speed on the existing trajectory. Lobber stores one committed ground segment, simulation elapsed time, bounded duration and continuous height in `RallyShotState`. Analytic arrival reaches zero elevation before the ordinary paddle hit/miss decision; no shadow or SpriteKit node can cause contact. A successful soft/lob return restores ordinary pace and clears elevated state. Pause freezes the flight clock, and rally/mode transitions clear transient state.

## Scene ownership and lifecycle

One session and stable scene own each run. The Watch surface wraps `WKInterfaceSKScene` in `WKInterfaceObjectRepresentable`, requests 30 FPS, and presents `nil` on permanent dismantling. This public initializer is deprecated; the known warning is retained because the previous SpriteView integration accumulated scenes in native repeated-run measurements. The host-only path still uses SpriteView. A replacement requires native disposal evidence.

Inactive or reduced-luminance ineligible views freeze simulation, animation, effects and haptics. Ordinary runs require Resume; frame time is rebased before advancing. There are no background execution sessions. Only needed character atlases remain cached; opponent transitions release the previous selection. Celebration particles use a bounded pool.

## Assets and development boundaries

`RuntimeArtManifest` and `MotionPlayback` keep original clip timestamps and paddle registration separate from core animation phases. Shuffle follows authoritative travel distance. Committed PNGs/manifests build from a clean checkout; private masters are needed only for optional reimport. See [art assets](ART_ASSETS.md).

DEBUG fixtures, autoplay and probes are compile-time excluded from Release. Scripted tests use public movement inputs and are labeled; they are not human balance models. `RenderEvidence` is a macOS diagnostic, never a Watch screenshot source.

Local UserDefaults store settings and scores. The app uses Apple frameworks only, declares app-owned UserDefaults reason CA92.1, and has no network or analytics dependency. Tracked signing defaults are account-independent with an optional ignored local team override.

See [build and test](BUILD_AND_TEST.md), [security](../SECURITY.md), [privacy](../PRIVACY.md), [tuning](GAMEPLAY_TUNING.md) and [testing](TESTING.md).
