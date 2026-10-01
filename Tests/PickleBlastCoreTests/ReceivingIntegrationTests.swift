import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Swept receiving guidance and bounded stall recovery")
struct ReceivingIntegrationTests {
    private func guidedAngle(_ ball: BallState, _ tuning: GameTuning) -> Double {
        ReceivingTrajectory.apparentAngle(of: ball.velocity, at: ball.position,
                                         projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
    }

    @Test("Swept boundary correction preserves contact point, remaining travel and speed")
    func sweptEntry() throws {
        let engine = activeEngine()
        let tuning = engine.tuning
        let v = Vector2(x: sqrt(46 * 46 - 20 * 20), y: -20)
        let start = Vector2(x: 10, y: tuning.receivingBoundaryY + 0.01)
        engine.state.ball = BallState(position: start, velocity: v)
        let contactTime = (tuning.receivingBoundaryY - start.y) / v.y
        let entry = start + v * contactTime
        let corrected = ReceivingTrajectory.constrained(v, at: entry,
            maximumApparentAngle: tuning.maximumIncomingApparentAngle,
            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
        let expected = entry + corrected * (tuning.fixedStep - contactTime)
        let events = engine.update(delta: tuning.fixedStep)
        let ball = try #require(engine.state.ball)
        #expect(events.isEmpty)
        expectNear(ball.position.x, expected.x)
        expectNear(ball.position.y, expected.y)
        expectNear(ball.speed, 46)
        #expect(guidedAngle(ball, tuning) <= tuning.maximumIncomingApparentAngle + 1e-10)
        // The actual trajectory stays straight after its one entry correction.
        let before = ball
        _ = advance(engine, seconds: 12 * tuning.fixedStep)
        let after = try #require(engine.state.ball)
        #expect(after.velocity == before.velocity)
        expectNear(after.position.x, before.position.x + before.velocity.x * 12 * tuning.fixedStep)
        expectNear(after.position.y, before.position.y + before.velocity.y * 12 * tuning.fixedStep)
    }

    @Test("Target corner, far wall, upper side wall and boss velocities all receive entry guidance")
    func velocitySources() throws {
        for source in 0..<4 {
            var tuning = GameTuning()
            tuning.cleanupTargetThreshold = 0
            tuning.boss.accelerationPerSecond = 0
            let engine = activeEngine(boss: source == 3, tuning: tuning, seed: 83)
            switch source {
            case 0:
                let normal = Vector2(x: 0.5, y: -sqrt(0.75))
                let center = Vector2(x: 10, y: 24)
                engine.state.targets = [TargetState(id: 1, kind: .paddle, position: center, radius: 0.5),
                                        target(id: 2, kind: .paddle, x: 1, y: 42)]
                engine.state.ball = BallState(position: center + normal * 0.82, velocity: .init(x: 0, y: 26))
            case 1:
                engine.state.ball = BallState(position: .init(x: 10, y: 43.69),
                    velocity: .init(x: sqrt(26 * 26 - 6.24 * 6.24), y: 6.24))
            case 2:
                engine.state.ball = BallState(position: .init(x: 19.69, y: 24),
                    velocity: .init(x: sqrt(26 * 26 - 6.24 * 6.24), y: -6.24))
            default:
                engine.setPlayerX(17)
                engine.state.boss = BossState(x: 5, movementTarget: 5, reactionRemaining: 1)
                engine.state.ball = BallState(position: .init(x: 5, y: 40.2), velocity: .init(x: 0, y: 26))
            }
            var events: [GameEvent] = []
            var entered = false
            for _ in 0..<1_200 {
                events += engine.update(delta: tuning.fixedStep)
                let ball = try #require(engine.state.ball)
                if ball.position.y <= tuning.receivingBoundaryY, ball.velocity.y < 0 {
                    #expect(guidedAngle(ball, tuning) <= tuning.maximumIncomingApparentAngle + 1e-10)
                    expectNear(ball.speed, 26)
                    entered = true
                    break
                }
            }
            #expect(entered)
            if source == 0 { #expect(events.targetHits == 1) }
            if source == 1 || source == 2 { #expect(events.contains(.wallContact)) }
            if source == 3 { #expect(events.bossContacts == 1) }
        }
    }

    @Test("Receiving side reflections respect both directions without teleporting or duplicate feedback")
    func receivingSideWalls() throws {
        for incoming in [true, false] {
            for side in [-1.0, 1.0] {
                let engine = activeEngine()
                let v = Vector2(x: side * 25, y: (incoming ? -1 : 1) * sqrt(26 * 26 - 25 * 25))
                engine.state.ball = BallState(position: .init(x: side < 0 ? 0.31 : 19.69, y: 12), velocity: v)
                let start = engine.state.ball!.position
                let events = engine.update(delta: engine.tuning.fixedStep)
                let ball = try #require(engine.state.ball)
                #expect(events.filter { $0 == .wallContact }.count == 1)
                #expect(events.paddleContacts == 0 && events.lifeLosses == 0)
                #expect(ball.velocity.x * side < 0)
                #expect((ball.position - start).length <= 26 * engine.tuning.fixedStep + 2e-5)
                expectNear(ball.speed, 26)
                let cap = incoming ? engine.tuning.maximumIncomingApparentAngle : engine.tuning.maximumOutgoingApparentAngle
                #expect(guidedAngle(ball, engine.tuning) <= cap + 1e-10)
            }
        }
    }

    @Test("Upper field shallow ricochets and repeated legitimate target contacts remain unrestricted")
    func backfieldPreserved() throws {
        var tuning = GameTuning()
        tuning.cleanupTargetThreshold = 0
        tuning.stallNoProgressDuration = 0.10 // Exercise the clock using frequent legitimate damage.
        let engine = activeEngine(tuning: tuning)
        let v = Vector2(x: sqrt(26 * 26 - 6.24 * 6.24), y: 6.24)
        engine.state.ball = BallState(position: .init(x: 5, y: 30), velocity: v)
        _ = advance(engine, seconds: 0.05)
        let unchanged = try #require(engine.state.ball)
        #expect(unchanged.velocity == v)
        #expect(guidedAngle(unchanged, tuning) > tuning.maximumOutgoingApparentAngle)
        // A durable pair sustains repeated shallow side contacts wholly above
        // the receiving area. The long-lived target health is a test fixture.
        let pair = activeEngine(tuning: tuning)
        pair.state.targets = [
            TargetState(id: 1, kind: .paddle, position: .init(x: 9, y: 30), radius: 0.55, health: 1000),
            TargetState(id: 2, kind: .paddle, position: .init(x: 11, y: 30), radius: 0.55, health: 1000)
        ]
        pair.state.ball = BallState(position: .init(x: 10, y: 30), velocity: .init(x: 26, y: 0))
        let events = advance(pair, seconds: 0.05)
        #expect(events.targetHits >= 2)
        #expect(pair.state.targetChain >= 2)
    }


    @Test("Legitimate damage resets the no-progress clock instead of ending active chains")
    func damageRestartsStallClock() throws {
        var tuning = GameTuning()
        tuning.cleanupTargetThreshold = 0
        tuning.stallNoProgressDuration = 0.1
        let engine = activeEngine(tuning: tuning)
        let v = Vector2(x: sqrt(26 * 26 - 6.24 * 6.24), y: 6.24)
        // Repeated independent contact fixtures isolate clock accounting. These
        // are not a claimed playable run or a balance-time measurement.
        for index in 0..<20 {
            engine.state.ball = BallState(position: .init(x: 5, y: 30), velocity: v)
            _ = advance(engine, seconds: 0.05)
            let before = try #require(engine.state.ball)
            expectNear(before.velocity.y, v.y)
            engine.state.targets = [
                TargetState(id: index, kind: .paddle, position: .init(x: 10, y: 35), radius: 0.5),
                target(id: 1000, kind: .paddle, x: 1, y: 42)
            ]
            engine.state.ball = BallState(position: .init(x: 10, y: 34.18), velocity: .init(x: 0, y: 26))
            let events = engine.update(delta: tuning.fixedStep)
            #expect(events.targetHits == 1)
        }
        #expect(engine.state.targetChain == 20)
        #expect(engine.state.simulationTime > tuning.stallNoProgressDuration * 10)
    }

    @Test("Eight seconds of no-progress shallow travel gets one speed-preserving escape")
    func stallTimeout() throws {
        let engine = activeEngine()
        expectNear(engine.tuning.stallNoProgressDuration, 8)
        let v = Vector2(x: sqrt(1 - 0.24 * 0.24), y: 0.24)
        engine.state.ball = BallState(position: .init(x: 5, y: 26), velocity: v)
        _ = advance(engine, seconds: 7.9)
        let before = try #require(engine.state.ball)
        expectNear(before.velocity.y, 0.24)
        _ = advance(engine, seconds: 0.2)
        let after = try #require(engine.state.ball)
        expectNear(after.speed, 1)
        expectNear(after.velocity.y, 0.45)
        #expect(after.position.y > before.position.y)
        // Direction remains stable rather than recurring steering every tick.
        _ = advance(engine, seconds: 0.2)
        #expect(engine.state.ball?.velocity == after.velocity)
    }
}
