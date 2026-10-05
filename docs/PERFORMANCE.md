# Performance and resource maintenance

The renderer requests 30 frames per second. The deterministic game core advances at 120 Hz with bounded catch-up and collision work. Neither setting guarantees a measured frame rate or battery life on every Watch.

`TextureLibrary` caches selected character atlases; changing opponents releases the previous selection. Celebration particles use a bounded pool. Inactive and paused runs stop simulation, animation, effects and haptics, and resume rebases time. The Watch scene host explicitly detaches its scene on permanent navigation. Keep that teardown when evaluating a future replacement for the deprecated WatchKit initializer.

Use `scripts/measure_resources.py` for checkout/bundle measurements and the lifecycle tests for repeated Home, rematch and opponent transitions. Record file-byte totals separately from compressed download size and resident memory. A passing lifetime test is not a physical battery or thermal measurement.

For meaningful comparisons, use the same configuration, signing state, toolchain and device. Measure sustained on-wrist play, interruptions and repeated matches before making performance claims. See [Testing](TESTING.md) and the [physical checklist](PHYSICAL_WATCH_TEST.md).

## Build 6 implementation

The court uses reusable native SpriteKit shapes whose paths change with layout. Point feedback changes only the markings’ opacity, leaving the black surface opaque. Foot markers and HUD framing are bounded scene nodes. This pass changes no character texture resolution, adds no artwork files and introduces no external runtime package. Additional shapes still require measurement; static reuse is not evidence of zero GPU or memory cost.

