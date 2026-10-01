import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Dense workload measurements")
struct PerformanceTests {
    @Test("Swept dense collision work remains finite under repeated maximum-speed arrivals")
    func denseCollisionWorkload() throws {
        // Synthetic focused collision workload, not level completion or human
        // balance evidence. Durable fixture targets keep all 58 colliders live.
        let targets = (0..<58).map { index in
            TargetState(id: index, kind: .paddle,
                        position: .init(x: 1.5 + Double(index % 10) * 1.85,
                                        y: 28 + Double(index / 10) * 2.4),
                        radius: 0.45, health: 10_000)
        }
        let episodes = 256
        let stepsPerEpisode = 128
        var hits = 0
        var walls = 0
        var longestChain = 0
        let start = ProcessInfo.processInfo.systemUptime
        for episode in 0..<episodes {
            let engine = activeEngine(seed: UInt64(episode))
            engine.state.targets = targets
            let target = targets[episode % targets.count]
            engine.state.ball = BallState(position: target.position + .init(x: 0, y: -1.1),
                                          velocity: .init(x: episode % 2 == 0 ? 9 : -9,
                                                          y: sqrt(46 * 46 - 9 * 9)))
            for _ in 0..<stepsPerEpisode {
                if let ball = engine.state.ball { engine.setPlayerX(ball.position.x) }
                let events = engine.update(delta: engine.tuning.fixedStep)
                hits += events.targetHits
                walls += events.filter { $0 == .wallContact }.count
                longestChain = max(longestChain, engine.state.targetChain)
                if let ball = engine.state.ball {
                    #expect(ball.position.x.isFinite && ball.position.y.isFinite)
                    #expect(ball.speed <= engine.tuning.maximumBallSpeed + 0.000001)
                }
                #expect(engine.state.targets.count == 58)
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(hits >= episodes)
        #expect(longestChain > 1)
        print("DENSE_CORE_PERFORMANCE fixture_targets=58 steps=\(episodes * stepsPerEpisode) target_hits=\(hits) walls=\(walls) longest_chain=\(longestChain) host_elapsed_seconds=\(elapsed) host_microseconds_per_step=\(elapsed * 1_000_000 / Double(episodes * stepsPerEpisode)) includes_test_assertions=true watch_fps=unmeasured")
    }
}
