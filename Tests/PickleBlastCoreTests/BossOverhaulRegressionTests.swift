import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Boss Rally overhaul regression coverage")
struct BossOverhaulRegressionTests {
    @Test("Rally-only tuning cannot change the Arcade trace")
    func arcadeTraceIgnoresRallyTuning() {
        let baseline = GameEngine(mode: .arcade, seed: 0xA11CE)
        var rallyTuning = GameTuning()
        rallyTuning.rallyMotionInfluenceEnabled = true
        rallyTuning.rallyMotionSampleWindow = 0.12
        rallyTuning.rallyMotionMaximumApparentAngle = .pi * 4 / 180
        rallyTuning.rallyWall.maximumLateralSpeed = 1
        rallyTuning.rallyWall.lateralAcceleration = 2
        rallyTuning.rallyWall.lateralBraking = 3
        rallyTuning.rallyWall.observationDelay = 0.8
        rallyTuning.rallyBanger.maximumLateralSpeed = 2
        rallyTuning.rallyPoacher.maximumLateralSpeed = 3
        let configured = GameEngine(mode: .arcade, tuning: rallyTuning, seed: 0xA11CE)

        for tick in 0..<3_600 {
            let desiredX = 10 + 8.5 * sin(Double(tick) * 0.017)
            baseline.movePlayer(crownDelta: desiredX - baseline.state.playerX, sensitivity: 1)
            configured.movePlayer(crownDelta: desiredX - configured.state.playerX, sensitivity: 1)
            let expectedEvents = baseline.update(delta: 1.0 / 60.0)
            let actualEvents = configured.update(delta: 1.0 / 60.0)
            #expect(actualEvents == expectedEvents)
            #expect(configured.state == baseline.state)
        }
    }

    @Test("Reset clears private rally history and reproduces a fresh seeded session",
          arguments: BossID.allCases)
    func resetReproducesFreshSession(id: BossID) {
        let seed: UInt64 = 0xB055_721
        let reused = GameEngine(mode: .bossRally(id), seed: seed)
        for tick in 0..<2_400 {
            let desiredX = 10 + 8.2 * sin(Double(tick) * 0.031)
            reused.movePlayer(crownDelta: desiredX - reused.state.playerX, sensitivity: 1)
            _ = reused.update(delta: 1.0 / 60.0)
            if reused.state.phase == .results { break }
        }

        reused.reset(seed: seed)
        let fresh = GameEngine(mode: .bossRally(id), seed: seed)
        #expect(reused.state.mode == .bossRally(id))
        #expect(reused.state == fresh.state)

        for tick in 0..<3_600 {
            let desiredX = 10 + 8.2 * sin(Double(tick) * 0.031)
            reused.movePlayer(crownDelta: desiredX - reused.state.playerX, sensitivity: 1)
            fresh.movePlayer(crownDelta: desiredX - fresh.state.playerX, sensitivity: 1)
            let reusedEvents = reused.update(delta: 1.0 / 60.0)
            let freshEvents = fresh.update(delta: 1.0 / 60.0)
            #expect(reusedEvents == freshEvents)
            #expect(reused.state == fresh.state)
        }
    }
}
