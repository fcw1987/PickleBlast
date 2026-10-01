import Foundation
import Testing
import PickleBlastCore

@Suite("Accepted Arcade baseline")
struct AcceptedArcadeBaselineTests {
    @Test("Physical-play tuning stays at easier-returns-1")
    func acceptedTuning() {
        let tuning = GameTuning()
        #expect(GameTuning.revision == "easier-returns-1")
        #expect(tuning.fixedStep == 1.0 / 120.0)
        #expect(tuning.playerHalfWidth == 3.25)
        #expect(tuning.maximumIncomingApparentAngle == .pi * 35 / 180)
        #expect(tuning.maximumOutgoingApparentAngle == .pi * 45 / 180)
        #expect(tuning.freeRecoveriesPerStage == 2)
        #expect(tuning.recoveryReadyDuration == 0.75)
        #expect(tuning.initialLives == 3)
        #expect(tuning.initialBallSpeed == 26)
        #expect(tuning.maximumBallSpeed == 46)
        #expect(tuning.cleanupTargetThreshold == 4)
        #expect(tuning.celebrationDuration == 2.0)
        #expect(tuning.boss.movementSpeed == 5.5)
        #expect(tuning.boss.reactionDelay == 0.22)
        #expect(tuning.boss.pointsToWin == 3)
        #expect(AuthoredWaves.targets(for: 1).count == 36)
        #expect(AuthoredWaves.targets(for: 2).count == 48)
        #expect(AuthoredWaves.targets(for: 3).count == 58)
        #expect([1, 2, 3].allSatisfy { AuthoredWaves.targets(for: $0).allSatisfy { $0.health == 1 } })
    }

    @Test("Seeded public-input play keeps its accepted wave and score fingerprint")
    func publicInputTrace() {
        let engine = GameEngine(seed: 0xA6C4DE)
        var counts = [Int](repeating: 0, count: 12)
        var phases: [GamePhase] = []

        // This intentionally modest controller uses the same position APIs as
        // touch and Crown. It never changes the ball, targets or stage directly.
        for frame in 0..<14_400 {
            if let ball = engine.state.ball, ball.velocity.y < 0,
               ball.position.y <= CourtGeometry.netY, engine.state.phase == .playing {
                let contactY = engine.tuning.playerY + ball.radius
                let arrival = max(0, (contactY - ball.position.y) / ball.velocity.y)
                let wanted = ball.position.x + ball.velocity.x * arrival
                if frame.isMultiple(of: 2) { engine.setPlayerX(wanted) }
                else { engine.movePlayer(crownDelta: wanted - engine.state.playerX) }
            }
            for event in engine.update(delta: 1.0 / 120) {
                switch event {
                case let .phaseChanged(phase): counts[0] += 1; phases.append(phase)
                case .paddleContact: counts[1] += 1
                case .targetHit: counts[2] += 1
                case .targetCleaned: counts[3] += 1
                case .ballRecovered: counts[4] += 1
                case .comboChanged: counts[5] += 1
                case .wallContact: counts[6] += 1
                case .lifeLost: counts[7] += 1
                case .waveCleared: counts[8] += 1
                case .bossIncoming: counts[9] += 1
                case .bossContact: counts[10] += 1
                case .bossPoint: counts[11] += 1
                default: break
                }
            }
        }

        #expect(counts == [13, 32, 78, 8, 0, 33, 76, 0, 2, 0, 0, 0])
        #expect(phases == [.playing, .cleanup, .impact, .celebration, .blackout, .ready,
                           .playing, .cleanup, .impact, .celebration, .blackout, .ready, .playing])
        #expect(engine.state.stage == .wave(3))
        #expect(engine.state.phase == .playing)
        #expect(engine.state.score == 32_025)
        #expect(engine.state.lives == 3)
        #expect(engine.state.recoveriesRemaining == 2)
        #expect(engine.state.targets.count == 56)
    }
}
