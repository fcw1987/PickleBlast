# Performance and resource maintenance

The renderer requests 30 frames per second. The deterministic game core advances at 120 Hz with bounded catch-up and collision work. Neither setting guarantees a measured frame rate or battery life on every Watch.

`TextureLibrary` caches selected character atlases; changing opponents releases the previous selection. Celebration particles use a bounded pool. Inactive and paused runs stop simulation, animation, effects and haptics, and resume rebases time. The Watch scene host explicitly detaches its scene on permanent navigation. Keep that teardown when evaluating a future replacement for the deprecated WatchKit initializer.

Use `scripts/measure_resources.py` for checkout/bundle measurements and the lifecycle tests for repeated Home, rematch and opponent transitions. Record file-byte totals separately from compressed download size and resident memory. A passing lifetime test is not a physical battery or thermal measurement.

For meaningful comparisons, use the same configuration, signing state, toolchain and device. Measure sustained on-wrist play, interruptions and repeated matches before making performance claims. See [Testing](TESTING.md) and the [physical checklist](PHYSICAL_WATCH_TEST.md).
