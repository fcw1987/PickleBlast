import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Forgiving arcade return revision")
struct ReturnForgivenessTests {
    @Test("Revision widens configured reach before radius expansion without changing movement or speed")
    func revisionValues() {
        let tuning = GameTuning()
        expectNear(tuning.playerHalfWidth, 3.25)
        expectNear(2 * (tuning.playerHalfWidth + tuning.ballRadius), 7.10)
        expectNear(tuning.maximumIncomingApparentAngle, .pi * 35 / 180)
        expectNear(tuning.maximumOutgoingApparentAngle, .pi / 4)
        expectNear(tuning.playerMargin, 1.1)
        expectNear(tuning.playerY, 2.2)
        expectNear(tuning.ballRadius, 0.30)
        expectNear(tuning.initialBallSpeed, 26)
        expectNear(tuning.maximumBallSpeed, 46)
        expectNear(tuning.boss.halfWidth, 1.75)
        expectNear(tuning.boss.movementSpeed, 5.5)
        expectNear(tuning.boss.reactionDelay, 0.22)
        expectNear(tuning.boss.maximumReturnAngle, .pi / 3)
    }

    @Test("Old near misses now return in waves and boss rallies", arguments: [false, true])
    func extendedReach(boss: Bool) throws {
        for side in [-1.0, 1.0] {
            let engine = activeEngine(boss: boss)
            let offset = side * 2.35 // Beyond old effective 1.95, inside new configured 2.475.
            engine.state.ball = BallState(position: .init(x: 10 + offset, y: 3.6),
                                          velocity: .init(x: 0, y: -26))
            let events = advance(engine, seconds: 0.2)
            #expect(events.paddleContacts == 1)
            #expect(events.lifeLosses == 0)
            #expect(engine.state.lives == 3)
            let ball = try #require(engine.state.ball)
            #expect(ball.velocity.y > 0)
            #expect(ball.velocity.x * side > 0)
        }
    }

    @Test("Radius-expanded outer reach is finite and beyond it still misses", arguments: [-1.0, 1.0])
    func finiteReach(side: Double) {
        for outside in [false, true] {
            let engine = activeEngine()
            engine.state.recoveriesRemaining = 0 // A genuine charged miss remains possible.
            let reach = engine.tuning.playerHalfWidth + engine.tuning.ballRadius
            engine.state.ball = BallState(position: .init(x: 10 + side * (reach + (outside ? 0.02 : -0.02)), y: 3.6),
                                          velocity: .init(x: 0, y: -26))
            let events = advance(engine, seconds: 0.2)
            #expect(events.paddleContacts == (outside ? 0 : 1))
            #expect(events.lifeLosses == (outside ? 1 : 0))
        }
    }

    @Test("Aim is normalized to enlarged configured reach and preserves speed", arguments: [26.0, 35.0, 46.0])
    func normalizedAim(speed: Double) {
        let engine = activeEngine()
        for fraction in [-1.12, -1.0, -0.5, 0.0, 0.5, 1.0, 1.12] {
            let velocity = engine.playerReturnVelocity(contactX: 10 + fraction * engine.tuning.playerHalfWidth,
                                                       speed: speed)
            let expectedAngle = abs(max(-1, min(1, fraction))) * 45 * Double.pi / 180
            expectNear(ReceivingTrajectory.apparentAngle(of: velocity,
                at: .init(x: 10 + fraction * engine.tuning.playerHalfWidth, y: 2.5),
                projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor), expectedAngle)
            expectNear(velocity.length, speed)
            #expect(velocity.y > 0)
        }
        // An old-edge offset must no longer saturate at the newly reduced cap.
        let oldEdge = engine.playerReturnVelocity(contactX: 11.65, speed: speed)
        expectNear(ReceivingTrajectory.apparentAngle(of: oldEdge, at: .init(x: 11.65, y: 2.5),
            projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor), (1.65 / 3.25) * 45 * .pi / 180)
    }

