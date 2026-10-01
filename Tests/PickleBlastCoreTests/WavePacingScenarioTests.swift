import Foundation
import Testing
@testable import PickleBlastCore

// Identical sampled, bounded public-input controller for before/after comparison.
// It never selects a target or changes ball, score, life count or in-flight state.
private struct PacingScenario { let name: String; let speed: Double; let interval: Int; let error: Double }
@Suite("Measured sampled-input wave pacing")
struct WavePacingScenarioTests {
    @Test("Sampled and imperfect public controls complete dense one-hit waves")
    func comparePacing() {
        let scenarios = [PacingScenario(name: "sampled", speed: 32, interval: 12, error: 0),
                         PacingScenario(name: "imperfect", speed: 24, interval: 18, error: 0.55),
                         PacingScenario(name: "delayed", speed: 16, interval: 24, error: 0.90)]
        var rows: [[String: Any]] = []
        for scenario in scenarios {
            for seed: UInt64 in [7, 19, 91] {
                for wave in 1...3 {
                    let engine = GameEngine(seed: seed)
                    // Isolate an authored stage only at start; all subsequent control is public input.
                    engine.state.stage = .wave(wave)
                    engine.state.targets = AuthoredWaves.targets(for: wave)
                    var requested = 10.0
                    var returns = 0, hits = 0, misses = 0
                    var active = 0.0
                    var clear = false
                    var frames = 0
                    let fractions = [0.76, -0.68, 0.32, -0.82, 0.58, -0.25, 0.92, -0.52]
                    while frames < 36_000 && engine.state.phase != .results && !clear {
                        if engine.state.phase == .playing { active += 1.0 / 120 }
                        if let ball = engine.state.ball, ball.velocity.y < 0, ball.position.y < 22 {
                            if frames.isMultiple(of: scenario.interval) {
                                let time = max(0, (engine.tuning.playerY + ball.radius - ball.position.y) / ball.velocity.y)
                                let span = 20 - 2 * ball.radius
                                var folded = (ball.position.x + ball.velocity.x * time - ball.radius).truncatingRemainder(dividingBy: 2 * span)
                                if folded < 0 { folded += 2 * span }
                                let landing = ball.radius + (folded <= span ? folded : 2 * span - folded)
                                let error = scenario.error * sin(Double(returns * 17 + Int(seed) * 3))
                                requested = landing - fractions[(returns + Int(seed)) % fractions.count] * engine.tuning.playerHalfWidth + error
                            }
                            let step = scenario.speed / 120
                            engine.setPlayerX(engine.state.playerX + max(-step, min(step, requested - engine.state.playerX)))
                        }
                        let events = engine.update(delta: 1.0 / 120)
                        for event in events {
                            if case .paddleContact = event { returns += 1 }
                            if case .targetHit = event { hits += 1 }
                            if case .lifeLost = event { misses += 1 }
                            if case .waveCleared = event { clear = true }
                        }
                        frames += 1
                    }
                    if scenario.name != "delayed" { #expect(clear, "\(scenario.name) seed\(seed) wave\(wave): \(engine.state.targets.count) targets remain") }
                    #expect(hits <= [32, 44, 54][wave - 1])
                    #expect(engine.state.score >= 0)
                    rows.append(["scenario": scenario.name, "seed": seed, "wave": wave,
                                 "cleared": clear, "activeSeconds": active, "elapsedSeconds": Double(frames)/120,
                                 "hits": hits, "returns": returns, "chargedMisses": misses,
                                 "remainingTargets": engine.state.targets.count, "score": engine.state.score])
                }
            }
        }
        // Before values were captured from the unchanged forgiving-arcade-1 core,
        // with this same controller, seeds and stage setup. They are scenario evidence,
        // not human completion-time promises.
        let imperfectBaselineMean = [67.78333333333893, 96.1611111111337, 84.8916666666803]
        for wave in 1...3 {
            let measured = rows.filter { $0["scenario"] as? String == "imperfect" && $0["wave"] as? Int == wave }
            let mean = measured.reduce(0.0) { $0 + ($1["activeSeconds"] as! Double) } / Double(measured.count)
            #expect(mean < imperfectBaselineMean[wave - 1] * 0.85,
                    "The identical imperfect input cohort should materially shorten each wave")
        }
        for row in rows {
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print("PACING " + String(decoding: data, as: UTF8.self))
        }

    }
}
