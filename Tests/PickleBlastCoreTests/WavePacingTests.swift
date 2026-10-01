import Foundation
import Testing
@testable import PickleBlastCore

@Suite("One-hit dense waves and deterministic finishing chains")
struct WavePacingTests {
    private func fixture(remaining: Int = 4, durable: Bool = false) -> GameEngine {
        let engine = activeEngine()
        engine.state.targets = [TargetState(id: 50, kind: .paddle, position: .init(x: 10, y: 30),
                                           radius: 0.5, health: durable ? 2 : 1,
                                           maximumHealth: durable ? 2 : 1)]
        let rewards: [(Int, TargetKind, TargetSize)] = [(4, .paddle, .large), (1, .paddle, .small),
                                                      (3, .basket, .medium), (2, .paddle, .medium),
                                                      (5, .paddle, .small)]
        for (index, reward) in rewards.prefix(remaining).enumerated() {
            engine.state.targets.append(TargetState(id: reward.0, kind: reward.1,
                position: .init(x: 3 + Double(index) * 3, y: 40), radius: 0.5, health: 1,
                size: reward.2, maximumHealth: 1))
        }
        engine.state.ball = BallState(position: .init(x: 10, y: 29.1), velocity: .init(x: 0, y: 46))
        return engine
    }

    @Test("Every authored normal target dies in one legitimate contact and larger targets retain value",
          arguments: [1, 2, 3])
    func singleHitAuthored(number: Int) {
        var tuning = GameTuning()
        tuning.cleanupTargetThreshold = 0
        for target in AuthoredWaves.targets(for: number) {
            let engine = activeEngine(tuning: tuning)
            engine.state.targets = [target, TargetState(id: -1, kind: .paddle,
                position: .init(x: target.position.x < 10 ? 18 : 2, y: 25), radius: 0.5)]
            engine.state.ball = BallState(position: .init(x: target.position.x,
                y: target.position.y - target.radius - tuning.ballRadius - 0.05), velocity: .init(x: 0, y: 26))
            let events = engine.update(delta: tuning.fixedStep)
            let award = tuning.score(for: target.kind, size: target.size, destroyed: true)
            #expect(events.contains(.targetHit(id: target.id, kind: target.kind, destroyed: true, score: award)))
            #expect(!engine.state.targets.contains { $0.id == target.id })
            #expect(events.targetHits == 1)
            #expect(engine.state.score == award)
            if target.size != .small { #expect(award > tuning.paddleScore) }
        }
    }

    @Test("Four survivors clear in stable order at base value without additional ricochet chain")
    func cleanupAccountingAndOrder() {
        let engine = fixture()
        engine.state.targetChain = 4
        let initial = engine.update(delta: engine.tuning.fixedStep)
        #expect(initial.targetHits == 1)
        #expect(initial.contains(.targetHit(id: 50, kind: .paddle, destroyed: true, score: 500)))
        #expect(engine.state.phase == .cleanup)
        #expect(engine.state.ball == nil)
        #expect(engine.state.targetChain == 5)
        #expect(engine.state.score == 500)
        var events = initial
        events += advance(engine, seconds: 0.45)
        let cleaned = events.compactMap { event -> Int? in
            if case let .targetCleaned(id, _, _) = event { return id }; return nil
        }
        let cleanupScores = events.compactMap { event -> Int? in
            if case let .targetCleaned(_, _, score) = event { return score }; return nil
        }
        #expect(cleaned == [1, 2, 3, 4])
        #expect(cleanupScores == [100, 225, 175, 400])
        #expect(events.targetHits == 1)
        #expect(events.filter { if case .comboChanged = $0 { return true }; return false }.count == 1)
        #expect(events.filter { if case .waveCleared = $0 { return true }; return false }.count == 1)
        #expect(engine.state.targets.isEmpty)
        #expect(engine.state.score == 1_650)
        #expect(engine.state.lives == 3)
        let later = advance(engine, seconds: 0.1)
        #expect(later.targetHits == 0)
        #expect(!later.contains { if case .targetCleaned = $0 { return true }; return false })
        #expect(engine.state.score == 1_650)
    }

    @Test("Cleanup cannot start from a ready state, a nondestroying hit, or five remaining targets")
    func onlyDestructionTriggersThreshold() {
        let ready = fixture()
        ready.state.targets.removeFirst()
        ready.state.ball = nil
        ready.state.phase = .ready
        ready.state.phaseTimeRemaining = 0.5
        _ = advance(ready, seconds: 0.1)
        #expect(ready.state.phase == .ready)
        #expect(ready.state.targets.count == 4)
        let durable = fixture(remaining: 3, durable: true)
        let hit = durable.update(delta: durable.tuning.fixedStep)
        #expect(hit.targetHits == 1)
        #expect(durable.state.phase == .playing)
        #expect(durable.state.targets.count == 4)
        let five = fixture(remaining: 5)
        _ = five.update(delta: five.tuning.fixedStep)
        #expect(five.state.phase == .playing)
        #expect(five.state.targets.count == 5)
    }

    @Test("Cleanup freezes during pause and resume countdown and has no life-loss or ball collisions")
    func cleanupLifecycle() {
        let engine = fixture()
        _ = engine.update(delta: engine.tuning.fixedStep)
        let before = engine.state
        engine.pause()
        #expect(advance(engine, seconds: 10).isEmpty)
        #expect(engine.state.targets == before.targets)
        #expect(engine.state.score == before.score)
        #expect(engine.state.phaseTimeRemaining == before.phaseTimeRemaining)
        engine.resume()
        _ = advance(engine, seconds: engine.tuning.resumeDuration)
        #expect(engine.state.targets == before.targets)
        let events = advance(engine, seconds: 0.45)
        #expect(events.lifeLosses == 0)
        #expect(events.paddleContacts == 0)
        #expect(events.targetHits == 0)
        #expect(engine.state.recoveriesRemaining == before.recoveriesRemaining)
    }

    @Test("Simultaneous final target opportunities cannot double award or advance a stage")
    func simultaneousBoundary() {
        let engine = fixture(remaining: 1)
        engine.state.targets = [TargetState(id: 1, kind: .paddle, position: .init(x: 9.2, y: 30), radius: 0.55),
                                TargetState(id: 2, kind: .paddle, position: .init(x: 10.8, y: 30), radius: 0.55)]
        engine.state.ball = BallState(position: .init(x: 10, y: 29.7), velocity: .init(x: 0, y: 46))
        let events = advance(engine, seconds: 0.5)
        #expect(events.targetHits == 1)
        #expect(events.filter { if case .targetCleaned = $0 { return true }; return false }.count == 1)
        #expect(events.filter { if case .waveCleared = $0 { return true }; return false }.count == 1)
        #expect(engine.state.score == 450)
        #expect(engine.state.lives == 3)
    }
}