A concrete dependency check considered [Airbnb Lottie](https://github.com/airbnb/lottie-ios). Its [package manifest](https://github.com/airbnb/lottie-ios/blob/master/Package.swift) lists iOS, macOS, tvOS and visionOS, with no watchOS platform, and the project uses [Apache 2.0](https://github.com/airbnb/lottie-ios/blob/master/LICENSE). It provides vector animation playback rather than a useful replacement for the existing court, contact animation and SpriteKit atlas renderer. No dependency was added.

## Measured host comparison — October 5, 2026

Baseline: build 5, `b470aae62a2755e063752bc2ff8598845ba879b3`. Candidate renderer: build 6, `77d00620013d85dc4a5dbecd39ca4f93dc8584d9`. Isolated source exports used the same Release probe; candidate renderer hashes matched that commit. All 1,678 files under `WatchApp/Art` were byte-identical. The 1,675 runtime PNGs total 13,024,552 bytes in both versions. Their all-image RGBA sum, 110,801,088 bytes, is an uncompressed inventory estimate, not resident RAM or GPU allocation.

The host was an Apple M3 Max with 64 GiB RAM, Darwin 27.0 and Xcode 27.0 (27A266a). Thirteen deterministic fixtures covered all bosses, special-shot phases, Arcade, dense feedback, pause, blackout and celebration at 162 × 197 and 211 × 257 point viewports. Each fixture warmed 120 updates, then measured 1,800 unpaced `render` calls. Five fresh processes per version alternated order; values below are medians of per-run statistics. Native compilation had finished, but simulator UI testing overlapped part of the probe and may contribute contention.

| Host CPU / scene metric | Baseline | Build 6 renderer |
| --- | ---: | ---: |
| First scene construction + viewport | 18.625 ms | 19.089 ms |
| First render | 1.291 ms | 1.741 ms |
| Small dense fixture, mean / p95 update | 0.09649 / 0.09925 ms | 0.09642 / 0.09983 ms |
| Large dense fixture, mean / p95 update | 0.08965 / 0.09492 ms | 0.09234 / 0.09717 ms |
| Ordinary rally / dense scene nodes | 168 / 284 | 178 / 294 |
| Process-end resident memory, median | 66.44 MiB | 74.14 MiB |
| Process-end resident memory, range | 64.64–77.41 MiB | 64.20–80.13 MiB |

Across all 26 fixture/size combinations, mean CPU deltas ranged from −0.00198 to +0.00511 ms. The memory ranges overlap substantially; this sample does not establish a resident-memory regression or Watch memory use. The first scene is process-cold, not filesystem-cache cold. These timings cover scene-node updates with source PNG fallback, excluding core simulation, SwiftUI, displayed frame pacing and GPU work. Synthetic clocks advance by 1/30 second per call; the probe does not schedule at 30 Hz or measure Watch app launch latency.

A separate offscreen probe used three alternating processes per version, three warmup snapshots and 60 samples per fixture. It includes SpriteKit rendering and synchronous image readback, not GPU-only time:

| Host offscreen render + readback | Baseline mean / p95 | Build 6 mean / p95 |
| --- | ---: | ---: |
| Small dense fixture | 17.857 / 20.484 ms | 18.412 / 23.103 ms |
| Large dense fixture | 20.346 / 24.782 ms | 20.348 / 24.053 ms |

Readback dominates this probe and results vary by fixture; it does not demonstrate a rendering improvement or a consistent increase in rendering cost. Snapshot-inclusive host resident memory had medians of 107.03 and 110.78 MiB, with overlapping ranges of 106.70–108.89 and 103.52–112.27 MiB respectively. Keep this separate from the CPU-only process values.

Raw source inventories, run logs, hashes and before/after images remain in private local engineering evidence. This summary does not establish physical Watch GPU timing, frame pacing, launch latency, memory, warmth or battery use. Those require measurements and sustained play on the installed candidate; user acceptance remains pending. Larger textures can increase decoding and upload cost even when compressed storage is small, so future asset changes need equivalent comparisons.

## Compiled development bundle

The preserved signed build 5 bundle contains 17,706,070 file bytes across 33 files. Signed build 6 contains 17,839,450 bytes across 33 files: an increase of 133,380 bytes (about 130 KiB). Both are development-signed watchOS Release products from the same Xcode installation; provisioning/signature bytes are included. Every compiled atlas page has the same dimensions and the summed RGBA estimate remains 32,950,964 bytes across all atlases. This is an inventory estimate, not concurrent residency: only the player and selected opponent character atlases are retained. It excludes driver allocations, mipmaps, heap, framework and shape-raster memory.

## Build 6 real-time simulator comparison

Three alternating fresh Debug processes per version used the same Ultra 4 49mm watchOS 27 simulator, Lobber seed 23 and real-time public-input evaluation policy, with no concurrent UI tests. Baseline build 5 and build 6 both measured median 30.03 callbacks/s and 33.33 ms sampled p95 callback intervals. Across the three processes, callbacks over 50 ms numbered one and zero respectively; that small sample does not establish an improvement.

Median per-process resident-memory samples were 196.89 → 197.25 MiB, a 0.36 MiB difference. Scene initialization medians were 77.61 → 76.28 ms. These are simulator-host Debug measurements, not physical Watch RAM, GPU time, battery, heat or perceived launch latency. Instruments could not establish a physical Watch recording connection. The owner subsequently played build 6 and accepted the menus, while requesting stronger graphics.

## Separate build 7 prototype

Build 7 experiments with earned saves and a bounded milestone HUD. The three generated visual directions are review concepts, separate from that executable; their detailed art is not included in its runtime atlases. Turning a selected direction into a playable build requires production assets and measurements of the resulting bundle, decoded atlas footprint, loading and on-device behavior. Existing registered character frames can be preserved while upgrading the environment. Neither the build 6 measurements nor conceptual asset budgets establish that future graphics are affordable.

The final milestone renderer was compared with exact build 6 source `552397e` using three alternating fresh Release host processes per version. The Apple M3 Max/Xcode 27.0 probe ran while native builds and simulator UI testing were paused. Twelve held Lobber fixtures covered ordinary, active and Reduced Motion presentation at 20/40 player returns and both measured Watch layouts. Each fixture measured 1,140 update calls after warmup; milestone-trigger updates were timed separately. Both versions used the same legacy combined-contact counts. These synthetic states measure presentation cost, not natural rally reachability.

| Host metric, median of per-run values | Build 6 | Final build 7 milestone prototype |
| --- | ---: | ---: |
| Aggregate scene-update CPU mean | 0.007808 ms | 0.008051 ms |
| Milestone-trigger CPU mean range | 0.00781–0.00841 ms | 0.06558–0.07462 ms |
| Scene descendants / labels | 178 / 6 | 186 / 7 |
| End-process RSS median | 46.56 MiB | 47.58 MiB |
| End-process RSS range | 46.52–47.73 MiB | 47.00–55.45 MiB |

Per-fixture mean CPU deltas ranged from +0.000093 to +0.000399 ms. The largest median trigger p95 was 0.09288 ms; that additional text/layout cost is separate from steady animation work. Node identities remained stable, and all intended active-animation samples were visible. All 1,678 runtime-art files remained byte-identical. Source and preview hashes are recorded with the [actual-renderer milestone captures](engineering/build-7-milestones/README.md).

The probe measures unpaced macOS node updates, excluding core simulation, displayed rendering and GPU work. A synthetic 1/30-second input clock is not measured 30 Hz frame pacing. RSS ranges overlap; three short processes cannot establish a memory regression or Watch RAM use. Physical Watch GPU cost, frame intervals, memory, energy, heat and usability remain unmeasured for build 7. No concept art was loaded by this probe, and these results do not establish that the proposed richer graphics are affordable.

The preserved development-signed build 7 Release bundle contains 17,897,210 file bytes across 33 files, 57,760 bytes more than the preserved signed build 6 bundle. Its compiled atlas RGBA inventory remains 32,950,964 bytes, with unchanged page dimensions. The new court concept PNGs are review documents and are absent from the app bundle. These inventories do not measure concurrently resident textures or physical Watch memory.
