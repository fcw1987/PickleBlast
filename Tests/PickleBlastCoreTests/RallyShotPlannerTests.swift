import Testing
@testable import PickleBlastCore

@Suite("Rally shot intent uses effective receiving placement")
struct RallyShotPlannerTests {
    @Test("Every candidate respects contact speed and the global cap", arguments: BossID.allCases)
    func speedAndProjection(id: BossID) throws {
        let tuning = GameTuning()
        let y = tuning.bossConfiguration(for: id).y
        let contact = BallState(position: Vector2(x: 11, y: y - tuning.ballRadius),
                                velocity: Vector2(x: 2, y: 30), radius: tuning.ballRadius)
        for variation in [0.1, 0.36, 0.6, 0.95] {
            let plan = RallyShotPlanner.choose(contact: contact, bossY: y, bossID: id,
                observedPlayerX: 10, previousLandingSide: 0,
                variation: variation, powered: false, tuning: tuning)
            #expect(plan.velocity.y < 0)
            #expect(plan.velocity.length <= contact.speed + 1e-10)
            #expect(plan.velocity.length <= tuning.maximumBallSpeed + 1e-10)
            let forecastBall = BallState(position: Vector2(x: contact.position.x,
                y: y - contact.radius - tuning.collisionEpsilon),
                velocity: plan.velocity, radius: contact.radius)
            let arrival = try #require(RallyBallProjection.arrival(of: forecastBall,
                atY: tuning.playerY + contact.radius, tuning: tuning,
                speedGrowth: tuning.rallyOpponentConfiguration(for: id).speedGrowthPerSecond))
            #expect(abs(arrival.position.x - plan.landingX) < 1e-10)
            #expect(plan.laneSide == (plan.landingX < 8 ? -1 : (plan.landingX > 12 ? 1 : 0)))
        }
    }

    @Test("Observed player position and the previous lane change legal placement")
    func placementRespondsToObservedState() {
        let tuning = GameTuning()
        let contact = BallState(position: Vector2(x: 10, y: tuning.boss.y - tuning.ballRadius),
                                velocity: Vector2(x: 0, y: 28), radius: tuning.ballRadius)
        let left = RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 6, previousLandingSide: 0,
            variation: 0.1, powered: false, tuning: tuning)
        let right = RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 14, previousLandingSide: 0,
            variation: 0.1, powered: false, tuning: tuning)
        #expect(left.purpose == .control && right.purpose == .control)
        #expect(left.landingX + 4 < right.landingX)
        let changed = RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 10, previousLandingSide: 1,
            variation: 0.65, powered: false, tuning: tuning)
        #expect(changed.landingX < 8)
    }

    @Test("Banger drive is a bounded contact-speed increase rather than a midflight change")
    func poweredContact() {
        let tuning = GameTuning()
        let contact = BallState(position: Vector2(x: 7, y: tuning.banger.y - tuning.ballRadius),
                                velocity: Vector2(x: 0, y: 26), radius: tuning.ballRadius)
        let ordinary = RallyShotPlanner.choose(contact: contact, bossY: tuning.banger.y,
            bossID: .banger, observedPlayerX: 10, previousLandingSide: -1,
            variation: 0.2, powered: false, tuning: tuning)
        let powered = RallyShotPlanner.choose(contact: contact, bossY: tuning.banger.y,
            bossID: .banger, observedPlayerX: 10, previousLandingSide: -1,
            variation: 0.2, powered: true, tuning: tuning)
        #expect(ordinary.velocity.length <= contact.speed + 1e-10)
        #expect(powered.velocity.length > ordinary.velocity.length)
        #expect(powered.velocity.length <= min(tuning.maximumBallSpeed,
            contact.speed * tuning.rallyBanger.powerSpeedMultiplier) + 1e-10)
        #expect(powered.purpose == .attack)
    }

    @Test("A slower change of pace does not compound, and an unbalanced boss controls")
    func paceRecoveryAndBalance() {
        let tuning = GameTuning()
        let contact = BallState(position: Vector2(x: 10, y: tuning.boss.y - tuning.ballRadius),
                                velocity: Vector2(x: 0, y: tuning.initialBallSpeed), radius: tuning.ballRadius)
        let slow = RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 10, previousLandingSide: 0,
            variation: 0.48, powered: false, tuning: tuning)
        #expect(slow.purpose == .changeOfPace)
        #expect(slow.velocity.length < tuning.initialBallSpeed)
        let followingContact = BallState(position: contact.position,
            velocity: Vector2(x: 0, y: slow.velocity.length), radius: contact.radius)
        let recovered = RallyShotPlanner.choose(contact: followingContact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 10, previousLandingSide: slow.laneSide,
            variation: 0.1, powered: false, tuning: tuning)
        #expect(recovered.purpose == .control)
        #expect(abs(recovered.velocity.length - tuning.initialBallSpeed) < 1e-10)
        let unbalanced = RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
            bossID: .wall, observedPlayerX: 10, previousLandingSide: 0,
            variation: 0.99, powered: true, balanced: false, tuning: tuning)
        #expect(unbalanced.purpose == .control)
        #expect(unbalanced.velocity.length <= tuning.initialBallSpeed + 1e-10)
    }

    @Test("Only purposeful shots use bounded delayed player movement")
    func delayedMomentumIsCausalAndSmall() {
        let tuning = GameTuning()
        let contact = BallState(position: Vector2(x: 10, y: tuning.boss.y - tuning.ballRadius),
                                velocity: Vector2(x: 0, y: 28), radius: tuning.ballRadius)
        func planned(_ velocity: Double, variation: Double) -> RallyShotPlan {
            RallyShotPlanner.choose(contact: contact, bossY: tuning.boss.y,
                bossID: .wall, observedPlayerX: 10,
                observedPlayerVelocity: velocity, previousLandingSide: 1,
                variation: variation, powered: false, tuning: tuning)
        }
        let movingRight = planned(10, variation: 0.7)
        let still = planned(0, variation: 0.7)
        let movingLeft = planned(-10, variation: 0.7)
        #expect(movingRight.purpose == .placement)
        #expect(movingRight.landingX < still.landingX)
        #expect(still.landingX < movingLeft.landingX)
        #expect(movingLeft.landingX - movingRight.landingX <= 3.0,
                "Observed motion shapes a lane; contact placement remains the main aim")
        let controlRight = planned(10, variation: 0.1)
        let controlLeft = planned(-10, variation: 0.1)
        #expect(controlRight.purpose == .control)
        #expect(controlRight.velocity == controlLeft.velocity,
                "A neutral return ignores observed player movement")
    }
}
