import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Three waves and The Wall")
struct ProgressionBossTests {
    @Test("Each normal wave serves below its targets without free damage", arguments: [1, 2, 3])
    func safeNormalServe(number: Int) {
        let engine = GameEngine(seed: 11)
        engine.state.stage = .wave(number)
        engine.state.targets = AuthoredWaves.targets(for: number)
        var contacted = false
        for _ in 0..<600 {
            let events = engine.update(delta: 1.0 / 120)
            if events.paddleContacts > 0 { contacted = true; break }
            #expect(events.targetHits == 0)
            #expect(engine.state.score == 0)
        }
        #expect(contacted)
    }

    @Test("The Wall serves from its far-side position toward the player")
    func bossIncomingServe() throws {
        let engine = activeEngine(boss: true)
        engine.state.phase = .ready
        engine.state.phaseTimeRemaining = engine.tuning.fixedStep
        _ = engine.update(delta: engine.tuning.fixedStep)
        let ball = try #require(engine.state.ball)
        #expect(ball.position.y > 39)
        #expect(ball.velocity.y < 0)
        #expect(engine.state.bossPoints == 0)
        #expect(engine.state.score == 0)
    }

    @Test("Final target resolves score once before impact, cascade, blackout and next wave")
    func waveCompletionSequence() {
        let engine = activeEngine()
        engine.state.targets = [target(id: 1, kind: .paddle)]
        engine.state.ball = BallState(position: .init(x: 10, y: 27), velocity: .init(x: 0, y: 46))
        let hit = advance(engine, seconds: 0.05)
        #expect(engine.state.phase == .impact)
        #expect(engine.state.targets.isEmpty)
        #expect(engine.state.score == 350)
        #expect(hit.targetHits == 1)
        #expect(hit.contains(.waveCleared(number: 1)))
        let rest = advance(engine, seconds: 4)
        let phases = rest.compactMap { event -> GamePhase? in
            if case let .phaseChanged(phase) = event { return phase }; return nil
        }
        #expect(phases.starts(with: [.celebration, .blackout, .ready]))
        #expect(engine.state.stage == .wave(2))
        #expect(engine.state.targets == AuthoredWaves.targets(for: 2))
        #expect(engine.state.score == 350)
        #expect(rest.targetHits == 0)
        #expect(!rest.contains(.waveCleared(number: 1)))
    }

    @Test("Every authored wave transitions in order then enters the boss")
    func threeWaveProgression() {
        let engine = activeEngine()
        var allEvents: [GameEvent] = []
        for number in 1...3 {
            #expect(engine.state.stage == .wave(number))
            engine.state.phase = .playing
            engine.state.targets = [target(id: number, kind: .paddle)]
            engine.state.ball = BallState(position: .init(x: 10, y: 27), velocity: .init(x: 0, y: 46))
            allEvents += advance(engine, seconds: 4)
        }
        #expect(engine.state.stage == .boss)
        #expect(engine.state.boss != nil)
        #expect(engine.state.targets.isEmpty)
        #expect(engine.state.score == 1_050)
        #expect(engine.state.lives == 3)
        #expect(allEvents.filter { $0 == .bossIncoming }.count == 1)
    }

