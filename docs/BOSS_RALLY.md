# Boss Rally

Choose The Wall, The Banger or The Poacher individually, or choose **All Three** from the Boss Rally menu. Each match is first to three rally points, without win-by-two. The HUD shows **YOU / BOSS**, a compact uninterrupted return count, and remaining saves. A genuine boss miss earns a player point. The first two player misses use the existing free saves and score neither side; later misses earn the boss a point. Saves do not replenish between points. Boss Rally has no additional lives or health-bar loss condition.

All Three plays **The Wall → The Banger → The Poacher**. Each win immediately starts the next opponent with the ordinary one-second ready interval; the first two victories have no celebration or results menu. Each new match starts 0–0 with two saves; saves never refill between points within that match. Losing any match ends the sequence. The final Poacher win retains the normal celebration. Restart/Retry begins the sequence at The Wall. Each completed match updates that opponent’s existing local record once, using that match’s score and longest rally; the run score sums the matches. Individual selections remain available.

Pause has a 44 × 44 point target in the safe header. Rendering cannot intercept touches; Crown and drag input live below the header and stop while paused. The menu offers Resume, Home, then Restart.

A point gets a brief confirmation and ready transition. The match win retains the approved celebration. Results offer Rematch or Retry, Choose Opponent, and Home, with the final point score and separate local best/wins/longest-rally records. Existing data keys and Arcade best remain intact.

## Opponents

All three observe delayed visible ball/player samples, estimate side-wall reflections, and move with finite acceleration and braking. Movement and observation continue during swings and recovery. Only the real ball crossing the existing paddle region can produce contact; there is no invulnerability or scheduled miss.

- **The Wall:** patient control and placement. Moving it to one side, then changing direction can expose a physically unreachable return. Its stronger continuous policy applies only to Boss Rally.
- **The Banger:** a suitable balanced return can become a visibly prepared drive within the existing speed limit. It retains most of its mobility through a brief recovery, keeps observing, and can still cover the follow-up. A desperate lunge or insufficient preparation time produces an ordinary return.
- **The Poacher:** completed player shots inform an early, limited lateral commitment. New visible information permits correction after its reaction delay. A correct read helps its positioning; changing the pattern can create space behind its momentum. A cue corresponds to real intended movement.

Shot selection evaluates the receiving position after the unchanged incoming assistance. It mixes control, placement, modest pace variation and situational attack, using delayed player position and motion plus balance. One bounded speed budget prevents stacked boosts. Repeated pace changes cannot slow the ball indefinitely. A reused contact accent distinguishes shot intent without adding nodes or altering the approved ball core.

The optional four-degree through-contact placement experiment is internally switchable and **disabled by default**. Crown position gain, saved sensitivity, clamping, reversal, automatic returns and touch parity remain accepted behavior. No curved spin is implemented.

See [current tuning](GAMEPLAY_TUNING.md) and [testing](TESTING.md) for values and validation limits. Automated policies establish behavior and reachability, not human enjoyment.

## Preservation and resources

Arcade retains the accepted `easier-returns-1` values and its original Wall movement/randomness path, three waves, scoring, two saves per stage and 60,225-point deterministic replay. Boss Rally policy, points and optional shaping are explicitly mode-gated.

Approved Player v4.1 and boss v4.2 frames, attachment mappings, animation timing, background and court projection are unchanged. Only the selected opponent atlas is loaded. The WatchKit scene host still explicitly detaches its scene on permanent navigation; ordinary interruptions remain resumable. Resource scope and validation limits are recorded in [performance](PERFORMANCE.md).

Local records retain wins, best score and longest uninterrupted rally for each opponent. A save ends the interrupted rally. Records have no account, online service or analytics dependency. Rematching resets opponent history and temporary state; points preserve completed shot tendencies within the same match. Only these three opponents are implemented.
