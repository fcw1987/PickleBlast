import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Realized Boss Rally abilities")
struct RealizedBossAbilityTests {
    @Test("Prepared drive survives the full speed and receiving pipeline on a matched route")
    func realizedDrive() throws {
        let engine = incomingBanger(speed: 26)
        var prepared: (UInt64, UInt64)?
        var powerEvents = 0
        for _ in 0..<240 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            for event in events {
                if case .rallyShotPrepared(let rally, let shot, .power) = event { prepared = (rally, shot) }
                if case .bossPowerContact = event { powerEvents += 1 }
            }
            if engine.state.rallyShot?.kind == .power { break }
        }
        let shot = try #require(engine.state.rallyShot)
        let ball = try #require(engine.state.ball)
        #expect(shot.kind == .power)
        #expect(powerEvents == 1)
        #expect(prepared?.0 == shot.rallyID && prepared?.1 == shot.shotID)
        let ordinarySpeed = RallyShotPlanner.comparableOrdinarySpeed(sourceSpeed: 26, bossID: .banger, tuning: engine.tuning)
        let normal = BallState(position: ball.position, velocity: ball.velocity * (ordinarySpeed / ball.speed), radius: ball.radius)
        let powerArrival = try #require(RallyBallProjection.arrival(of: ball,
            atY: engine.tuning.playerY + ball.radius, tuning: engine.tuning,
            speedGrowth: engine.tuning.rallyBanger.speedGrowthPerSecond))
        let normalArrival = try #require(RallyBallProjection.arrival(of: normal,
            atY: engine.tuning.playerY + ball.radius, tuning: engine.tuning,
            speedGrowth: engine.tuning.rallyBanger.speedGrowthPerSecond))
        #expect(abs(powerArrival.position.x - normalArrival.position.x) < 0.02)
        #expect(powerArrival.time < normalArrival.time * 0.76)
        #expect(powerArrival.time >= engine.tuning.rallyBanger.minimumPowerResponseTime - engine.tuning.fixedStep)
        #expect(powerArrival.velocity.length > normalArrival.velocity.length * 1.34)
        engine.movePlayer(crownDelta: powerArrival.position.x - engine.state.playerX)
        var contactCount = 0
        for _ in 0..<240 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            contactCount += events.filter { if case .paddleContact = $0 { return true }; return false }.count
            if contactCount > 0 { break }
        }
        #expect(contactCount == 1)
        #expect(engine.state.rallyShot?.kind == .normal)
        #expect((engine.state.ball?.speed ?? 0) > normalArrival.velocity.length * 1.34)
    }

    @Test("Saturated incoming pace restores normal headroom and never stacks power",
          arguments: [30.0, 40.0, 46.0])
    func lateRallyHeadroom(speed: Double) throws {
        let tuning = GameTuning()
        let contact = BallState(position: .init(x: 10, y: tuning.banger.y - tuning.ballRadius), velocity: .init(x: 0, y: speed))
        let normal = RallyShotPlanner.choose(contact: contact, bossY: tuning.banger.y,
            bossID: .banger, observedPlayerX: 10, previousLandingSide: 1,
            variation: 0.1, powered: false, tuning: tuning)
        let drive = RallyShotPlanner.choose(contact: contact, bossY: tuning.banger.y,
            bossID: .banger, observedPlayerX: 10, previousLandingSide: 1,
            variation: 0.1, powered: true, tuning: tuning)
        #expect(normal.velocity.length <= 30 + 1e-8)
        #expect(drive.velocity.length >= normal.velocity.length * 1.35)
        #expect(drive.velocity.length <= tuning.maximumBallSpeed + 1e-8)
        let arrival = try #require(RallyBallProjection.arrival(of: BallState(position: contact.position, velocity: drive.velocity),
            atY: tuning.playerY + tuning.ballRadius, tuning: tuning, speedGrowth: tuning.rallyBanger.speedGrowthPerSecond))
        #expect(arrival.time >= tuning.rallyBanger.minimumPowerResponseTime)
        let recovered = RallyShotPlanner.choose(contact: BallState(position: contact.position, velocity: drive.velocity),
            bossY: tuning.banger.y, bossID: .banger, observedPlayerX: 10,
            previousLandingSide: 1, variation: 0.1, powered: false, tuning: tuning)
        #expect(recovered.velocity.length <= 30 + 1e-8)
    }

    @Test("A saturated full flight can prepare a real bounded drive before the net")
    func fullFlightAtCap() throws {
        let engine = incomingBanger(speed: 46)
        var warnings = 0, powers = 0
        for _ in 0..<180 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            warnings += events.filter { $0 == .bossPowerTelegraph }.count
            powers += events.filter { if case .bossPowerContact = $0 { return true }; return false }.count
            if events.contains(where: { if case .bossContact = $0 { return true }; return false }) { break }
        }
        #expect(warnings == 1 && powers == 1)
        let shot = try #require(engine.state.rallyShot)
        #expect(shot.kind == .power)
        #expect(shot.realizedSpeed > 30 * 1.35)
        #expect(shot.realizedSpeed <= engine.tuning.maximumBallSpeed)
    }

    @Test("A short unsafe drive route emits neither preparation nor power")
    func shortRouteNoFalseCue() {
        var tuning = GameTuning()
        tuning.banger.y = 12
        tuning.receivingBoundaryY = 5
        tuning.rallyBanger.observationDelay = 0
        tuning.rallyBanger.powerLeadTime = 0.01
        let engine = GameEngine(mode: .bossRally(.banger), tuning: tuning, seed: 83)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .banger, returnCount: 1)
        engine.state.ball = BallState(position: .init(x: 10, y: 5.1), velocity: .init(x: 0, y: 26))
        var warnings = 0, powers = 0, contacts = 0
        for _ in 0..<80 {
            let events = engine.update(delta: tuning.fixedStep)
            warnings += events.filter { $0 == .bossPowerTelegraph }.count
            powers += events.filter { if case .bossPowerContact = $0 { return true }; return false }.count
            contacts += events.filter { if case .bossContact = $0 { return true }; return false }.count
            if contacts > 0 { break }
        }
        #expect(contacts == 1 && warnings == 0 && powers == 0)
        #expect(engine.state.rallyShot?.kind == .normal)
    }

    @Test("Poacher keeps the announced target until an explicit delayed recovery")
    func honestCommitment() throws {
        let engine = GameEngine(mode: .bossRally(.poacher), seed: 83)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .poacher, x: 10, movementTarget: 13,
            specialPhase: .poachCommitment, specialRemaining: 2, committedSide: .right, committedTargetX: 13)
        engine.state.ball = BallState(position: .init(x: 12, y: 3), velocity: .init(x: 0, y: 26))
        for _ in 0..<40 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            let boss = try #require(engine.state.boss)
            #expect(!events.contains(.bossPoachRecovery))
            #expect(boss.specialPhase == .poachCommitment)
            #expect(boss.movementTarget == boss.committedTargetX)
        }
        #expect((engine.state.boss?.x ?? 0) > 10)
        // A new opposite-side shot remains unavailable until observation delay.
        engine.state.ball = BallState(position: .init(x: 3, y: 3), velocity: .init(x: 0, y: 26))
        var corrected = false
        for _ in 0..<40 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            if events.contains(.bossPoachRecovery) { corrected = true; break }
            #expect(engine.state.boss?.movementTarget == 13)
        }
        #expect(corrected)
        #expect(engine.state.boss?.specialPhase == .poachRecovery)
        #expect((engine.state.boss?.movementTarget ?? 13) < 13)
    }

    @Test("Production moderate repeated lane completes a correct read without false recovery",
          arguments: [UInt64(1), 7, 19, 42, 83, 99])
    func productionCorrectPoachRead(seed: UInt64) throws {
        let engine = GameEngine(mode: .bossRally(.poacher), seed: seed)
        engine.state.phase = .playing
        #expect(completedPlayerShot(engine, paddleX: 9.15).contains { if case .bossContact = $0 { return true }; return false })
        let second = completedPlayerShot(engine, paddleX: 9.15)
        #expect(second.contains { if case .bossPoachCommitment(side: .right, _) = $0 { return true }; return false })
        let committed = try #require(engine.state.boss)
        #expect(committed.specialPhase == .poachCommitment)
        #expect((committed.committedTargetX ?? 0) > (committed.committedReadX ?? 20))
        let sameLane = completedPlayerShot(engine, paddleX: 9.15)
        #expect(!sameLane.contains(.bossPoachRecovery))
        #expect(sameLane.contains { if case .bossContact = $0 { return true }; return false })
        #expect(!sameLane.contains { if case .bossPoint = $0 { return true }; return false })
    }

    @Test("A majority read excludes the opposite-lane outlier from its cue and destination")
    func majorityPoachRead() throws {
        let engine = GameEngine(mode: .bossRally(.poacher), seed: 83)
        engine.state.phase = .playing
        _ = completedPlayerShot(engine, paddleX: 10.85)
        _ = completedPlayerShot(engine, paddleX: 9.15)
        let third = completedPlayerShot(engine, paddleX: 9.15)
        #expect(third.contains { if case .bossPoachCommitment(side: .right, _) = $0 { return true }; return false })
        let committed = try #require(engine.state.boss)
        #expect((committed.committedReadX ?? 0) > CourtGeometry.centerX + engine.tuning.rallyPoacher.poachLaneThreshold)
        #expect((committed.committedTargetX ?? 0) > committed.x)
        let confirmed = completedPlayerShot(engine, paddleX: 9.15)
        #expect(!confirmed.contains(.bossPoachRecovery))
        #expect(confirmed.contains { if case .bossContact = $0 { return true }; return false })
    }

    @Test("Production changed lane exposes commitment momentum before delayed recovery")
    func productionChangedPoachRead() throws {
        let engine = GameEngine(mode: .bossRally(.poacher), seed: 83)
        engine.state.phase = .playing
        _ = completedPlayerShot(engine, paddleX: 9.15)
        _ = completedPlayerShot(engine, paddleX: 9.15)
        let committed = try #require(engine.state.boss)
        engine.state.ball = BallState(position: .init(x: 10, y: 2.7), velocity: .init(x: 0, y: -26))
        engine.movePlayer(crownDelta: 10.85 - engine.state.playerX)
        let earlyTicks = Int(engine.tuning.rallyPoacher.observationDelay * 0.70 / engine.tuning.fixedStep)
        for _ in 0..<earlyTicks {
            let events = engine.update(delta: engine.tuning.fixedStep)
            #expect(!events.contains(.bossPoachRecovery))
            #expect(engine.state.boss?.movementTarget == committed.committedTargetX)
        }
        #expect((engine.state.boss?.x ?? 0) > committed.x)
        var recovery = false
        for _ in 0..<50 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            if events.contains(.bossPoachRecovery) {
                let boss = try #require(engine.state.boss)
                #expect(boss.specialPhase == .poachRecovery)
                #expect(boss.movementTarget < boss.x)
                #expect(boss.lateralVelocity > 0, "Wrong read leaves physical momentum to brake rather than a snap")
                recovery = true; break
            }
        }
        #expect(recovery)
    }

    private func completedPlayerShot(_ engine: GameEngine, paddleX: Double) -> [GameEvent] {
        engine.state.phase = .playing
        engine.state.ball = BallState(position: .init(x: 10, y: 2.7), velocity: .init(x: 0, y: -26))
        engine.movePlayer(crownDelta: paddleX - engine.state.playerX)
        var result: [GameEvent] = []
        for _ in 0..<300 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            result += events
            if events.contains(where: { if case .bossContact = $0 { return true }; if case .bossPoint = $0 { return true }; return false }) { break }
        }
        return result
    }

    private func incomingBanger(speed: Double) -> GameEngine {
        let engine = GameEngine(mode: .bossRally(.banger), seed: 83)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .banger, returnCount: 1)
        engine.state.ball = BallState(position: .init(x: 10, y: 2.7), velocity: .init(x: 0, y: speed))
        return engine
    }
}
