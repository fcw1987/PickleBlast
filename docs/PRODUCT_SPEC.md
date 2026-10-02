# PickleBlast product specification

PickleBlast is a standalone, offline Apple Watch game. SwiftUI owns menus, SpriteKit renders, and one deterministic Swift core owns gameplay.

## Play

- Move with the Digital Crown or drag across the court. Returns are automatic; contact position determines placement.
- Arcade has three authored waves of 36, 48 and 58 one-hit targets, reachable backfield ricochets, consecutive-hit multipliers, and The Wall finale. Three lives persist through the run; each stage starts with two free recoveries. The last four targets clear in a finishing chain after a legitimate destruction.
- Boss Rally offers The Wall, The Banger, The Poacher, The Dinker and The Lobber individually. All Three remains Wall → Banger → Poacher. Each match is first to three, without win-by-two. Two free saves apply to the whole match and award no point. Later player misses award the boss a point; genuine boss misses award the player a point.
- All Three starts the next match after a win with the ordinary ready interval, new 0–0 score and two saves. A loss ends the sequence; Retry starts at The Wall. The final win uses the normal celebration.
- Pause offers Resume, Home and Restart. Interruptions and reduced-luminance ineligibility freeze the run. Resume rebases time and uses a countdown.
- Sensitivity, haptics, Arcade best and per-opponent best score/wins/longest rally persist locally. No account, phone companion, multiplayer or online service exists.

The Dinker occasionally sends a softer low return, then ordinary pace resumes at the player’s automatic contact. The Lobber commits a direct ground path and elevated arc, descending at that same receiving line. Banger drives retain a safe response interval; Poacher’s directional cue follows its committed target.

## Invariants

The court is 20 × 44 logical feet, with net at 22 and kitchen boundaries at 15 and 29. Centerlines do not extend into the kitchens. Rendering-only perspective and inverse touch mapping never change collisions. The accepted Crown gain, saved calibration, clamping and immediate reversal, receiving assistance, automatic returns, approved artwork/timing, background and scoring are preserved. Optional movement-based shot influence remains disabled.

The renderer requests 30 callbacks per second; simulation advances at 120 Hz with bounded catch-up. These targets are not measured physical frame-rate or battery guarantees.

## Compatibility

The deployment target is watchOS 10. Building for that target does not establish testing on every Watch or OS version. See [build instructions](BUILD_AND_TEST.md), [architecture](ARCHITECTURE.md), [privacy](../PRIVACY.md), and the [App Store checklist](APP_STORE_READINESS.md).
