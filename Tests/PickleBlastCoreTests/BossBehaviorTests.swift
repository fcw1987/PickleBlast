import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Boss Rally core behavior")
struct BossBehaviorTests {
    @Test("Each boss starts as a fresh direct match", arguments: BossID.allCases)
    func directStart(id: BossID) {
        let engine = GameEngine(mode: .bossRally(id), seed: 7)
        #expect(engine.state.mode == .bossRally(id))
        #expect(engine.state.stage == .boss)
        #expect(engine.state.targets.isEmpty)
        #expect(engine.state.boss?.id == id)
        #expect(engine.state.playerRallyPoints == 0)
        #expect(engine.state.opponentRallyPoints == 0)
        #expect(engine.state.recoveriesRemaining == 0)
        #expect(engine.state.phase == .ready)
        engine.reset()
        #expect(engine.state.mode == .bossRally(id))
        #expect(engine.state.boss?.id == id)
    }

    @Test("Matches start without free saves and the third unrescued miss ends the match",
          arguments: BossID.allCases)
    func firstToThreeAndSaves(id: BossID) {
        let engine = playingBoss(id)
        for point in 1...3 {
            engine.state.phase = .playing
            engine.state.ball = BallState(position: .init(x: 18, y: -0.1),
                                          velocity: .init(x: 0, y: -26))
            let events = advance(engine, seconds: 0.1)
            #expect(events.lifeLosses == 0)
            #expect(engine.state.lives == 3)
            #expect(events.contains(.opponentPoint(points: point)))
            #expect(engine.state.opponentRallyPoints == point)
            #expect(engine.state.recoveriesRemaining == 0)
            #expect(engine.state.phase == (point == 3 ? .results : .ready))
            #expect(engine.state.playerRallyPoints == 0)
        }
        #expect(!engine.state.won)
        #expect(advance(engine, seconds: 1).isEmpty)
    }

    @Test("A genuine boss miss scores once and point transitions preserve match state")
    func playerPointAndRallyReset() {
        let engine = playingBoss(.wall)
        engine.state.currentRallyReturns = 5
        engine.state.longestRallyReturns = 7
        engine.state.recoveriesRemaining = 1
        engine.state.boss?.x = 2
        engine.state.ball = BallState(position: .init(x: 18, y: 43.9),
                                      velocity: .init(x: 0, y: 26))
        let events = advance(engine, seconds: 0.1)
        #expect(events.contains(.bossPoint(points: 1)))
        #expect(engine.state.playerRallyPoints == 1)
        #expect(engine.state.opponentRallyPoints == 0)
        #expect(engine.state.recoveriesRemaining == 1)
        #expect(engine.state.currentRallyReturns == 0)
        #expect(engine.state.longestRallyReturns == 7)
        #expect(engine.state.phase == .ready)
        #expect(advance(engine, seconds: 0.2).bossPoints == 0)
    }