    @Test("Incoming side-wall ties produce one return and remain inside court", arguments: [-1.0, 1.0])
    func sideWallTie(side: Double) throws {
        let engine = activeEngine()
        engine.setPlayerX(side < 0 ? 0 : CourtGeometry.width)
        let radius = engine.tuning.ballRadius
        let x = side < 0 ? radius : CourtGeometry.width - radius
        // Both planes are reached simultaneously within one fixed step.
        let velocity = Vector2(x: side * 20, y: -sqrt(46 * 46 - 20 * 20))
        let time = engine.tuning.fixedStep * 0.5
        let contact = Vector2(x: x, y: engine.tuning.playerY + radius)
        engine.state.ball = BallState(position: contact - velocity * time, velocity: velocity)
        let events = advance(engine, seconds: 0.1)
        let ball = try #require(engine.state.ball)
        #expect(events.paddleContacts == 1)
        #expect(events.lifeLosses == 0)
        #expect(ball.velocity.y > 0)
        #expect(ball.velocity.x * side < 0)
        #expect(ball.position.x >= radius && ball.position.x <= CourtGeometry.width - radius)
        expectNear(ball.speed, 46)
    }

    @Test("Enlarged reach never catches outgoing balls", arguments: [-2.35, 2.35])
    func outgoingReach(offset: Double) {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10 + offset, y: 2.2),
                                      velocity: .init(x: 0, y: 26))
        #expect(advance(engine, seconds: 0.15).paddleContacts == 0)
    }

    @Test("Player aim tuning cannot change The Wall return direction")
    func bossAimIsIndependent() throws {
        var narrowPlayerTuning = GameTuning()
        narrowPlayerTuning.maximumOutgoingApparentAngle = 0.01
        let regular = activeEngine(boss: true, seed: 83)
        let narrow = activeEngine(boss: true, tuning: narrowPlayerTuning, seed: 83)
        for engine in [regular, narrow] {
            engine.setPlayerX(17)
            engine.state.boss = BossState(x: 5, movementTarget: 5, reactionRemaining: 1)
            engine.state.ball = BallState(position: .init(x: 5, y: 40.2),
                                          velocity: .init(x: 0, y: 26))
            #expect(advance(engine, seconds: 0.03).bossContacts == 1)
        }
        let normalBall = try #require(regular.state.ball)
        let narrowBall = try #require(narrow.state.ball)
        expectNear(normalBall.velocity.x, narrowBall.velocity.x)
        expectNear(normalBall.velocity.y, narrowBall.velocity.y)
        #expect(abs(atan2(normalBall.velocity.x, -normalBall.velocity.y)) > 0.01)
    }

    @Test("Seeded bounded imperfect positioning demonstrates tolerance rather than a perfect bot")
    func seededBalanceComparison() {
        struct Outcome: Equatable { var returns = 0; var misses = 0 }
        let samples = 512
        func run(old: Bool) -> Outcome {
            var generator = SeededGenerator(seed: 0xF012_61A3)
            var tuning = GameTuning()
            if old { tuning.playerHalfWidth = 2.475 }
            tuning.freeRecoveriesPerStage = 0 // Compare width, independently of the new recovery rule.
            var outcome = Outcome()
            for index in 0..<samples {
                // Identical incoming shots and independent bounded positioning error
                // for both configurations; no trajectory-following controller.
                let incomingX = 0.7 + generator.unit() * 18.6
                let positioningError = generator.signed() * 3.6
                let speed = 26 + generator.unit() * 20
                let engine = activeEngine(tuning: tuning, seed: UInt64(index))
                engine.setPlayerX(incomingX + positioningError)
                engine.state.ball = BallState(position: .init(x: incomingX, y: 3.6),
                                              velocity: .init(x: 0, y: -speed))
                let events = advance(engine, seconds: 0.2)
                #expect(events.paddleContacts + events.lifeLosses == 1)
                outcome.returns += events.paddleContacts
                outcome.misses += events.lifeLosses
            }
            return outcome
        }
        let old = run(old: true)
        let new = run(old: false)
        #expect(run(old: false) == new)
        #expect(new.returns > old.returns)
        #expect(new.misses > 0)
        #expect(new.returns + new.misses == samples)
        print("FORGIVENESS_BALANCE seed=0xF01261A3 samples=\(samples) old_returns=\(old.returns) old_misses=\(old.misses) new_returns=\(new.returns) new_misses=\(new.misses) old_success=\(Double(old.returns) / Double(samples)) new_success=\(Double(new.returns) / Double(samples))")
    }
}
