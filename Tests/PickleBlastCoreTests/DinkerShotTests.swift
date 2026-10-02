import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Dinker bounded soft resets")
struct DinkerShotTests {
    @Test("A committed soft reset stays grounded and changes actual matched-route flight time",
          arguments: [UInt64(7), 19, 42, 99])
    func actualSoftFlight(seed: UInt64) throws {
        let tuning = GameTuning()
        let soft = contactFixture(tuning: tuning, seed: seed)
        var ordinaryTuning = tuning
        ordinaryTuning.rallyDinker.softSpeedRatio = 1
        let ordinary = contactFixture(tuning: ordinaryTuning, seed: seed)
        let softLaunch = try launch(soft)
        let ordinaryLaunch = try launch(ordinary)
        #expect(softLaunch.shot.kind == .soft)
        #expect(ordinaryLaunch.shot.kind == .normal)
        #expect(soft.state.boss?.specialPhase == .softRecovery)
        #expect(softLaunch.shot.lobFlight == nil)
        // Matched seed/contact chooses the same route before the pace change.
        let softDirection = softLaunch.ball.velocity * (1 / softLaunch.ball.speed)
        let ordinaryDirection = ordinaryLaunch.ball.velocity * (1 / ordinaryLaunch.ball.speed)
        #expect((softDirection - ordinaryDirection).length < 1e-8)
        let launchRatio = softLaunch.shot.realizedSpeed / ordinaryLaunch.shot.realizedSpeed
        #expect(launchRatio >= 0.65 && launchRatio <= 0.75)
        let softDuration = try receive(soft)
        let ordinaryDuration = try receive(ordinary)
        #expect(softDuration >= ordinaryDuration * 1.30)
        #expect(softDuration <= ordinaryDuration * 1.55)
        #expect(softDuration <= tuning.rallyDinker.softMaximumTravelDuration + tuning.fixedStep)
        #expect(soft.state.rallyShot?.kind == .normal)
        #expect(soft.state.rallyShot?.lobFlight == nil)
        #expect(soft.state.ball?.velocity.y ?? 0 > 0)
        #expect(soft.state.ball?.speed ?? 0 >= tuning.initialBallSpeed)
        // The normal pace is restored on the next genuine boss contact.
        let next = try launch(soft)
        #expect(next.shot.kind == .normal)
        #expect(next.shot.realizedSpeed >= tuning.initialBallSpeed)
        #expect(next.shot.realizedSpeed > softLaunch.shot.realizedSpeed * 1.25)
    }

    @Test("Real low and late-rally soft flights remain finite and within the duration cap",
          arguments: [16.0, 26.0, 46.0])
    func realizedCap(sourceSpeed: Double) throws {
        for x in [4.0, 10.0, 16.0] {
            let engine = contactFixture(seed: 42, x: x, sourceSpeed: sourceSpeed)
            engine.state.ball?.position.y = 2.7
            let flight = try launch(engine)
            #expect(flight.shot.kind == .soft)
            #expect(flight.shot.realizedSpeed >= engine.tuning.rallyDinker.softMinimumSpeed)
            let duration = try receive(engine)
            #expect(duration > 0)
            #expect(duration <= engine.tuning.rallyDinker.softMaximumTravelDuration + engine.tuning.fixedStep)
            #expect(engine.state.rallyShot?.lobFlight == nil)
        }
    }

