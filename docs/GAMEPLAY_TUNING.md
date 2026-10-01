# Accepted gameplay tuning

`Sources/PickleBlastCore/GameTuning.swift` is authoritative; this document describes the implementation rather than proposing a rebalance.

| Setting | Current value |
| --- | --- |
| Simulation / render request | 120 Hz / 30 FPS |
| Player full return width / ball radius | 6.50 ft / 0.30 ft |
| Initial / maximum ball speed | 26 / 46 ft/s |
| Receiving / outgoing apparent angle envelope | 35° / 45°, fixed 2.434 projection slope factor |
| Crown gain | 0.150 × saved multiplier; effective 0.075–0.300 ft per binding unit |
| Player bounds | 1.1–18.9 ft, immediate reversal after clamping |
| Arcade | 36 / 48 / 58 one-hit targets, three lives, two free recoveries per stage |
| Final targets | Legitimate destruction leaving at most four starts base-score cleanup every 0.10 s |
| Combo | Successive damage uses ×1, ×2, ×3, ×3, ×5; returns, misses and stages reset it |
| Boss Rally | First to three, no win-by-two, two saves per match scoring neither side |
| Match / save ready | 1.0 / 0.75 s |
| Wall speed / acceleration / braking / observation delay | 7.2 ft/s / 24 ft/s² / 30 ft/s² / 0.20 s |
| Banger | 8.8 / 29 / 35 / 0.20 |
| Poacher | 9.4 / 31 / 36 / 0.17 |
| Rally speed growth | 0.16 ft/s² within the 46 ft/s cap |
| Banger drive | 1.16 multiplier within cap, ≥0.25 s preparation, mobile 0.45 s recovery |
| Poacher commitment | Two matching completed lanes, ≤3 ft displacement, delayed correction |
| Optional through-contact shaping | Disabled |

Receiving guidance applies at swept y=22 entry and relevant lower-area reflections, preserving speed/position. Upper-court ricochets remain unrestricted by that cap. Outgoing placement uses normalized contact offset and the projection-aware limit. Artwork never changes collisions.

Small/medium/large paddles award 100/225/400 on destruction; baskets 175. Cleanup uses base awards without multiplying or incrementing chains. Wave bonuses are 250; boss points 500 and victory 1,000. The controlled full Arcade replay scores 60,225; this is not a predicted human score.

The Wall rewards placement, Banger stays mobile in recovery, and Poacher commits from observed tendencies. Arcade's Wall policy remains isolated. All Three resets points/saves per new opponent and keeps accumulated run score. Existing records and sensitivity units remain intact; historical scores are retained even where older rules differed. Human difficulty, comfort and enjoyment remain physical judgments.
