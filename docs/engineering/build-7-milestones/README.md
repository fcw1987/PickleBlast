# Build 7 earned-save and milestone prototype

These images use the **actual shared SpriteKit renderer**, with the final boss-clearance adjustment. They are native macOS offscreen fixtures at the measured Watch layouts, not live Watch screenshots. Player, Lobber and ball state are held to make the HUD readable. The native clock and SwiftUI Pause control are outside this renderer-only capture.

Boss Rally starts with no save. Twenty consecutive **player** returns within one rally earn one save; only one can be held. Points and misses reset the streak, and an unused save survives a won point. Retry and the next boss start empty. Existing two-sided rally records and Arcade rules remain unchanged.

## Animated feedback

The normal HUD has a progress ring and one save shield. A 1.3-second milestone replaces the scores temporarily, above the court. Reduced Motion conveys the same information without the bounce or spark accents. GIF playback is not a frame-timing measurement.

| Actual renderer · normal motion | Actual renderer · Reduced Motion |
| --- | --- |
| ![Small Watch-layout milestone animation](small-milestone-animated.gif) | ![Small Watch-layout static Reduced Motion feedback](small-milestone-reduced-motion.gif) |
| ![Large Watch-layout milestone animation](large-milestone-animated.gif) | ![Large Watch-layout Reduced Motion feedback](large-milestone-reduced-motion.gif) |

## Quiet progress and milestones

| Small · 19 player returns | Small · 20 player returns | Small · 40 player returns |
| --- | --- | --- |
| ![Quiet ring at nineteen returns](small-returns-19.png) | ![Twenty returns earns one save](small-returns-20.png) | ![Forty returns celebrates without stacking a save](small-returns-40.png) |

All five bosses’ approved animation frames were checked for clearance at legal court extremes and paddle reach, including the milestone’s largest overshoot. The final font size and raised anchor remove the overlap caught by that check. Ball position, character artwork, contact geometry and animation timing are unchanged.

[Source and image hashes](manifest.json) · [Measured host costs and limits](../../PERFORMANCE.md) · [Separate visual concepts](../visual-directions/README.md)

The detailed art concepts have not been integrated. No build 7 installation or acceptance is implied by these captures.