    @Test("The travel floor rejects waiting beyond the cap and handles invalid numeric inputs")
    func safeBounds() {
        let tuning = GameTuning()
        let bounded = DinkerShotPolicy.speed(ordinarySpeed: 26, ordinaryTravelTime: 1.9, tuning: tuning)
        #expect(bounded >= 26 * 1.9 / tuning.rallyDinker.softMaximumTravelDuration)
        #expect(bounded <= 26)
        #expect(DinkerShotPolicy.speed(ordinarySpeed: 26, ordinaryTravelTime: 2.5, tuning: tuning) == 26)
        #expect(DinkerShotPolicy.speed(ordinarySpeed: 8, ordinaryTravelTime: 1, tuning: tuning) == 8)
        for value in [Double.nan, .infinity, -.infinity, -1, 0, 26, Double.greatestFiniteMagnitude] {
            for duration in [Double.nan, .infinity, -1, 0, 1.5, Double.greatestFiniteMagnitude] {
                let speed = DinkerShotPolicy.speed(ordinarySpeed: value, ordinaryTravelTime: duration, tuning: tuning)
                #expect(speed.isFinite && speed >= 0)
                if value.isFinite { #expect(speed <= max(0, value)) }
            }
        }
        var invalid = tuning
        invalid.rallyDinker.softSpeedRatio = .nan
        invalid.rallyDinker.softMinimumSpeed = .infinity
        #expect(DinkerShotPolicy.speed(ordinarySpeed: 26, ordinaryTravelTime: 1.4, tuning: invalid).isFinite)
        invalid.rallyDinker.softMaximumTravelDuration = .nan
        #expect(DinkerShotPolicy.speed(ordinarySpeed: 26, ordinaryTravelTime: 1.4, tuning: invalid) == 26)
    }

    @Test("A tight travel cap raises realized soft speed before launch, while retaining the reset")
    func durationFloorIsRealized() throws {
        var tuning = GameTuning()
        tuning.rallyDinker.softMaximumTravelDuration = 1.75
        let engine = contactFixture(tuning: tuning, seed: 42)
        let flight = try launch(engine)
        #expect(flight.shot.kind == .soft)
        #expect(flight.shot.realizedSpeed > flight.shot.requestedSpeed)
        #expect(flight.shot.realizedSpeed < tuning.initialBallSpeed)
        #expect(try receive(engine) <= tuning.rallyDinker.softMaximumTravelDuration + tuning.fixedStep)
    }

    @Test("A late reachable contact returns normally when there is no time for a legal tell")
    func shortContactSuppressesSpecial() throws {
        let engine = contactFixture(seed: 7)
        engine.state.ball?.position.y = 39.8
        let flight = try launch(engine)
        #expect(flight.shot.kind == .normal)
        #expect(flight.shot.lobFlight == nil)
        #expect(engine.state.boss?.specialPhase == .idle)
        #expect(engine.state.boss?.returnCount == 3)
    }

    @Test("Seeded soft cadence leaves two ordinary returns and varies within three to five")
    func seededCooldown() throws {
        var intervals = Set<Int>()
        for seed in [UInt64(7), 19, 42, 99] {
            let first = try cadence(seed: seed)
            let repeated = try cadence(seed: seed)
            #expect(first == repeated)
            let softReturns = first.enumerated().compactMap { $0.element == .soft ? $0.offset + 1 : nil }
            #expect(softReturns.first == 3)
            #expect(softReturns.count >= 4)
            for (prior, next) in zip(softReturns, softReturns.dropFirst()) {
                let interval = next - prior
                #expect(interval >= 3 && interval <= 5)
                #expect(first[prior..<next - 1].allSatisfy { $0 == .normal })
                intervals.insert(interval)
            }
        }
        #expect(intervals.count > 1)
    }

    @Test("Soft recovery continues finite movement and accepts reachable ordinary contact")
    func activeRecovery() throws {
        let engine = contactFixture(seed: 7)
        _ = try launch(engine)
        let before = try #require(engine.state.boss).x
        engine.state.ball = BallState(position: .init(x: before + 3, y: 22.1),
                                      velocity: .init(x: 0, y: 26))
        _ = advance(engine, seconds: 0.32)
        let moving = try #require(engine.state.boss)
        #expect(moving.specialPhase == .softRecovery)
        #expect(moving.x > before)
        #expect(moving.x - before <= engine.tuning.rallyDinker.maximumLateralSpeed * 0.32)

        let returning = contactFixture(seed: 7)
        _ = try launch(returning)
        let x = try #require(returning.state.boss).x
        returning.state.ball = BallState(position: .init(x: x + 1, y: 36),
                                         velocity: .init(x: 0, y: 26))
        let ordinary = try launch(returning)
        #expect(ordinary.shot.kind == .normal)
        #expect(returning.state.boss?.returnCount == 4)
        #expect(returning.state.playerRallyPoints == 0)
    }

    @Test("Pause freezes a real soft flight and reset removes shot and recovery state")
    func pauseAndReset() throws {
        let engine = contactFixture(seed: 7)
        _ = try launch(engine)
        _ = advance(engine, seconds: 0.4)
        engine.pause()
        let frozen = engine.state
        #expect(engine.update(delta: 60).isEmpty)
        #expect(engine.state == frozen)
        engine.resume()
        let ballBeforeCountdown = engine.state.ball
        _ = advance(engine, seconds: engine.tuning.resumeDuration)
        #expect(engine.state.ball == ballBeforeCountdown)
        #expect(engine.state.rallyShot?.kind == .soft)
        #expect(try receive(engine) < engine.tuning.rallyDinker.softMaximumTravelDuration)
        engine.reset(seed: 7)
        #expect(engine.state.rallyShot == nil)
        #expect(engine.state.boss?.specialPhase == .idle)
        #expect(engine.state.boss?.returnCount == 0)
        #expect(engine.state == GameEngine(mode: .bossRally(.dinker), seed: 7).state)
    }

    @Test("Soft contact and receiving happen once across 120, 60, 30 and 15 Hz frames")
    func frameCadence() throws {
        var durations: [Double] = []
        for frame in [1.0 / 120, 1.0 / 60, 1.0 / 30, 1.0 / 15] {
            let engine = contactFixture(seed: 7)
            let flight = try launch(engine, frame: frame)
            #expect(flight.shot.kind == .soft)
            durations.append(try receive(engine, frame: frame))
            #expect(engine.state.currentRallyReturns == 2)
            #expect(engine.state.playerRallyPoints == 0 && engine.state.opponentRallyPoints == 0)
            #expect(engine.state.recoveriesRemaining == 2)
        }
        #expect((durations.max() ?? 0) - (durations.min() ?? 0) <= 1.0 / 15 + 1e-8)
    }

    @Test("Wide ordinary placement can win before the first soft reset is eligible")
    func ordinaryPlacementWins() throws {
        let engine = GameEngine(mode: .bossRally(.dinker), seed: 7)
        for point in 1...3 {
            // A boss stretched to the other side has a real finite travel limit.
            // Contact is still decided by the ordinary swept player hit surface.
            engine.state.phase = .playing
            engine.state.boss?.x = 1.75
            engine.state.boss?.movementTarget = 1.75
            engine.state.boss?.lateralVelocity = 0
            engine.state.ball = BallState(position: .init(x: 18, y: 3), velocity: .init(x: 0, y: -26))
            engine.movePlayer(crownDelta: 18 - engine.state.playerX)
            let events = advance(engine, seconds: 1.7)
            #expect(events.paddleContacts == 1)
            #expect(events.bossContacts == 0)
            #expect(events.bossPoints == 1)
            #expect(engine.state.playerRallyPoints == point)
            #expect(engine.state.opponentRallyPoints == 0)
            #expect(engine.state.recoveriesRemaining == 2)
            #expect(engine.state.boss?.returnCount == 0)
            #expect(!events.contains {
                if case .rallyShotLaunched(_, _, .soft) = $0 { return true }; return false
            })
        }
        #expect(engine.state.won)
        #expect(engine.state.score == 3 * engine.tuning.bossPointScore + engine.tuning.bossVictoryBonus)
    }

    private struct Launch {
        let shot: RallyShotState
        let ball: BallState
    }

    private func contactFixture(tuning: GameTuning = GameTuning(), seed: UInt64,
                                x: Double = 10, sourceSpeed: Double = 26) -> GameEngine {
        let engine = GameEngine(mode: .bossRally(.dinker), tuning: tuning, seed: seed)
        engine.state.phase = .playing
        engine.state.phaseTimeRemaining = 0
        engine.state.boss = BossState(id: .dinker, x: x, movementTarget: x, returnCount: 2)
        engine.state.ball = BallState(position: .init(x: x, y: 22.1),
                                      velocity: .init(x: 0, y: sourceSpeed))
        return engine
    }

    private func launch(_ engine: GameEngine, frame: Double = 1.0 / 120) throws -> Launch {
        var warnings: [(rallyID: UInt64, shotID: UInt64, time: Double)] = []
        for _ in 0..<Int(ceil(4 / frame)) {
            let events = engine.update(delta: frame)
            for event in events {
                if case let .rallyShotPrepared(rallyID, shotID, .soft) = event {
                    warnings.append((rallyID, shotID, engine.state.simulationTime))
                }
            }
            if events.bossContacts > 0 {
                #expect(events.bossContacts == 1)
                #expect(events.bossPoints == 0)
                let shot = try #require(engine.state.rallyShot)
                #expect(events.filter {
                    if case .rallyShotLaunched(_, _, _) = $0 { return true }; return false
                }.count == 1)
                if shot.kind == .soft {
                    #expect(warnings.count == 1)
                    let warning = try #require(warnings.first)
                    #expect(warning.rallyID == shot.rallyID && warning.shotID == shot.shotID)
                    #expect(engine.state.simulationTime - warning.time + frame
                            >= engine.tuning.rallyDinker.specialLeadTime)
                }
                return Launch(shot: shot, ball: try #require(engine.state.ball))
            }
        }
        Issue.record("Expected a genuine Dinker paddle crossing within four seconds")
        throw FixtureError.noContact
    }

    /// Uses the public input path with a fixed receiving target after launch.
    /// This centered-return fixture measures mechanics, not human difficulty.
    private func receive(_ engine: GameEngine, frame: Double = 1.0 / 120) throws -> Double {
        let start = engine.state.simulationTime
        let ball = try #require(engine.state.ball)
        let forecast = try #require(RallyBallProjection.arrival(of: ball,
            atY: engine.tuning.playerY + ball.radius, tuning: engine.tuning,
            speedGrowth: engine.tuning.rallyDinker.speedGrowthPerSecond))
        engine.movePlayer(crownDelta: forecast.position.x - engine.state.playerX)
        for _ in 0..<Int(ceil(4 / frame)) {
            #expect(engine.state.rallyShot?.lobFlight == nil)
            let events = engine.update(delta: frame)
            if events.paddleContacts > 0 {
                #expect(events.paddleContacts == 1)
                #expect(!events.contains { if case .ballRecovered = $0 { return true }; return false })
                return engine.state.simulationTime - start
            }
        }
        Issue.record("Expected one centered player return within four seconds")
        throw FixtureError.noContact
    }

    private func cadence(seed: UInt64) throws -> [RallyShotKind] {
        let engine = contactFixture(seed: seed)
        engine.state.boss?.returnCount = 0
        var kinds: [RallyShotKind] = []
        // Equivalent legal incoming routes isolate scheduling from player misses.
        for _ in 0..<24 {
            let x = try #require(engine.state.boss).x
            engine.state.ball = BallState(position: .init(x: x, y: 22.1), velocity: .init(x: 0, y: 26))
            kinds.append(try launch(engine).shot.kind)
            _ = advance(engine, seconds: 0.6)
        }
        return kinds
    }

    private enum FixtureError: Error { case noContact }
}
