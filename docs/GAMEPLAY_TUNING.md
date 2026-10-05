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
| Ordinary Rally speed growth | 0.16 ft/s² within the 46 ft/s cap |
| Banger drive | 1.40 × comparable ordinary pace, ≥0.25 s preparation, ≥0.90 s response interval, mobile 0.45 s recovery |
| Banger ordinary return ceiling | 30 ft/s; drives remain within the global 46 ft/s cap and do not compound |
| Dinker soft reset | 0.70 × ordinary pace, ≥16 ft/s, ≤2.15 s incoming flight; 3–5 eligible-return interval |
| Lobber arc | 1.30 × ordinary flight duration, ≤2.10 s, direct ground path and 5 ft logical peak before screen bounds |
| New-boss preparation / recovery | ≥0.22 s / mobile 0.55 s; ordinary pace resumes at player contact |
| Poacher commitment | Two matching completed lanes, target within 3 ft, delayed confirmation or active wrong-read recovery |
| Optional through-contact shaping | Disabled |

Receiving guidance applies at swept y=22 entry and relevant lower-area reflections, preserving speed/position. Upper-court ricochets remain unrestricted by that cap. Outgoing placement uses normalized contact offset and the projection-aware limit. Artwork never changes collisions.

Small/medium/large paddles award 100/225/400 on destruction; baskets 175. Cleanup uses base awards without multiplying or incrementing chains. Wave bonuses are 250; boss points 500 and victory 1,000. The controlled full Arcade replay scores 60,225; this is not a predicted human score.

The Wall rewards placement, Banger stays mobile in recovery, and Poacher commits from observed tendencies. Arcade's Wall policy remains isolated. Play Next starts the next individual boss with fresh points and saves; each match keeps its own score and record. The legacy internal three-match series retains its accumulated-score behavior for compatibility and has no public menu entry. Existing records and sensitivity units remain intact; historical scores are retained even where older rules differed. Human difficulty, comfort and enjoyment remain physical judgments.

Dinker and Lobber each keep ordinary exchanges between signature shots. Their shot clocks advance only with simulation time. Lob ground velocity is committed at launch after receiving constraints; its height reaches zero before automatic contact. These are initial physical-review tuning values, not claims of human difficulty or enjoyment.