    @Test("Boss moves within a speed limit without teleporting")
    func bossMovementLimit() throws {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 2, movementTarget: 18, reactionRemaining: 1)
        engine.state.ball = BallState(position: .init(x: 18, y: 20), velocity: .init(x: 0, y: 26))
        let start = try #require(engine.state.boss).x
        _ = engine.update(delta: 0.1)
        let boss = try #require(engine.state.boss)
        #expect(boss.x > start)
        #expect(boss.x - start <= engine.tuning.boss.movementSpeed * 0.1 + 0.000_001)
        #expect(boss.x < boss.movementTarget)
        #expect(boss.x >= engine.tuning.boss.halfWidth)
        #expect(boss.x <= 20 - engine.tuning.boss.halfWidth)
    }

    @Test("Reaction target is held until the configured delay expires")
    func bossReactionTiming() throws {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 10, movementTarget: 10, reactionRemaining: 0.22)
        engine.state.ball = BallState(position: .init(x: 18, y: 20), velocity: .init(x: 0, y: 5))
        _ = advance(engine, seconds: 0.15)
        #expect(try #require(engine.state.boss).movementTarget == 10)
        expectNear(try #require(engine.state.boss).x, 10)
        _ = advance(engine, seconds: 0.1)
        #expect(try #require(engine.state.boss).movementTarget > 15)
    }

    @Test("The Wall can return an incoming shot exactly once")
    func bossReturn() throws {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 10, movementTarget: 10, reactionRemaining: 1)
        engine.state.ball = BallState(position: .init(x: 10, y: 39.8), velocity: .init(x: 0, y: 46))
        let events = advance(engine, seconds: 0.2)
        #expect(events.bossContacts == 1)
        #expect(events.bossPoints == 0)
        #expect(try #require(engine.state.ball).velocity.y < 0)
        #expect(try #require(engine.state.ball).speed <= engine.tuning.maximumBallSpeed + 0.000_001)
    }

    @Test("A shot past The Wall scores once beyond the far baseline")
    func bossCanLosePoint() {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 18, movementTarget: 18, reactionRemaining: 1)
        engine.state.ball = BallState(position: .init(x: 2, y: 39.8), velocity: .init(x: 0, y: 46))
        let events = advance(engine, seconds: 0.4)
        #expect(events.bossContacts == 0)
        #expect(events.bossPoints == 1)
        #expect(engine.state.bossPoints == 1)
        #expect(engine.state.phase == .ready)
        #expect(engine.state.ball == nil)
        #expect(engine.state.lives == 3)
        #expect(engine.state.score == 500)
    }

    @Test("Crossing the boss plane alone is not a point")
    func scoringBoundaryIsBehindBoss() {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 18, movementTarget: 18, reactionRemaining: 1)
        engine.state.ball = BallState(position: .init(x: 2, y: 40.6), velocity: .init(x: 0, y: 5))
        let events = advance(engine, seconds: 0.1)
        #expect(events.bossPoints == 0)
        #expect(engine.state.bossPoints == 0)
        #expect(engine.state.phase == .playing)
    }

    @Test("Boss side walls stay reflective")
    func bossSideBoundary() throws {
        let engine = activeEngine(boss: true)
        engine.state.ball = BallState(position: .init(x: 19.5, y: 20), velocity: .init(x: 35, y: 5))
        _ = engine.update(delta: 0.1)
        #expect(try #require(engine.state.ball).velocity.x < 0)
    }

    @Test("Long rallies accelerate gradually and obey the strict cap")
    func bossRallyAcceleration() throws {
        let engine = activeEngine(boss: true)
        engine.state.ball = BallState(position: .init(x: 8, y: 20), velocity: .init(x: 25, y: 5))
        let initial = try #require(engine.state.ball).speed
        _ = advance(engine, seconds: 0.5)
        let accelerated = try #require(engine.state.ball).speed
        #expect(accelerated > initial)
        #expect(accelerated <= initial + engine.tuning.boss.accelerationPerSecond * 0.5 + 0.000_001)
        engine.state.ball = BallState(position: .init(x: 8, y: 20), velocity: .init(x: 45.9, y: 0.1))
        _ = advance(engine, seconds: 1)
        #expect(try #require(engine.state.ball).speed <= engine.tuning.maximumBallSpeed + 0.000_001)
    }

    @Test("A point resets rally time and next launch speed")
    func bossPointResetsRally() throws {
        let engine = activeEngine(boss: true)
        engine.state.rallyTime = 60
        engine.state.boss = BossState(x: 18, movementTarget: 18, reactionRemaining: 1)
        engine.state.ball = BallState(position: .init(x: 2, y: 43.9), velocity: .init(x: 0, y: 46))
        _ = advance(engine, seconds: 0.1)
        #expect(engine.state.phase == .ready)
        #expect(engine.state.rallyTime == 0)
        _ = advance(engine, seconds: engine.tuning.readyDuration + 0.02)
        #expect(try #require(engine.state.ball).speed < engine.tuning.initialBallSpeed + 0.1)
    }

    @Test("Third boss point produces an extended victory cascade then winning results")
    func bossVictory() {
        let engine = activeEngine(boss: true)
        engine.state.boss = BossState(x: 18, movementTarget: 18, reactionRemaining: 1, points: 2)
        engine.state.ball = BallState(position: .init(x: 2, y: 43.9), velocity: .init(x: 0, y: 46))
        let point = advance(engine, seconds: 0.1)
        #expect(engine.state.bossPoints == 3)
        #expect(engine.state.won)
        #expect(point.bossPoints == 1)
        #expect(point.filter { $0 == .bossDefeated }.count == 1)
        #expect(engine.state.score == 1_500)
        _ = advance(engine, seconds: engine.tuning.impactDuration + engine.tuning.celebrationDuration)
        #expect(engine.state.phase == .celebration)
        let ending = advance(engine, seconds: 3)
        #expect(engine.state.phase == .results)
        #expect(ending.filter { if case .runEnded(won: true, _) = $0 { return true }; return false }.count == 1)
        #expect(advance(engine, seconds: 2).isEmpty)
    }

    @Test("Last life produces exactly one losing result")
    func playerDefeat() {
        let engine = activeEngine()
        engine.state.recoveriesRemaining = 0
        engine.state.lives = 1
        engine.state.ball = BallState(position: .init(x: 18, y: 0.1), velocity: .init(x: 0, y: -46))
        let events = advance(engine, seconds: 4)
        #expect(engine.state.lives == 0)
        #expect(engine.state.phase == .results)
        #expect(!engine.state.won)
        #expect(events.lifeLosses == 1)
        #expect(events.filter { if case .runEnded(won: false, _) = $0 { return true }; return false }.count == 1)
        #expect(advance(engine, seconds: 2).isEmpty)
    }
}
