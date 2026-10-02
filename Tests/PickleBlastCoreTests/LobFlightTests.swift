import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Authoritative Lobber flights")
struct LobFlightTests {
    @Test("Real prepared lob commits an assisted legal path and one descending contact")
    func realLob() throws {
        let engine = try launchedLob()
        let shot = try #require(engine.state.rallyShot)
        let initial = try #require(shot.lobFlight)
        #expect(shot.kind == .lob)
        #expect(initial.duration <= engine.tuning.rallyLobber.lobMaximumTravelDuration)
        #expect(initial.destination.x >= engine.tuning.ballRadius)
        #expect(initial.destination.x <= CourtGeometry.width - engine.tuning.ballRadius)
        #expect(initial.destination.y == engine.tuning.playerY + engine.tuning.ballRadius)
        let launchedBall = try #require(engine.state.ball)
        let forecast = try #require(RallyBallProjection.arrival(of: launchedBall,
            atY: initial.destination.y, tuning: engine.tuning,
            speedGrowth: engine.tuning.rallyLobber.speedGrowthPerSecond, lobFlight: initial))
        #expect(forecast.position == initial.destination)
        #expect(abs(forecast.time - initial.remainingDuration) < 1e-10)
        #expect(forecast.sideReflections == 0)
        let apparent = ReceivingTrajectory.apparentAngle(of: initial.velocity, at: initial.origin,
            projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor)
        #expect(apparent <= engine.tuning.maximumIncomingApparentAngle + 1e-8)
        engine.movePlayer(crownDelta: initial.receivingX - engine.state.playerX)
        var previousElapsed = initial.elapsed, contacts = 0
        var maximumHeight = initial.height
        for _ in 0..<360 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            contacts += events.filter { if case .paddleContact = $0 { return true }; return false }.count
            if let lob = engine.state.rallyShot?.lobFlight {
                #expect(lob.destination == initial.destination)
                #expect(lob.elapsed >= previousElapsed)
                #expect(engine.state.ball?.position == lob.groundPosition)
                #expect(lob.height >= 0 && lob.height <= lob.peakHeight)
                #expect(contacts == 0)
                maximumHeight = max(maximumHeight, lob.height)
                previousElapsed = lob.elapsed
            } else { break }
        }
        #expect(maximumHeight > initial.peakHeight * 0.99)
        #expect(contacts == 1)
        #expect(engine.state.rallyShot?.kind == .normal)
        #expect(engine.state.rallyShot?.lobFlight == nil)
        #expect((engine.state.ball?.velocity.y ?? 0) > 0)
        #expect((engine.state.ball?.speed ?? 0) >= engine.tuning.initialBallSpeed)
        #expect(engine.state.currentRallyReturns == 2)
    }

    @Test("Analytic arrival is exactly once at multiple callback cadences",
          arguments: [1.0 / 120, 1.0 / 30, 0.10])
    func sweptArrival(cadence: Double) throws {
        let engine = try launchedLob()
        let lob = try #require(engine.state.rallyShot?.lobFlight)
        engine.movePlayer(crownDelta: lob.receivingX - engine.state.playerX)
        var contacts = 0
        for _ in 0..<Int(ceil(lob.duration / cadence)) + 2 {
            let events = engine.update(delta: cadence)
            contacts += events.filter { if case .paddleContact = $0 { return true }; return false }.count
        }
        #expect(contacts == 1)
        #expect(engine.state.playerRallyPoints == 0 && engine.state.opponentRallyPoints == 0)
        #expect(engine.state.recoveriesRemaining == 2)
    }

    @Test("Rise, apex and descent freeze through interruption and resume without a jump",
          arguments: [0.20, 0.50, 0.85])
    func interruptedFlight(fraction: Double) throws {
        let engine = try launchedLob()
        let duration = try #require(engine.state.rallyShot?.lobFlight).duration
        while (engine.state.rallyShot?.lobFlight?.fraction ?? 1) < fraction {
            _ = engine.update(delta: engine.tuning.fixedStep)
        }
        let lob = try #require(engine.state.rallyShot?.lobFlight)
        engine.pause()
        let paused = engine.state
        #expect(engine.update(delta: 30).isEmpty)
        #expect(engine.state == paused)
        engine.resume()
        for _ in 0..<Int(floor(engine.tuning.resumeDuration / engine.tuning.fixedStep)) {
            _ = engine.update(delta: engine.tuning.fixedStep)
        }
        #expect(engine.state.rallyShot?.lobFlight == lob)
        _ = engine.update(delta: engine.tuning.fixedStep)
        let resumed = try #require(engine.state.rallyShot?.lobFlight)
        #expect(resumed.elapsed - lob.elapsed <= engine.tuning.fixedStep + 1e-8)
        #expect(resumed.duration == duration)
    }

    @Test("Missed lobs use two non-scoring saves then first-to-three opponent points")
    func lobMissScoring() throws {
        let engine = GameEngine(mode: .bossRally(.lobber), seed: 83)
        var saved = 0, scored = 0
        for _ in 0..<5 {
            engine.state.phase = .playing
            engine.state.playerX = 18.9
            let origin = Vector2(x: 3, y: engine.activeBossConfiguration.y - engine.tuning.ballRadius)
            let destination = Vector2(x: 3, y: engine.tuning.playerY + engine.tuning.ballRadius)
            let flight = LobFlightState(origin: origin, destination: destination, duration: 1.5,
                elapsed: 1.5 - engine.tuning.fixedStep / 2, peakHeight: 5)
            engine.state.ball = BallState(position: flight.groundPosition, velocity: flight.velocity)
            engine.state.rallyShot = RallyShotState(rallyID: 1, shotID: UInt64(saved + scored + 1), kind: .lob,
                requestedSpeed: flight.velocity.length, realizedSpeed: flight.velocity.length, lobFlight: flight)
            let events = engine.update(delta: 0.10)
            saved += events.filter { if case .ballRecovered = $0 { return true }; return false }.count
            scored += events.filter { if case .opponentPoint = $0 { return true }; return false }.count
            #expect(!events.contains { if case .paddleContact = $0 { return true }; return false })
            #expect(engine.state.rallyShot == nil)
        }
        #expect(saved == 2 && scored == 3)
        #expect(engine.state.phase == .results)
        #expect(engine.state.opponentRallyPoints == 3)
        #expect(engine.state.playerRallyPoints == 0 && engine.state.score == 0)
    }

    @Test("Rematch clears elevated state and repeats fresh seeded control")
    func rematchClears() throws {
        let engine = try launchedLob()
        engine.reset()
        let fresh = GameEngine(mode: .bossRally(.lobber), seed: 83)
        #expect(engine.state.rallyShot == nil)
        #expect(engine.state == fresh.state)
        for _ in 0..<200 {
            #expect(engine.update(delta: 1.0 / 30) == fresh.update(delta: 1.0 / 30))
            #expect(engine.state == fresh.state)
        }
    }

    private func launchedLob() throws -> GameEngine {
        let engine = GameEngine(mode: .bossRally(.lobber), seed: 83)
        engine.state.phase = .playing
        engine.state.boss = BossState(id: .lobber, returnCount: 2)
        engine.state.ball = BallState(position: .init(x: 10, y: 2.7), velocity: .init(x: 0, y: 26))
        var tell: Double?
        for _ in 0..<240 {
            let events = engine.update(delta: engine.tuning.fixedStep)
            if events.contains(where: { if case .rallyShotPrepared(_, _, .lob) = $0 { return true }; return false }) {
                tell = engine.state.simulationTime
            }
            if engine.state.rallyShot?.kind == .lob {
                #expect(engine.state.simulationTime - (tell ?? engine.state.simulationTime)
                    >= engine.tuning.rallyLobber.specialLeadTime - 1e-8)
                return engine
            }
        }
        Issue.record("No legal prepared lob was launched")
        return engine
    }
}