    @Test("Delayed observations cannot steer before the delay and finite motor catches up")
    func delayedFiniteSteering() {
        let engine = playingBoss(.wall)
        let policy = engine.tuning.rallyOpponentConfiguration(for: .wall)
        engine.state.boss = BossState(id: .wall, x: 10, movementTarget: 10)
        engine.state.ball = BallState(position: .init(x: 14, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        _ = advance(engine, seconds: policy.observationDelay * 0.70)
        #expect(engine.state.boss?.x == 10)
        #expect(engine.state.boss?.movementTarget == 10)
        var priorX = engine.state.boss?.x ?? 10
        var priorVelocity = engine.state.boss?.lateralVelocity ?? 0
        for _ in 0..<80 {
            _ = engine.update(delta: engine.tuning.fixedStep)
            guard let boss = engine.state.boss else { break }
            #expect(abs(boss.x - priorX) <= policy.maximumLateralSpeed * engine.tuning.fixedStep + 1e-8)
            #expect(abs(boss.lateralVelocity - priorVelocity)
                    <= max(policy.lateralAcceleration, policy.lateralBraking) * engine.tuning.fixedStep + 1e-8)
            #expect(boss.x >= engine.activeBossConfiguration.halfWidth)
            #expect(boss.x <= CourtGeometry.width - engine.activeBossConfiguration.halfWidth)
            priorX = boss.x; priorVelocity = boss.lateralVelocity
        }
        #expect((engine.state.boss?.lastObservedTime ?? 0) > 0)
        #expect((engine.state.boss?.x ?? 10) > 10.5)
    }

    @Test("Opponent reversal brakes through zero without a snap")
    func finiteReversal() {
        let engine = playingBoss(.wall)
        let policy = engine.tuning.rallyWall
        engine.state.boss = BossState(id: .wall, x: 10, movementTarget: 3,
                                      lateralVelocity: 5)
        engine.state.ball = BallState(position: .init(x: 3, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        _ = engine.update(delta: engine.tuning.fixedStep)
        let first = engine.state.boss?.lateralVelocity ?? 0
        #expect(first > 0)
        #expect(5 - first <= policy.lateralAcceleration * engine.tuning.fixedStep + 1e-8)
        _ = advance(engine, seconds: 0.45)
        #expect((engine.state.boss?.lateralVelocity ?? 0) < 0)
        #expect((engine.state.boss?.x ?? 0) >= engine.activeBossConfiguration.halfWidth)
    }

    @Test("Projection is pure and tracks authoritative side reflection and speed growth")
    func reflectedProjection() throws {
        var tuning = GameTuning()
        tuning.rallyWall.maximumLateralSpeed = 0
        let engine = GameEngine(mode: .bossRally(.wall), tuning: tuning, seed: 99)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .wall, x: 1.75, movementTarget: 1.75)
        let initial = BallState(position: .init(x: 18, y: 20),
                                velocity: .init(x: 20, y: 26))
        engine.state.ball = initial
        let before = engine.state
        let plane = engine.activeBossConfiguration.y - initial.radius
        let projected = try #require(RallyBallProjection.arrival(of: initial, atY: plane,
            tuning: tuning, speedGrowth: tuning.rallyWall.speedGrowthPerSecond))
        #expect(engine.state == before)
        #expect(projected.sideReflections >= 1)
        var previous = initial.position
        var crossingX: Double?
        for _ in 0..<280 {
            _ = engine.update(delta: tuning.fixedStep)
            guard let ball = engine.state.ball else { break }
            if previous.y < plane, ball.position.y >= plane {
                let fraction = (plane - previous.y) / (ball.position.y - previous.y)
                crossingX = previous.x + (ball.position.x - previous.x) * fraction
                break
            }
            previous = ball.position
        }
        let actual = try #require(crossingX)
        #expect(abs(actual - projected.position.x) < 0.25)
    }

