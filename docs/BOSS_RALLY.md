# Boss Rally

Boss Rally is the first Home option, followed by Arcade. Choose **The Wall → The Banger → The Poacher → The Dinker → The Lobber** from the individual opponent list. Back returns Home.

Each match is first to three rally points, without win-by-two. Build 10 was physically accepted by the owner. The HUD keeps **YOU / BOSS**, a quiet progress indicator, and one save slot. A genuine boss miss earns a player point. Matches begin with no save. Every 20 consecutive successful **player returns** can fill an empty save slot; it never holds more than one. A held save absorbs the next player miss and scores neither side; without one, the miss earns the boss a point. Won points preserve return progress and an unused save. Player misses, including a saved miss or lost point, reset return progress. Retry, rematch, restart and the next boss clear progress and saves. Milestones at 20, 40 and later multiples celebrate without banking extra saves. Pause preserves both progress and a held save. Boss Rally has no additional lives or health-bar loss condition.

## Results and continued play

A point gets a brief confirmation and ready transition. Every individual match win retains its celebration and results. After winning, **Play Next** offers the next opponent in the displayed order. Selecting it starts a fresh individual match at 0–0 with no banked save; it does not carry the prior score or saves. Each completed match updates its own opponent record once.

The Lobber is the final opponent. Its winning result identifies the end of the list and has no Play Next action or automatic wrap to Wall. A loss does not offer advancement. Rematch/Retry keeps the current opponent; Choose Opponent returns to the list, and Home exits. You can start at any boss without first defeating earlier opponents.

Pause has a 44 × 44 point target in the safe header. Rendering cannot intercept touches; Crown and drag input live below the header and stop while paused. The menu offers Resume, Home, then Restart. These controls remain available after Play Next, and Restart resets the current match.

## Opponents

All five observe delayed visible ball/player samples and move with finite acceleration and braking. Ordinary shot prediction accounts for side-wall reflections. Movement and observation continue during swings and recovery. Only the authoritative ball reaching the existing paddle region can produce contact; there is no invulnerability or scheduled miss.

- **The Wall:** patient control and placement. Moving it to one side, then changing direction can expose an unreachable return. Its stronger continuous policy applies only to Boss Rally.
- **The Banger:** a suitable balanced return can become a visibly prepared drive within the existing speed limit and response-time bound. It keeps observing and retains most mobility through a brief recovery. A desperate lunge or insufficient preparation produces an ordinary return.
- **The Poacher:** completed player shots inform an early, limited lateral commitment. New visible information permits correction after its reaction delay. A correct read helps positioning; changing the pattern can create space behind its momentum. Its cue follows the actual commitment.
- **The Dinker:** occasionally trades ordinary pace for a soft, grounded reset. Its preparation, duration cap and recovery keep the change readable. Ordinary pace resumes at the player’s automatic contact.
- **The Lobber:** commits a ground path and continuous elevated arc that descends into the normal receiving area. The landing cue and ground marker are visual only. The single authoritative arrival determines the normal paddle hit or miss.

Shot selection evaluates the receiving position after the unchanged incoming assistance. It mixes control, placement, pace variation and situational attack using delayed player position, motion and balance. One bounded speed budget prevents stacked boosts. Repeated pace changes cannot slow the ball indefinitely. Compact shot cues distinguish intent while retaining one gameplay ball.

The optional four-degree through-contact placement experiment is internally switchable and **disabled by default**. Crown position gain, saved sensitivity, clamping, reversal, automatic returns and touch parity remain accepted behavior. No curved spin is implemented.

See [current tuning](GAMEPLAY_TUNING.md) and [testing](TESTING.md) for values and validation limits. Automated policies establish behavior and reachability, not human enjoyment.

## Preservation and resources

Arcade retains the accepted `easier-returns-1` values and its original Wall movement/randomness path, three waves, scoring, two saves per stage and 60,225-point deterministic replay. Boss Rally policy, points and optional shaping are explicitly mode-gated.

Character attachment mappings and original animation timing preserve ball contact. Presentation changes retain the true-black court, regulation line geometry and readable shots; see [presentation](PRESENTATION.md). Runtime character caching keeps the player and selected opponent; menu thumbnails release their motion atlases after decoding. The WatchKit scene host explicitly detaches its scene on permanent navigation, while ordinary interruptions remain resumable. Resource scope and validation limits are recorded in [performance](PERFORMANCE.md).

Local records retain wins, best score and longest uninterrupted rally for each of the five opponents. A save ends the interrupted rally. Records have no account, online service or analytics dependency. Rematching resets opponent history and temporary state; points preserve completed shot tendencies within the same match. The internal legacy three-match series is retained for compatibility testing only, as described in [Architecture](ARCHITECTURE.md).
