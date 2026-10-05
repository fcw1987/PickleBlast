# Watch presentation

The rendering-only projection preserves logical regulation geometry. The near baseline is 1.5625 times the far baseline width. Safe-area insets place the HUD beneath the clock, the far baseline below the HUD and the near baseline near the lower usable edge. Background aspect fill is decorative; court lines and sprites are independently projected. The court surface is opaque true black, including during point-feedback pulses.

The build 6 night-arena treatment separates bright perimeter lines from quieter interior markings. Fine net mesh, tape and short outer posts add depth at the existing net plane; restrained rails sit outside the sidelines. Court paths update on layout changes. A darker arena backdrop, compact black HUD backing and subtle foot markers frame the play without adding a full-screen effect or another gameplay object.

The separate build 7 prototype replaces visible Boss Rally counters with a small player-return progress ring and one save shield. A 1.3-second milestone temporarily replaces the match-score row; Reduced Motion uses static text without overshoot or spark accents. It never changes the ball or character transforms. Every approved boss frame was checked at legal court extremes and full paddle reach against the largest text overshoot at both Watch layouts. See the [actual renderer previews](engineering/build-7-milestones/README.md) and [host performance limits](PERFORMANCE.md). The detailed [art concepts](engineering/visual-directions/README.md) remain separate from runtime assets while the owner reviews the court treatment.

Approved complete-frame characters are upright square billboards sized from fixed alpha unions. Current player alpha-union height is about 47.04 points at a 211-point viewport, scaling for narrower displays. Whole-frame translation aligns the embedded paddle with authoritative ball contact without redesigning animation or enlarging collision reach. The ball renders above the player on centered blocks. Target paddle heads sit at their projected colliders; handles do not define hits.

The opponent menu uses numbered cards, larger character portraits and short style cues. Boss Rally leads Home, Arcade follows it, and winning results place Play Next beside the existing navigation choices. The final Lobber result says “Final opponent defeated” and keeps Rematch, Choose Opponent and Home.

Pause has a 44 × 44 point target in the safe header. The native render host cannot intercept touches. Crown/drag input excludes that header and stops while paused. Resume and Home are readily available; Restart follows below.

Original character timestamps, alpha and grip continuity are preserved. Effects retain logical origins and reproject on layout changes without advancing paused lifetime. Celebration uses bounded existing particles followed by blackout.

The current [README screenshots](../README.md) are historical build 4 Watch simulator captures; they do not represent the build 6 interface. Capture and inspect new before/after evidence for the accepted polish candidate, keeping source commit, build, configuration, display size and capture method with each image. [Testing](TESTING.md) distinguishes simulator automation from physical play. Simulator images do not certify Crown feel, haptics, battery or on-wrist readability.