    @Test("Projected low side-bank return includes the authoritative outgoing angle correction")
    func lowSideBankProjection() throws {
        var tuning = GameTuning()
        tuning.rallyWall.maximumLateralSpeed = 0
        let engine = GameEngine(mode: .bossRally(.wall), tuning: tuning, seed: 99)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .wall, x: 1.75, movementTarget: 1.75)
        let initial = BallState(position: .init(x: 18, y: 4),
                                velocity: .init(x: 20, y: 26))
        engine.state.ball = initial
        let plane = engine.activeBossConfiguration.y - initial.radius
        let projection = try #require(RallyBallProjection.arrival(of: initial,
            atY: plane, tuning: tuning, speedGrowth: tuning.rallyWall.speedGrowthPerSecond))
        #expect(projection.sideReflections >= 1)
        var previous = initial.position
        var actualX: Double?
        for _ in 0..<320 {
            _ = engine.update(delta: tuning.fixedStep)
            guard let ball = engine.state.ball else { break }
            if previous.y < plane, ball.position.y >= plane {
                let fraction = (plane - previous.y) / (ball.position.y - previous.y)
                actualX = previous.x + (ball.position.x - previous.x) * fraction
                break
            }
            previous = ball.position
        }
        #expect(abs(try #require(actualX) - projection.position.x) < 0.25)
    }

    @Test("Banger telegraphs a real drive and keeps moving through brief recovery")
    func bangerDriveAndActiveRecovery() throws {
        let engine = playingBoss(.banger)
        engine.state.boss = BossState(id: .banger, x: 10, movementTarget: 10,
                                      returnCount: 1)
        engine.state.ball = BallState(position: .init(x: 10, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        var warning: Double?
        var contact: Double?
        for _ in 0..<220 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            if events.contains(.bossPowerTelegraph) { warning = engine.state.simulationTime }
            if events.contains(where: { if case .bossPowerContact = $0 { return true }; return false }) {
                contact = engine.state.simulationTime; break
            }
        }
        let warningTime = try #require(warning)
        let contactTime = try #require(contact)
        #expect(contactTime - warningTime + 1e-8
                >= engine.tuning.rallyBanger.powerLeadTime)
        #expect(engine.state.boss?.specialPhase == .powerRecovery)
        #expect((engine.state.ball?.speed ?? 0) <= engine.tuning.maximumBallSpeed + 1e-8)
        let xBefore = try #require(engine.state.boss).x
        engine.state.ball = BallState(position: .init(x: 13, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        _ = advance(engine, seconds: 0.32)
        let recovering = try #require(engine.state.boss)
        #expect(recovering.x > xBefore)
        #expect(recovering.x - xBefore <= engine.tuning.rallyBanger.maximumLateralSpeed * 0.32 + 1e-8)
    }

    @Test("Banger's real hit surface remains active throughout power recovery")
    func bangerCanReturnDuringRecovery() {
        let engine = playingBoss(.banger)
        engine.state.boss = BossState(id: .banger, x: 10, movementTarget: 10,
                                      specialPhase: .powerRecovery, specialRemaining: 0.45)
        engine.state.ball = BallState(position: .init(x: 11.5, y: 33),
                                      velocity: .init(x: 0, y: 26))
        let events = advance(engine, seconds: 0.35)
        #expect(events.bossContacts == 1)
        #expect(events.bossPoints == 0)
        #expect(engine.state.boss?.returnCount == 1)
    }

    @Test("A Banger warning alone never scores or creates a powered contact")
    func warningRequiresContact() {
        let engine = playingBoss(.banger)
        engine.state.boss = BossState(id: .banger, x: 18, movementTarget: 18,
                                      returnCount: 1)
        engine.state.ball = BallState(position: .init(x: 2, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        let events = advance(engine, seconds: 1.2)
        #expect(events.bossContacts == 0)
        #expect(!events.contains { if case .bossPowerContact = $0 { return true }; return false })
        #expect(events.bossPoints == 1)
    }

    @Test("Pause cancels an unspent drive reservation; resume needs a fresh visible warning")
    func pauseCancelsPowerWindup() throws {
        let engine = playingBoss(.banger)
        engine.state.boss = BossState(id: .banger, x: 10, movementTarget: 10,
                                      returnCount: 1)
        engine.state.ball = BallState(position: .init(x: 10, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        var warned = false
        for _ in 0..<100 {
            if engine.update(delta: engine.tuning.fixedStep).contains(.bossPowerTelegraph) {
                warned = true; break
            }
        }
        #expect(warned)
        #expect(engine.state.boss?.specialPhase == .powerWindup)
        engine.pause()
        #expect(engine.state.boss?.specialPhase == .idle)
        let paused = engine.state
        #expect(engine.update(delta: 10).isEmpty)
        #expect(engine.state == paused)
        engine.resume()
        var freshWarning: Double?
        var poweredContact: Double?
        for _ in 0..<400 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            if events.contains(.bossPowerTelegraph) {
                freshWarning = engine.state.simulationTime
            }
            if events.contains(where: { if case .bossPowerContact = $0 { return true }; return false }) {
                poweredContact = engine.state.simulationTime
                break
            }
            if events.bossContacts > 0 || events.bossPoints > 0 { break }
        }
        if let poweredContact {
            let fresh = try #require(freshWarning)
            #expect(poweredContact - fresh + 1e-8 >= engine.tuning.rallyBanger.powerLeadTime)
        }
    }

    @Test("Poacher commits from completed lane history before seeing the next shot, then corrects late")
    func poacherHistoryCommitment() throws {
        let engine = playingBoss(.poacher)
        func forcePlayerShot(paddleX: Double) -> [GameEvent] {
            engine.state.phase = .playing
            engine.state.ball = BallState(position: .init(x: 10, y: 2.7),
                                          velocity: .init(x: 0, y: -26))
            engine.setPlayerX(paddleX)
            var result: [GameEvent] = []
            for _ in 0..<260 {
                let events = engine.update(delta: engine.tuning.fixedStep)
                result.append(contentsOf: events)
                if events.bossContacts > 0 || events.bossPoints > 0 { break }
            }
            return result
        }
        let first = forcePlayerShot(paddleX: 8.3)
        #expect(first.bossContacts == 1)
        #expect(!first.contains { if case .bossPoachCommitment = $0 { return true }; return false })
        let second = forcePlayerShot(paddleX: 8.3)
        #expect(second.bossContacts == 1)
        #expect(second.contains { if case .bossPoachCommitment(side: .right, _) = $0 {
            return true
        }; return false })
        let committed = try #require(engine.state.boss)
        #expect(committed.specialPhase == .poachCommitment)
        #expect(committed.committedSide == .right)
        #expect((committed.committedTargetX ?? committed.x) - committed.x
                <= engine.tuning.rallyPoacher.poachCommitmentOffset + 1e-8)
        let before = committed.x
        // The next shot is chosen only after the commitment already exists.
        engine.state.ball = BallState(position: .init(x: 10, y: 2.7),
                                      velocity: .init(x: 0, y: -26))
        engine.setPlayerX(11.7)
        let early = advance(engine, seconds: engine.tuning.rallyPoacher.observationDelay * 0.70)
        #expect(!early.contains(.bossPoachRecovery))
        #expect((engine.state.boss?.x ?? before) >= before - 1e-8)
        let later = advance(engine, seconds: 0.40)
        #expect(later.contains(.bossPoachRecovery))
        let corrected = try #require(engine.state.boss)
        #expect(corrected.x >= engine.activeBossConfiguration.halfWidth)
        #expect(corrected.x <= CourtGeometry.width - engine.activeBossConfiguration.halfWidth)
    }

    @Test("Poacher remembers a completed winning lane across a point transition")
    func poacherRemembersWinningLane() throws {
        var tuning = GameTuning()
        tuning.rallyPoacher.maximumLateralSpeed = 0
        let engine = GameEngine(mode: .bossRally(.poacher), tuning: tuning, seed: 23)
        engine.state.phase = .playing
        let contactX = 10.0
        let paddleX = 8.3
        let contactY = tuning.playerY + tuning.ballRadius
        let outgoing = ReceivingTrajectory.outgoing(
            apparentAngle: (contactX - paddleX) / tuning.playerHalfWidth
                * tuning.maximumOutgoingApparentAngle,
            at: .init(x: contactX, y: contactY), speed: tuning.initialBallSpeed,
            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
        let forecast = try #require(RallyBallProjection.arrival(of:
            BallState(position: .init(x: contactX, y: contactY + tuning.collisionEpsilon),
                      velocity: outgoing, radius: tuning.ballRadius),
            atY: tuning.poacher.y - tuning.ballRadius, tuning: tuning,
            speedGrowth: tuning.rallyPoacher.speedGrowthPerSecond))
        #expect(forecast.position.x > CourtGeometry.centerX + 1.2)
        func shoot() -> [GameEvent] {
            engine.state.phase = .playing
            engine.state.ball = BallState(position: .init(x: contactX, y: contactY + 0.2),
                                          velocity: .init(x: 0, y: -tuning.initialBallSpeed))
            engine.setPlayerX(paddleX)
            var events: [GameEvent] = []
            for _ in 0..<280 {
                let tick = engine.update(delta: tuning.fixedStep)
                events.append(contentsOf: tick)
                if tick.bossPoints > 0 || tick.bossContacts > 0 { break }
            }
            return events
        }
        engine.state.boss?.x = tuning.poacher.halfWidth
        engine.state.boss?.movementTarget = tuning.poacher.halfWidth
        #expect(shoot().bossPoints == 1)
        #expect(engine.state.playerRallyPoints == 1)
        engine.state.boss?.x = forecast.position.x
        engine.state.boss?.movementTarget = forecast.position.x
        let second = shoot()
        #expect(second.bossContacts == 1)
        #expect(second.contains { if case .bossPoachCommitment(side: .right, _) = $0 {
            return true
        }; return false })
    }

    @Test("Same seed and public controls replay a bounded match segment exactly",
          arguments: BossID.allCases, [1, 42, 83])
    func seededPublicReplay(id: BossID, seed: Int) {
        let first = GameEngine(mode: .bossRally(id), seed: UInt64(seed))
        let second = GameEngine(mode: .bossRally(id), seed: UInt64(seed))
        var contacts = 0
        for frame in 0..<4_000 {
            let x = 10 + sin(Double(frame) * 0.015) * 2
            first.setPlayerX(x)
            second.setPlayerX(x)
            let a = first.update(delta: first.tuning.fixedStep)
            let b = second.update(delta: second.tuning.fixedStep)
            #expect(a == b)
            if frame.isMultiple(of: 60) { #expect(first.state == second.state) }
            contacts += a.bossContacts + a.paddleContacts
            #expect(first.state.playerRallyPoints <= 3)
            #expect(first.state.opponentRallyPoints <= 3)
            #expect((first.state.ball?.speed ?? 0) <= first.tuning.maximumBallSpeed + 1e-8)
            if first.state.phase == .results { break }
        }
        #expect(first.state == second.state)
        #expect(contacts > 0)
        #expect(first.state.targets.isEmpty)
    }

    private func playingBoss(_ id: BossID) -> GameEngine {
        let engine = GameEngine(mode: .bossRally(id), seed: 83)
        engine.state.phase = .playing
        engine.state.phaseTimeRemaining = 0
        return engine
    }
}
