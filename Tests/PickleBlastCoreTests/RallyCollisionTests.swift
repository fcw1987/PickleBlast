import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Authoritative rally collisions")
struct RallyCollisionTests {
    @Test("Forehand and backhand animate anticipation, strike, recovery after actual contact", arguments: [-1.0, 1.0])
    func swingSequence(side: Double) {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10 + side, y: 7), velocity: .init(x: 0, y: -26))
        var animations: Set<PlayerAnimation> = []
        var events: [GameEvent] = []
        for _ in 0..<90 {
            events += engine.update(delta: 1.0 / 120)
            animations.insert(engine.state.playerAnimation)
        }
        let expected: [PlayerAnimation] = side < 0
            ? [.backhandAnticipation, .backhandSwing, .backhandContact, .backhandFollowThrough, .backhandRecovery, .ready]
            : [.forehandAnticipation, .forehandSwing, .forehandContact, .forehandFollowThrough, .forehandRecovery, .ready]
        for animation in expected { #expect(animations.contains(animation)) }
        #expect(events.paddleContacts == 1)
        #expect(events.contains { event in
            if case let .paddleContact(_, swing, _) = event { return swing == (side < 0 ? .backhand : .forehand) }
            return false
        })
    }

    @Test("Centered automatic contact returns upward without lateral drift")
    func centeredReturn() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 2.8), velocity: .init(x: 0, y: -26))
        let events = advance(engine, seconds: 0.04)
        let ball = try #require(engine.state.ball)
        #expect(ball.velocity.y > 0)
        expectNear(ball.velocity.x, 0)
        #expect(events.paddleContacts == 1)
        #expect(events.contains { if case .paddleContact(_, _, centered: true) = $0 { return true }; return false })
    }

    @Test("Edge contact controls left and right outgoing angles", arguments: [-1.0, 1.0])
    func edgeReturns(side: Double) throws {
        let engine = activeEngine()
        let x = 10 + side * engine.tuning.playerHalfWidth * 0.95
        engine.state.ball = BallState(position: .init(x: x, y: 2.8), velocity: .init(x: 0, y: -26))
        let events = advance(engine, seconds: 0.04)
        let ball = try #require(engine.state.ball)
        #expect(ball.velocity.x * side > 0)
        #expect(ball.velocity.y > 0)
        #expect(ReceivingTrajectory.apparentAngle(of: ball.velocity, at: ball.position,
            projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor) <= engine.tuning.maximumOutgoingApparentAngle + 0.000_001)
        #expect(abs(ball.velocity.x) > ball.speed * 0.35)
        #expect(events.paddleContacts == 1)
    }

    @Test("Glancing radius contact never creates near-horizontal travel")
    func angleClamp() throws {
        let engine = activeEngine()
        let x = 10 + engine.tuning.playerHalfWidth + engine.tuning.ballRadius * 0.8
        engine.state.ball = BallState(position: .init(x: x, y: 2.8), velocity: .init(x: 0, y: -46))
        let events = advance(engine, seconds: 0.03)
        let ball = try #require(engine.state.ball)
        #expect(events.paddleContacts == 1)
        #expect(ball.velocity.y > 0)
        #expect(ball.velocity.y / ball.speed >= engine.tuning.minimumVerticalFraction)
        #expect(ReceivingTrajectory.apparentAngle(of: ball.velocity, at: ball.position,
            projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor) <= engine.tuning.maximumOutgoingApparentAngle + 0.000_001)
    }

    @Test("A single collision produces exactly one contact across subsequent frames")
    func duplicateContactPrevention() {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 2.6), velocity: .init(x: 0, y: -46))
        let events = advance(engine, seconds: 0.25)
        #expect(events.paddleContacts == 1)
        #expect(engine.state.lives == 3)
    }

    @Test("Upward travel through the hitting plane never manufactures a hit")
    func outgoingDoesNotContact() {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 2.2), velocity: .init(x: 0, y: 26))
        #expect(advance(engine, seconds: 0.1).paddleContacts == 0)
    }

    @Test("Maximum-speed paddle crossing cannot tunnel")
    func maximumSpeedPlayerCollision() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 4), velocity: .init(x: 0, y: -46))
        let events = engine.update(delta: 0.1)
        #expect(events.paddleContacts == 1)
        #expect(try #require(engine.state.ball).velocity.y > 0)
        #expect(engine.state.lives == 3)
    }

    @Test("Side walls reflect with remaining-frame travel", arguments: [-1.0, 1.0])
    func sideWallReflection(side: Double) throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: side < 0 ? 0.5 : 19.5, y: 12), velocity: .init(x: side * 35, y: 8))
        let events = engine.update(delta: 0.1)
        let ball = try #require(engine.state.ball)
        #expect(ball.velocity.x * side < 0)
        #expect(ball.position.x > ball.radius && ball.position.x < 20 - ball.radius)
        #expect(ball.position.y > 12)
        #expect(events.contains(.wallContact))
    }

    @Test("Normal far baseline reflects instead of scoring")
    func farBoundaryReflection() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 43), velocity: .init(x: 0, y: 46))
        let events = engine.update(delta: 0.1)
        #expect(try #require(engine.state.ball).velocity.y < 0)
        #expect(engine.state.score == 0)
        #expect(!events.contains { if case .bossPoint = $0 { return true }; return false })
    }

    @Test("Net and kitchen lines remain visual and do not bounce the ball")
    func netHasNoCollision() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 21), velocity: .init(x: 0, y: 26))
        let events = engine.update(delta: 0.1)
        let ball = try #require(engine.state.ball)
        #expect(ball.position.y > 22)
        #expect(ball.velocity.y > 0)
        #expect(!events.contains(.wallContact))
    }

    @Test("Speed remains capped after paddle contact")
    func speedCap() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10.5, y: 3), velocity: .init(x: 0, y: -460))
        _ = advance(engine, seconds: 0.05)
        #expect(try #require(engine.state.ball).speed <= engine.tuning.maximumBallSpeed + 0.000_001)
    }

    @Test("An unaligned ball loses exactly one life and enters a ready state")
    func oneLifePerMiss() {
        let engine = activeEngine()
        engine.state.recoveriesRemaining = 0 // Charged miss after free allowances are used.
        engine.state.ball = BallState(position: .init(x: 18, y: 0.2), velocity: .init(x: 0, y: -46))
        let events = advance(engine, seconds: 0.8)
        #expect(events.lifeLosses == 1)
        #expect(engine.state.lives == 2)
        #expect(engine.state.phase == .ready)
        #expect(engine.state.ball == nil)
        #expect(events.paddleContacts == 0)
    }

    @Test("Miss remains possible despite anticipation animation")
    func anticipationDoesNotHit() {
        let engine = activeEngine()
        engine.state.recoveriesRemaining = 0
        engine.state.playerAnimation = .forehandAnticipation
        engine.state.ball = BallState(position: .init(x: 18, y: 3), velocity: .init(x: 0, y: -46))
        let events = advance(engine, seconds: 0.2)
        #expect(events.paddleContacts == 0)
        #expect(events.lifeLosses == 1)
    }

    @Test("One-hit targets award class scores and disappear once", arguments: [TargetKind.paddle, .cone])
    func singleHitTarget(kind: TargetKind) {
        var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0
        let engine = activeEngine(tuning: tuning)
        engine.state.targets = [target(id: 1, kind: kind), target(id: 2, kind: .paddle, x: 18, y: 40)]
        engine.state.ball = BallState(position: .init(x: 10, y: 27), velocity: .init(x: 0, y: 46))
        let events = advance(engine, seconds: 0.2)
        #expect(!engine.state.targets.contains { $0.id == 1 })
        #expect(engine.state.targets.count == 1)
        #expect(events.targetHits == 1)
        #expect(engine.state.score == (kind == .paddle ? 100 : 125))
        #expect(events.contains(.targetHit(id: 1, kind: kind, destroyed: true, score: kind == .paddle ? 100 : 125)))
    }

    @Test("Basket survives first strike, rebounds, shows damage, then dies on the second")
    func twoHitBasket() throws {
        var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0
        let engine = activeEngine(tuning: tuning)
        engine.state.targets = [target(id: 1, kind: .basket), target(id: 2, kind: .paddle, x: 18, y: 40)]
        engine.state.ball = BallState(position: .init(x: 10, y: 27), velocity: .init(x: 0, y: 46))
        let first = advance(engine, seconds: 0.1)
        let basket = try #require(engine.state.targets.first { $0.id == 1 })
        #expect(basket.health == 1)
        #expect(basket.isDamaged)
        #expect(try #require(engine.state.ball).velocity.y < 0)
        #expect(first.targetHits == 1)
        #expect(engine.state.score == 75)
        _ = advance(engine, seconds: 0.1)
        engine.state.ball = BallState(position: .init(x: 10, y: 27), velocity: .init(x: 0, y: 46))
        let second = advance(engine, seconds: 0.1)
        #expect(second.targetHits == 1)
        #expect(!engine.state.targets.contains { $0.id == 1 })
        // No intervening player return: second damaging strike earns ×2.
        #expect(engine.state.score == 75 + 175 * 2)
    }

    @Test("Maximum speed sweeps through small targets without tunneling")
    func maximumSpeedTargetCollision() {
        let engine = activeEngine()
        engine.state.targets = [TargetState(id: 1, kind: .paddle, position: .init(x: 10, y: 30), radius: 0.04), target(id: 2, kind: .paddle, x: 18, y: 40)]
        engine.state.ball = BallState(position: .init(x: 10, y: 28), velocity: .init(x: 0, y: 46), radius: 0.02)
        let events = engine.update(delta: 0.1)
        #expect(events.targetHits == 1)
        #expect(!engine.state.targets.contains { $0.id == 1 })
    }

    @Test("Near miss outside target radius neither scores nor changes direction")
    func targetNearMiss() throws {
        let engine = activeEngine()
        engine.state.targets = [target(id: 1, kind: .paddle)]
        engine.state.ball = BallState(position: .init(x: 11.51, y: 27), velocity: .init(x: 0, y: 46))
        let events = engine.update(delta: 0.1)
        #expect(events.targetHits == 0)
        #expect(engine.state.score == 0)
        #expect(try #require(engine.state.ball).velocity.y > 0)
    }
}
