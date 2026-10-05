# PickleBlast product specification

PickleBlast is a standalone, offline Apple Watch game. SwiftUI owns menus, SpriteKit renders, and one deterministic Swift core owns gameplay.

## Play

- Move with the Digital Crown or drag across the court. Returns are automatic; contact position determines placement.
- Home lists Boss Rally first and Arcade below it. The opponent menu offers five individual choices.
- Arcade has three authored waves of 36, 48 and 58 one-hit targets, reachable backfield ricochets, consecutive-hit multipliers, and The Wall finale. Three lives persist through the run; each stage starts with two free recoveries. The last four targets clear in a finishing chain after a legitimate destruction.
- Boss Rally offers The Wall, The Banger, The Poacher, The Dinker and The Lobber individually, in that order. Each match is first to three, without win-by-two. Matches start with no save. At every 20 consecutive player returns across won points until a player miss, an empty save slot earns one save; the bank caps at one. A held save absorbs one player miss without awarding a point. Other player misses award the boss a point; genuine boss misses award the player a point.
- Each win finishes with the normal celebration and results. Play Next explicitly starts a fresh individual match against the next displayed boss, with a new 0–0 score and no banked save. A loss cannot advance. The Lobber is last; the results explain that the list is complete and do not loop to Wall. Rematch/Retry retains the current boss; Choose Opponent and Home remain available.
- Pause offers Resume, Home and Restart. Interruptions and reduced-luminance ineligibility freeze the run. Resume rebases time and uses a countdown.
- Sensitivity, haptics, Arcade best and per-opponent best score/wins/longest rally persist locally. No account, phone companion, multiplayer or online service exists.

The Dinker occasionally sends a softer low return, then ordinary pace resumes at the player’s automatic contact. The Lobber commits a direct ground path and elevated arc, descending at that same receiving line. Banger drives retain a safe response interval; Poacher’s directional cue follows its committed target.

## Invariants

The court is 20 × 44 logical feet, with net at 22 and kitchen boundaries at 15 and 29. Centerlines do not extend into the kitchens. Rendering-only perspective and inverse touch mapping never change collisions. The accepted Crown gain, saved calibration, clamping and immediate reversal, receiving assistance, automatic returns, character contact registration, animation timing and scoring are preserved. The owner accepted B3's slate-blue playing surface in build 10, explicitly replacing the earlier true-black court requirement; black HUD and outer areas remain. Ball, shadow, receiving and special-shot cues stay independently rendered and readable. Optional movement-based shot influence remains disabled.

The renderer requests 30 callbacks per second; simulation advances at 120 Hz with bounded catch-up. These targets are not measured physical frame-rate or battery guarantees.

## Compatibility

The deployment target is watchOS 10. Building for that target does not establish testing on every Watch or OS version. See [build instructions](BUILD_AND_TEST.md), [architecture](ARCHITECTURE.md), [privacy](../PRIVACY.md), and the [App Store checklist](APP_STORE_READINESS.md).
