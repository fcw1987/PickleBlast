# Performance and resource maintenance

The renderer requests 30 frames per second. The deterministic game core advances at 120 Hz with bounded catch-up and collision work. Neither setting guarantees a measured frame rate or battery life on every Watch.

`TextureLibrary` caches selected character atlases; changing opponents releases the previous selection. Celebration particles use a bounded pool. Inactive and paused runs stop simulation, animation, effects and haptics, and resume rebases time. The Watch scene host explicitly detaches its scene on permanent navigation. Keep that teardown when evaluating a future replacement for the deprecated WatchKit initializer.

Use `scripts/measure_resources.py` for checkout/bundle measurements and the lifecycle tests for repeated Home, rematch and opponent transitions. Record file-byte totals separately from compressed download size and resident memory. A passing lifetime test is not a physical battery or thermal measurement.

For meaningful comparisons, use the same configuration, signing state, toolchain and device. Measure sustained on-wrist play, interruptions and repeated matches before making performance claims. See [Testing](TESTING.md) and the [physical checklist](PHYSICAL_WATCH_TEST.md).

## Build 6 implementation

The court uses reusable native SpriteKit shapes whose paths change with layout. Point feedback changes only the markings’ opacity, leaving the black surface opaque. Foot markers and HUD framing are bounded scene nodes. This pass changes no character texture resolution, adds no artwork files and introduces no external runtime package. Additional shapes still require measurement; static reuse is not evidence of zero GPU or memory cost.

## Build 6 comparison requirements

Build 5 at `b470aae62a2755e063752bc2ff8598845ba879b3` is the accepted five-boss baseline. The version 1.0 (6) polish candidate requires its own measurements; none are inferred from the renderer’s target FPS or earlier test passes. Keep raw measurements and device logs in ignored local evidence. Record baseline and candidate commit, configuration, viewport, runtime, warm-up and sample duration together.

Compare callback intervals and long frames, update/render CPU time where available, resident memory, first scene load, repeated Home/rematch/Play Next cycles, and bundle/resource bytes. Simulator CPU timing excludes physical Watch GPU, thermal and battery behavior. A larger texture may increase decoded memory or upload cost even when its PNG is small; file size alone is not a memory budget.

Prefer the existing SpriteKit/SwiftUI stack and bounded static decoration. Any dependency or asset expansion needs a concrete benefit, watchOS compatibility, license review and measured cost. No package addition is needed merely to give the court more visual depth. Preserve the true-black court, contact registration and animation timing. Physical frame pacing, warmth, battery use and sustained-play acceptance remain pending until tested on the installed candidate.
