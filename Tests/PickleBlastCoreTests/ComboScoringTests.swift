import Foundation
import Testing
@testable import PickleBlastCore

/// Focused collision fixtures deliberately place incoming balls. Full-run tests
/// separately exercise ordinary controls without replacing game state.
@Suite("Deterministic target chains and rewards")
struct ComboScoringTests {
    private func strike(_ engine: GameEngine, id: Int = 1) -> [GameEvent] {
        let target = engine.state.targets.first { $0.id == id }!
        engine.state.ball = BallState(position: .init(x: target.position.x, y: target.position.y - target.radius - 0.5),
                                      velocity: .init(x: 0, y: 46))
        return advance(engine, seconds: 0.08)
    }

    private func fixture(kind: TargetKind = .paddle, size: TargetSize = .small) -> GameEngine {
        var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0 // Isolate player-earned awards.
        let engine = activeEngine(tuning: tuning)
        engine.state.targets = [TargetState(id: 1, kind: kind, position: .init(x: 10, y: 30), size: size),
                                target(id: 99, kind: .paddle, x: 18, y: 40)]
        return engine
    }

    @Test("Consecutive damaging contacts increment before awards and cap at five times")
    func thresholdAccounting() {
        let engine = fixture()
        var awards: [Int] = []
        var thresholds: [GameEvent] = []
        for hit in 1...7 {
            engine.state.targets = [target(id: hit, kind: .paddle), target(id: 99, kind: .paddle, x: 18, y: 40)]
            let events = strike(engine, id: hit)
            for event in events {
                if case let .targetHit(_, _, _, score) = event { awards.append(score) }
                if case .comboChanged = event { thresholds.append(event) }
            }
            #expect(engine.state.targetChain == hit)
            #expect(events.targetHits == 1)
        }
        #expect(awards == [100, 200, 300, 300, 500, 500, 500])
        #expect(engine.state.score == awards.reduce(0, +))
        #expect(thresholds == [.comboChanged(chain: 2, multiplier: 2),
                               .comboChanged(chain: 3, multiplier: 3),
                               .comboChanged(chain: 5, multiplier: 5)])
    }

    @Test("One, two and three hit paddles have distinct health, damage state and final rewards",
          arguments: [TargetSize.small, .medium, .large])
    func tierDamage(size: TargetSize) throws {
        let engine = fixture(size: size)
        let expectedAwards: [Int]
        switch size {
        case .small: expectedAwards = [100]
        case .medium: expectedAwards = [125, 450]
        case .large: expectedAwards = [200, 400, 1_200]
        }
        var events: [GameEvent] = []
        for hit in 1...size.maximumHealth {
            events += strike(engine)
            if hit < size.maximumHealth {
                let remaining = try #require(engine.state.targets.first { $0.id == 1 })
                #expect(remaining.health == size.maximumHealth - hit)
                #expect(remaining.maximumHealth == size.maximumHealth)
                #expect(remaining.isDamaged)
            }
        }
        let awards = events.compactMap { event -> Int? in
            if case let .targetHit(_, _, _, score) = event { return score }
            return nil
        }
        #expect(awards == expectedAwards)
        #expect(engine.state.score == expectedAwards.reduce(0, +))
        #expect(!engine.state.targets.contains { $0.id == 1 })
        #expect(events.filter { if case .targetHit(_, _, destroyed: true, _) = $0 { return true }; return false }.count == 1)
        let after = advance(engine, seconds: 0.1)
        #expect(after.targetHits == 0)
        #expect(engine.state.score == expectedAwards.reduce(0, +))
    }

    @Test("Basket final hit replaces its base award once before the combo multiplier")
    func basketReward() {
        let engine = fixture(kind: .basket)
        #expect(strike(engine).contains(.targetHit(id: 1, kind: .basket, destroyed: false, score: 75)))
        #expect(strike(engine).contains(.targetHit(id: 1, kind: .basket, destroyed: true, score: 350)))
        #expect(engine.state.score == 425)
    }

    @Test("Continuous contact cannot repeatedly damage or increment the chain")
    func noDuplicateContinuousDamage() {
        let engine = fixture(size: .large)
        engine.state.ball = BallState(position: .init(x: 10, y: 28.5), velocity: .init(x: 0, y: 26))
        let events = advance(engine, seconds: 0.2)
        #expect(events.targetHits == 1)
        #expect(engine.state.targetChain == 1)
        #expect(engine.state.targets.first { $0.id == 1 }?.health == 2)
        #expect(engine.state.score == 200)
    }

    @Test("Successful return resets before a subsequent target hit")
    func playerReturnReset() {
        let engine = fixture(size: .large)
        _ = strike(engine)
        engine.state.ball = BallState(position: .init(x: 10, y: 2.6), velocity: .init(x: 0, y: -26))
        let returned = advance(engine, seconds: 0.02)
        #expect(returned.paddleContacts == 1)
        #expect(returned.contains(.comboChanged(chain: 0, multiplier: 1)))
        #expect(engine.state.targetChain == 0)
        let hit = strike(engine)
        #expect(hit.contains(.targetHit(id: 1, kind: .paddle, destroyed: false, score: 200)))
    }

    @Test("Both final and nonfinal life loss reset the chain", arguments: [1, 3])
    func lifeLossReset(lives: Int) {
        let engine = fixture(size: .large)
        _ = strike(engine)
        engine.state.recoveriesRemaining = 0
        engine.state.lives = lives
        engine.state.ball = BallState(position: .init(x: 18, y: 0), velocity: .init(x: 0, y: -26))
        let events = advance(engine, seconds: 0.03)
        #expect(events.lifeLosses == 1)
        #expect(events.contains(.comboChanged(chain: 0, multiplier: 1)))
        #expect(engine.state.targetChain == 0)
        #expect(engine.state.score == 200)
    }

    @Test("New wave, boss entry and restart reset target chains", arguments: [1, 3])
    func stageAndRestartReset(wave: Int) {
        let engine = fixture()
        engine.state.targetChain = 5
        engine.state.stage = .wave(wave)
        engine.state.phase = .blackout
        engine.state.phaseTimeRemaining = 0
        let events = engine.update(delta: engine.tuning.fixedStep)
        #expect(events.contains(.comboChanged(chain: 0, multiplier: 1)))
        #expect(engine.state.targetChain == 0)
        #expect(engine.state.stage == (wave == 3 ? .boss : .wave(2)))
        engine.state.targetChain = 7
        engine.reset()
        #expect(engine.state.targetChain == 0)
        #expect(engine.state.score == 0)
    }

    @Test("Pause, countdown and side and far walls preserve the chain")
    func pauseAndWallsPreserve() {
        let engine = fixture(size: .large)
        _ = strike(engine)
        engine.pause()
        #expect(advance(engine, seconds: 3).isEmpty)
        #expect(engine.state.targetChain == 1)
        engine.resume()
        _ = advance(engine, seconds: engine.tuning.resumeDuration)
        #expect(engine.state.targetChain == 1)
        engine.state.ball = BallState(position: .init(x: 0.31, y: 43.69), velocity: .init(x: -20, y: 20))
        let events = advance(engine, seconds: 0.02)
        #expect(events.filter { $0 == .wallContact }.count == 2)
        #expect(!events.contains { if case .comboChanged = $0 { return true }; return false })
        #expect(engine.state.targetChain == 1)
        #expect(engine.state.score == 200)
    }

    @Test("Final target award precedes threshold, wave bonus and completion exactly once")
    func finalTargetOrder() {
        let engine = fixture()
        engine.state.targets.removeLast()
        engine.state.targetChain = 1
        let events = strike(engine)
        #expect(Array(events.prefix(3)) == [.targetHit(id: 1, kind: .paddle, destroyed: true, score: 200),
                                          .comboChanged(chain: 2, multiplier: 2), .waveCleared(number: 1)])
        #expect(engine.state.score == 450)
        #expect(advance(engine, seconds: 0.1).targetHits == 0)
        #expect(engine.state.score == 450)
    }

    @Test("Boss points and victory bonus never receive a target multiplier")
    func bossScoreUnchanged() {
        let engine = activeEngine(boss: true)
        engine.state.boss?.points = 2
        engine.state.ball = BallState(position: .init(x: 1, y: 44.2), velocity: .init(x: 0, y: 26))
        let events = advance(engine, seconds: 0.02)
        #expect(events.contains(.bossPoint(points: 3)))
        #expect(events.contains(.bossDefeated))
        #expect(engine.state.score == 1_500)
        #expect(engine.state.targetChain == 0)
    }
}
