import Testing
@testable import PickleBlastCore

@Suite("Boss Rally earned saves")
struct EarnedRecoveryTests {
    private func playing(_ id: BossID = .wall) -> GameEngine {
        let engine = GameEngine(mode: .bossRally(id), seed: 20)
        engine.state.phase = .playing
        engine.state.phaseTimeRemaining = 0
        return engine
    }

    /// Each fixture feeds an actual swept player collision through update;
    /// contact, award, counters and events remain the engine's responsibility.
    private func returnBall(_ engine: GameEngine, frame: Double = 0.1) -> [GameEvent] {
        engine.state.ball = BallState(position: .init(x: 10, y: 3), velocity: .init(x: 0, y: -26))
        return advance(engine, seconds: 0.1, frame: frame)
    }

    private func miss(_ engine: GameEngine) -> [GameEvent] {
        engine.state.phase = .playing
        engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29), velocity: .init(x: 0, y: -26))
        return advance(engine, seconds: 0.1)
    }

    private func winPoint(_ engine: GameEngine) -> [GameEvent] {
        engine.state.phase = .playing
        engine.state.boss?.x = 2
        engine.state.boss?.movementTarget = 2
        engine.state.ball = BallState(position: .init(x: 18, y: 43.9), velocity: .init(x: 0, y: 26))
        return advance(engine, seconds: 0.1)
    }

    @Test("Nineteen returns earn nothing; twenty earns exactly one save; twenty-one does not repeat",
          arguments: BossID.allCases)
    func boundaryAndSingleAward(id: BossID) {
        let engine = playing(id)
        #expect(GameTuning.earnedRecoveryReturnInterval == 20)
        #expect(engine.state.recoveriesRemaining == 0)
        for count in 1...21 {
            let events = returnBall(engine)
            #expect(events.paddleContacts == 1)
            #expect(engine.state.consecutivePlayerReturns == count)
            #expect(engine.state.longestRallyReturns == count)
            #expect(engine.state.recoveriesRemaining == (count < 20 ? 0 : 1))
            #expect(events.filter { $0 == .recoveryEarned }.count == (count == 20 ? 1 : 0))
            #expect(events.filter { if case .rallyMilestone = $0 { return true }; return false }.count == (count == 20 ? 1 : 0))
            if count == 20 { #expect(events.contains(.rallyMilestone(returns: 20))) }
        }
        let idle = advance(engine, seconds: 0.1)
        #expect(!idle.contains(.recoveryEarned))
        #expect(engine.state.recoveriesRemaining == 1)
    }

    @Test("Milestones repeat at forty and sixty while the bank stays capped at one")
    func repeatedMilestonesDoNotStackOrAccrueCredit() {
        let engine = playing()
        var all: [GameEvent] = []
        for _ in 1...61 { all += returnBall(engine) }
        let milestones = all.compactMap { event -> Int? in
            if case let .rallyMilestone(returns) = event { return returns }; return nil
        }
        #expect(milestones == [20, 40, 60])
        #expect(all.filter { $0 == .recoveryEarned }.count == 1)
        #expect(engine.state.recoveriesRemaining == 1)
        #expect(miss(engine).contains(.ballRecovered(remaining: 0)))
        #expect(engine.state.consecutivePlayerReturns == 0)
        #expect(engine.state.recoveriesRemaining == 0)
        #expect(engine.state.opponentRallyPoints == 0)
        engine.state.phase = .playing
        for count in 1...20 {
            let events = returnBall(engine)
            #expect(engine.state.recoveriesRemaining == (count < 20 ? 0 : 1))
            #expect(events.contains(.recoveryEarned) == (count == 20))
        }
    }

    @Test("A bank survives a won point but both winning and losing points reset the streak")
    func pointAndMissBoundaries() {
        let engine = playing()
        for _ in 1...20 { _ = returnBall(engine) }
        #expect(winPoint(engine).contains(.bossPoint(points: 1)))
        #expect(engine.state.consecutivePlayerReturns == 0)
        #expect(engine.state.longestRallyReturns == 20)
        #expect(engine.state.recoveriesRemaining == 1)
        engine.state.phase = .playing
        for _ in 1...19 { _ = returnBall(engine) }
        let saved = miss(engine)
        #expect(saved.filter { $0 == .ballRecovered(remaining: 0) }.count == 1)
        #expect(!saved.contains(.opponentPoint(points: 1)))
        #expect(engine.state.consecutivePlayerReturns == 0 && engine.state.recoveriesRemaining == 0)
        engine.state.phase = .playing
        for _ in 1...19 { _ = returnBall(engine) }
        #expect(miss(engine).contains(.opponentPoint(points: 1)))
        #expect(engine.state.consecutivePlayerReturns == 0 && engine.state.recoveriesRemaining == 0)
        #expect(engine.state.playerRallyPoints == 1)
    }

    @Test("A miss at nineteen on the deciding point resets streak and ends without a save")
    func terminalMiss() {
        let engine = playing()
        engine.state.boss?.opponentPoints = 2
        for _ in 1...19 { _ = returnBall(engine) }
        let events = miss(engine)
        #expect(events.contains(.opponentPoint(points: 3)))
        #expect(engine.state.phase == .results && !engine.state.won)
        #expect(engine.state.consecutivePlayerReturns == 0)
        #expect(engine.state.longestRallyReturns == 19)
        #expect(engine.state.recoveriesRemaining == 0)
        #expect(!events.contains(.recoveryEarned))
    }

    @Test("The deciding player point also ends its streak while preserving the recorded best")
    func terminalWin() {
        let engine = playing()
        engine.state.boss?.points = 2
        for _ in 1...20 { _ = returnBall(engine) }
        #expect(winPoint(engine).contains(.bossDefeated))
        #expect(engine.state.consecutivePlayerReturns == 0)
        #expect(engine.state.completedBossMatches.last?.longestRallyReturns == 20)
        #expect(engine.state.recoveriesRemaining == 1)
    }

    @Test("Pause and countdown cannot repeat an award; reset clears bank and streak")
    func pauseAndRetry() {
        let engine = playing()
        for _ in 1...20 { _ = returnBall(engine) }
        engine.pause()
        let frozen = engine.state
        #expect(engine.update(delta: 60).isEmpty)
        #expect(engine.state == frozen)
        engine.resume()
        let events = advance(engine, seconds: engine.tuning.resumeDuration)
        #expect(!events.contains(.recoveryEarned))
        #expect(engine.state.consecutivePlayerReturns == 20 && engine.state.recoveriesRemaining == 1)
        #expect(!returnBall(engine).contains(.recoveryEarned))
        engine.reset()
        #expect(engine.state.consecutivePlayerReturns == 0 && engine.state.recoveriesRemaining == 0)
        #expect(engine.state.longestRallyReturns == 0)
    }

    @Test("Serving, wall reflection and boss contact do not earn a player return")
    func onlyPlayerContactsCount() {
        let engine = GameEngine(mode: .bossRally(.wall), seed: 20)
        _ = advance(engine, seconds: engine.tuning.readyDuration)
        #expect(engine.state.consecutivePlayerReturns == 0)
        engine.state.ball = BallState(position: .init(x: 19.6, y: 22), velocity: .init(x: 26, y: 1))
        let wall = engine.update(delta: 0.1)
        #expect(wall.contains(.wallContact))
        #expect(engine.state.consecutivePlayerReturns == 0)
        engine.state.boss?.x = 10
        engine.state.boss?.movementTarget = 10
        engine.state.ball = BallState(position: .init(x: 10,
            y: engine.activeBossConfiguration.y - engine.tuning.ballRadius - 0.5),
            velocity: .init(x: 0, y: 26))
        let boss = engine.update(delta: 0.1)
        #expect(boss.bossContacts == 1)
        #expect(engine.state.consecutivePlayerReturns == 0 && engine.state.recoveriesRemaining == 0)
        #expect(engine.state.currentRallyReturns == 1) // Existing record counter includes both sides.
        #expect(engine.state.longestRallyReturns == 1)
        #expect(!boss.contains(.recoveryEarned))
        #expect(!boss.contains { if case .rallyMilestone = $0 { return true }; return false })
        #expect(returnBall(engine).paddleContacts == 1)
        #expect(engine.state.consecutivePlayerReturns == 1)
        #expect(engine.state.currentRallyReturns == 2)
        #expect(engine.state.longestRallyReturns == 2)
    }

    @Test("Swept contacts have identical awards across fixed and grouped frame delivery",
          arguments: [1.0 / 120, 1.0 / 30, 0.1])
    func cadence(frame: Double) {
        let engine = playing()
        var earned = 0, contacts = 0
        for _ in 1...21 {
            let events = returnBall(engine, frame: frame)
            contacts += events.paddleContacts
            earned += events.filter { $0 == .recoveryEarned }.count
        }
        #expect(contacts == 21 && earned == 1)
        #expect(engine.state.consecutivePlayerReturns == 21 && engine.state.recoveriesRemaining == 1)
    }

    @Test("Nineteen player and nineteen boss contacts earn nothing; the twentieth player return earns one")
    func alternatingContactsKeepRecordAndAwardCountersSeparate() {
        let engine = playing()
        for count in 1...20 {
            let player = returnBall(engine)
            #expect(engine.state.consecutivePlayerReturns == count)
            #expect(engine.state.currentRallyReturns == count * 2 - 1)
            #expect(player.contains(.recoveryEarned) == (count == 20))
            #expect(engine.state.recoveriesRemaining == (count < 20 ? 0 : 1))
            engine.state.boss?.x = 10
            engine.state.boss?.movementTarget = 10
            engine.state.ball = BallState(position: .init(x: 10,
                y: engine.activeBossConfiguration.y - engine.tuning.ballRadius - 0.5),
                velocity: .init(x: 0, y: 26))
            let boss = engine.update(delta: 0.1)
            #expect(boss.bossContacts == 1)
            #expect(!boss.contains(.recoveryEarned))
            #expect(!boss.contains { if case .rallyMilestone = $0 { return true }; return false })
            #expect(engine.state.consecutivePlayerReturns == count)
            #expect(engine.state.currentRallyReturns == count * 2)
        }
        #expect(engine.state.longestRallyReturns == 40)
        #expect(engine.state.consecutivePlayerReturns == 20)
    }

    @Test("Arcade keeps its accepted two automatic allowances and earns no rally saves")
    func arcadeUnchanged() {
        let engine = activeEngine(boss: true)
        #expect(engine.state.recoveriesRemaining == 2)
        var events: [GameEvent] = []
        for _ in 1...21 { events += returnBall(engine) }
        #expect(engine.state.recoveriesRemaining == 2)
        #expect(!events.contains(.recoveryEarned))
        #expect(!events.contains { if case .rallyMilestone = $0 { return true }; return false })
        #expect(miss(engine).contains(.ballRecovered(remaining: 1)))
    }
}
