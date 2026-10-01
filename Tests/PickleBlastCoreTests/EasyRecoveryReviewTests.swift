import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Independent easy return and recovery review")
struct EasyRecoveryReviewTests {
    private func playing(boss: Bool = false) -> GameEngine {
        let engine = GameEngine(seed: 0xEA51)
        engine.state.phase = .playing
        engine.state.phaseTimeRemaining = 0
        engine.state.targets = []
        if boss { engine.state.stage = .boss; engine.state.boss = BossState() }
        return engine
    }

    @Test("Swept fringe catches exactly once while a true miss spends a recovery, for grouped frames and boss rallies",
          arguments: [false, true])
    func sweptFringeAndStrictMiss(boss: Bool) throws {
        for side in [-1.0, 1.0] {
            for outside in [false, true] {
                func run(frame: Double) -> (GameState, [GameEvent]) {
                    let engine = playing(boss: boss)
                    let reach = engine.tuning.playerHalfWidth + engine.tuning.ballRadius
                    engine.state.ball = BallState(position: .init(x: 10 + side * (reach + (outside ? 0.001 : -0.001)), y: 3),
                                                  velocity: .init(x: 0, y: -46))
                    return (advanceThenState(engine, seconds: 0.1, frame: frame))
                }
                let fixed = run(frame: 1.0 / 120)
                let grouped = run(frame: 0.1)
                #expect(fixed.0 == grouped.0)
                #expect(fixed.1 == grouped.1)
                #expect(fixed.1.paddleContacts == (outside ? 0 : 1))
                #expect(fixed.1.lifeLosses == 0)
                #expect(fixed.0.lives == 3)
                let recoveries = fixed.1.filter { if case .ballRecovered = $0 { return true }; return false }.count
                #expect(recoveries == (outside ? 1 : 0))
                #expect(fixed.0.recoveriesRemaining == (outside ? 1 : 2))
                if !outside {
                    let ball = try #require(fixed.0.ball)
                    #expect(ball.position.y > 2.5 && ball.velocity.y > 0)
                    expectNear(ball.speed, 46)
                }
            }
        }
    }

    private func advanceThenState(_ engine: GameEngine, seconds: Double, frame: Double) -> (GameState, [GameEvent]) {
        let events = advance(engine, seconds: seconds, frame: frame)
        return (engine.state, events)
    }

    @Test("Two recoveries preserve earned progress and the third miss charges one life without a paddle event",
          arguments: [false, true])
    func progressPreservedAcrossRecovery(boss: Bool) throws {
        let engine = playing(boss: boss)
        engine.state.score = 725
        if boss { engine.state.boss!.points = 2 }
        else { engine.state.targets = [target(id: 19, kind: .paddle, x: 16, y: 35)] }
        let targets = engine.state.targets
        for miss in 1...3 {
            engine.state.phase = .playing
            engine.state.targetChain = 5
            engine.state.ball = BallState(position: .init(x: 0.3, y: 0), velocity: .init(x: 0, y: -26))
            let events = engine.update(delta: 0.1)
            #expect(events.paddleContacts == 0)
            #expect(events.lifeLosses == (miss == 3 ? 1 : 0))
            #expect(engine.state.lives == (miss == 3 ? 2 : 3))
            #expect(engine.state.recoveriesRemaining == max(0, 2 - miss))
            #expect(engine.state.score == 725)
            #expect(engine.state.targetChain == 0)
            #expect(engine.state.targets == targets)
            #expect(engine.state.boss?.points == (boss ? 2 : nil))
            #expect(engine.state.phase == .ready && engine.state.ball == nil)
            #expect(events.filter { if case .comboChanged(chain: 0, multiplier: 1) = $0 { return true }; return false }.count == 1)
            #expect(events.filter { if case .ballRecovered = $0 { return true }; return false }.count == (miss <= 2 ? 1 : 0))
        }
    }

    @Test("Pause and boss point serves preserve the remaining allowance; a new stage resets exactly once")
    func allowanceBoundaries() throws {
        let engine = playing(boss: true)
        engine.state.recoveriesRemaining = 1
        engine.state.boss!.points = 1
        engine.state.ball = BallState(position: .init(x: 0.3, y: 44.2), velocity: .init(x: 0, y: 26))
        let point = engine.update(delta: 0.1)
        #expect(point.bossPoints == 1)
        #expect(engine.state.boss?.points == 2)
        #expect(engine.state.recoveriesRemaining == 1)
        engine.pause()
        let paused = engine.state
        #expect(engine.update(delta: 60).isEmpty)
        #expect(engine.state == paused)
        engine.resume()
        advance(engine, seconds: engine.tuning.resumeDuration + engine.tuning.readyDuration + 0.01)
        #expect(engine.state.recoveriesRemaining == 1)
        #expect(engine.state.boss?.points == 2)

        engine.state.recoveriesRemaining = 0
        engine.state.stage = .wave(2)
        engine.state.phase = .blackout
        engine.state.phaseTimeRemaining = engine.tuning.fixedStep
        engine.update(delta: engine.tuning.fixedStep)
        #expect(engine.state.stage == .wave(3))
        #expect(engine.state.recoveriesRemaining == 2)
        engine.state.recoveriesRemaining = 1
        advance(engine, seconds: engine.tuning.readyDuration + 0.1)
        #expect(engine.state.recoveriesRemaining == 1)
        engine.reset()
        #expect(engine.state.stage == .wave(1) && engine.state.recoveriesRemaining == 2)
        #expect(engine.state.score == 0 && engine.state.lives == 3)
    }
}
