import Foundation
import Testing
import PickleBlastCore

@Suite("Consecutive complete Arcade runs")
struct RepeatedArcadeRunsTests {
    @Test("Ten public-input runs preserve accepted progression, score and cleanup")
    func tenRunsAndReplays() {
        let engine = GameEngine(seed: 7)
        for run in 0..<10 {
            if run > 0 { engine.reset(seed: 7) }
            var player = AutomaticPlayer()
            var waves: [Int] = []
            var points: [Int] = []
            var cleanups = [0, 0, 0]
            var ended = 0
            var peakCascade = 0
            var frames = 0

            #expect(engine.state.mode == .arcade)
            #expect(engine.state.stage == .wave(1))
            #expect(engine.state.score == 0)
            #expect(engine.state.lives == 3)
            #expect(engine.state.boss == nil)
            #expect(engine.state.celebration.activeCount == 0)

            while engine.state.phase != .results && frames < 144_000 {
                let stage = engine.state.stage
                player.position(in: engine)
                let events = engine.update(delta: 1.0 / 120)
                player.observe(events, stage: engine.state.stage)
                for event in events {
                    switch event {
                    case let .waveCleared(number): waves.append(number)
                    case let .bossPoint(number): points.append(number)
                    case .targetCleaned:
                        if let wave = stage.waveNumber { cleanups[wave - 1] += 1 }
                    case .runEnded: ended += 1
                    default: break
                    }
                }
                peakCascade = max(peakCascade, engine.state.celebration.activeCount)
                frames += 1
            }

            #expect(engine.state.phase == .results, "Run \(run) stopped at \(engine.state.stage) after \(frames) frames")
            #expect(engine.state.won)
            #expect(waves == [1, 2, 3])
            #expect(points == [1, 2, 3])
            #expect(cleanups == [4, 4, 4])
            #expect(ended == 1)
            #expect(engine.state.score == 60_225)
            #expect(engine.state.lives == 3)
            #expect(engine.state.targets.isEmpty)
            #expect(engine.state.celebration.activeCount == 0)
            #expect(peakCascade >= 100)
            #expect(engine.state.longestRallyReturns >= 2)
            #expect(engine.update(delta: 1).isEmpty)
        }
    }
}
