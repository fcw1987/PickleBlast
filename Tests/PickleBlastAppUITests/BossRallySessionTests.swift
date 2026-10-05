import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Boss Rally session lifecycle")
@MainActor
struct BossRallySessionTests {
    private func makeSession(id: BossID, defaults: UserDefaults? = nil)
        -> (GameSession, UserDefaults, String) {
        let suite = "PickleBlast-boss-session-\(UUID().uuidString)"
        let storage = defaults ?? UserDefaults(suiteName: suite)!
        let session = GameSession(
            preferences: AppPreferences(storage: LocalStore(defaults: storage)),
            mode: .bossRally(id))
        return (session, storage, suite)
    }

    private func frames(_ count: Int, session: GameSession, time: inout Double) {
        for _ in 0..<count {
            time += 1.0 / 120
            session.scene.onFrame?(time)
        }
    }

    @Test("Each selected boss starts directly in its encounter and rematch preserves selection",
          arguments: BossID.allCases)
    func directStartAndRematch(id: BossID) {
        let (session, defaults, suite) = makeSession(id: id)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(session.mode == .bossRally(id))
        #expect(session.engine.state.mode == .bossRally(id))
        #expect(session.engine.state.bossID == id)
        #expect(session.engine.state.stage == .boss)
        #expect(session.engine.state.targets.isEmpty)
        #expect(session.engine.state.boss?.id == id)

        session.engine.state.score = 2_750
        session.engine.state.currentRallyReturns = 4
        session.engine.state.longestRallyReturns = 7
        session.engine.state.boss?.points = 2
        session.restart()

        #expect(session.mode == .bossRally(id))
        #expect(session.engine.state.mode == .bossRally(id))
        #expect(session.engine.state.stage == .boss)
        #expect(session.engine.state.targets.isEmpty)
        #expect(session.engine.state.boss?.id == id)
        #expect(session.engine.state.boss?.points == 0)
        #expect(session.engine.state.opponentRallyPoints == 0)
        #expect(session.playerRallyPoints == 0 && session.opponentRallyPoints == 0)
        #expect(session.engine.state.score == 0)
        #expect(session.engine.state.currentRallyReturns == 0)
        #expect(session.engine.state.longestRallyReturns == 0)
    }

    @Test("Pause and resume freeze a Boss Rally countdown, then a miss consumes a previously earned save")
    func pauseResumeAndMissAllowance() {
        let (session, defaults, suite) = makeSession(id: .banger)
        defer { defaults.removePersistentDomain(forName: suite) }
        session.beginIfActive(true)
        session.engine.state.phase = .playing
        session.engine.state.ball = BallState(position: .init(x: 10, y: 35),
                                              velocity: .init(x: 0, y: -26))
        session.engine.state.currentRallyReturns = 5
        session.engine.state.longestRallyReturns = 8
        // A save banked by a previous twenty-return point survives this point.
        session.engine.state.recoveriesRemaining = 1
        let rallyBall = session.engine.state.ball
        var time = 0.0

        session.pause()
        let pausedState = session.engine.state
        time += 3_600
        session.scene.onFrame?(time)
        #expect(session.engine.state == pausedState)

        session.resume()
        var resumedState = pausedState
        resumedState.isPaused = false
        resumedState.resumeCountdown = session.engine.tuning.resumeDuration
        session.scene.onFrame?(time) // Rebase the first frame without consuming background time.
        #expect(session.engine.state == resumedState)
        for _ in 0..<200 {
            if session.engine.state.resumeCountdown == 0 { break }
            frames(1, session: session, time: &time)
            #expect(session.engine.state.ball == rallyBall)
            #expect(session.engine.state.currentRallyReturns == 5)
            #expect(session.engine.state.longestRallyReturns == 8)
        }
        #expect(session.engine.state.resumeCountdown == 0)
        #expect(session.engine.state.phase == .playing)
        #expect(session.engine.state.bossID == .banger)
        frames(1, session: session, time: &time)
        #expect(session.engine.state.ball?.position.y ?? 35 < (rallyBall?.position.y ?? 35))
        #expect(session.engine.state.lives == 3)
        #expect(session.engine.state.recoveriesRemaining == 1)

        session.engine.state.phase = .playing
        session.engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29),
                                              velocity: .init(x: 0, y: -26))
        frames(4, session: session, time: &time)
        #expect(session.engine.state.phase == .ready)
        #expect(session.engine.state.lives == 3)
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.currentRallyReturns == 0)
        #expect(session.engine.state.longestRallyReturns == 8)

        session.engine.state.phase = .playing
        session.engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29),
                                              velocity: .init(x: 0, y: -26))
        frames(4, session: session, time: &time)
        #expect(session.engine.state.opponentRallyPoints == 1)
        #expect(session.opponentRallyPoints == 1)
        #expect(session.engine.state.lives == 3) // Rally has points, not another life-loss condition.
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.mode == .bossRally(.banger))
        #expect(!session.finished)
    }

    @Test("A Boss Rally victory result records once for the selected opponent and survives rematch")
    func victoryRecordAndRematch() {
        let (session, defaults, suite) = makeSession(id: .poacher)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(session.preferences.record(score: 8_000))
        session.beginIfActive(true)

        // Drive the ordinary final transition with an explicit state fixture;
        // GameSession still receives and persists the engine's runEnded event.
        session.engine.state.phase = .blackout
        session.engine.state.phaseTimeRemaining = 0.001
        session.engine.state.won = true
        session.engine.state.score = 4_250
        session.engine.state.longestRallyReturns = 13
        var time = 0.0
        frames(3, session: session, time: &time)

        #expect(session.finished)
        #expect(session.engine.state.phase == .results)
        #expect(session.preferences.bossRecord(for: .poacher) ==
                BossRecord(wins: 1, bestScore: 4_250, longestRally: 13))
        #expect(session.preferences.bossRecord(for: .wall) == BossRecord())
        #expect(session.preferences.bossRecord(for: .banger) == BossRecord())
        #expect(session.preferences.best == 8_000)

        session.scene.onFrame?(time + 1)
        #expect(session.preferences.bossRecord(for: .poacher).wins == 1)
        session.restart()
        #expect(session.mode == .bossRally(.poacher))
        #expect(session.engine.state.stage == .boss)
        #expect(session.preferences.bossRecord(for: .poacher).wins == 1)
    }

    @Test("Repeated Boss Rally defeats and rematches keep Arcade score isolated and release on Home")
    func repeatedRallyRematchAndExit() {
        let suite = "PickleBlast-boss-repeat-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(storage: LocalStore(defaults: defaults))
        #expect(preferences.record(score: 9_500))

        for id in BossID.allCases {
            var owner: GameSession? = GameSession(preferences: preferences, mode: .bossRally(id))
            weak var observedSession = owner
            weak var observedScene = owner?.scene
            let pendingFrame = owner?.scene.onFrame
            owner?.beginIfActive(true)
            var time = 0.0

            for cycle in 0..<10 {
                let resultScore = 1_000 + cycle * 50
                owner?.engine.state.phase = .playing
                owner?.engine.state.lives = 3
                owner?.engine.state.boss?.opponentPoints = 2
                owner?.engine.state.recoveriesRemaining = 0
                owner?.engine.state.score = resultScore
                owner?.engine.state.currentRallyReturns = 4
                owner?.engine.state.longestRallyReturns = cycle + 6
                owner?.engine.state.ball = BallState(
                    position: .init(x: 0.3, y: -0.29), velocity: .init(x: 0, y: -26))
                frames(4, session: owner!, time: &time)

                #expect(owner?.finished == true)
                #expect(owner?.phase == .results)
                #expect(owner?.engine.state.mode == .bossRally(id))
                #expect(owner?.preferences.best == 9_500)
                #expect(owner?.preferences.bossRecord(for: id) == BossRecord(
                    wins: 0, bestScore: resultScore, longestRally: cycle + 6))

                pendingFrame?(time + 1)
                #expect(owner?.preferences.bossRecord(for: id).bestScore == resultScore)

                owner?.restart()
                #expect(owner?.finished == false)
                #expect(owner?.mode == .bossRally(id))
                #expect(owner?.engine.state.stage == .boss)
                #expect(owner?.engine.state.boss?.id == id)
                #expect(owner?.engine.state.targets.isEmpty == true)
                #expect(owner?.engine.state.score == 0)
                #expect(owner?.engine.state.longestRallyReturns == 0)
                if cycle < 9 {
                    frames(150, session: owner!, time: &time)
                    #expect(owner?.engine.state.phase == .playing)
                }
            }

            // Discarding the session models Choose Opponent/Home leaving this match.
            owner = nil
            #expect(observedSession == nil)
            #expect(observedScene == nil)
            pendingFrame?(time + 3_600)
        }

        #expect(preferences.best == 9_500)
        for id in BossID.allCases {
            #expect(preferences.bossRecord(for: id).wins == 0)
        }
    }

    @Test("Default session remains Arcade and its restart returns to the first wave")
    func arcadeModeRemainsDefault() {
        let (session, defaults, suite) = makeSession(id: .wall)
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcade = GameSession(preferences: session.preferences)
        #expect(arcade.mode == .arcade)
        #expect(arcade.engine.state.mode == .arcade)
        #expect(arcade.engine.state.stage == .wave(1))
        #expect(!arcade.engine.state.targets.isEmpty)
        arcade.engine.state.stage = .boss
        arcade.restart()
        #expect(arcade.mode == .arcade)
        #expect(arcade.engine.state.stage == .wave(1))
        #expect(!arcade.engine.state.targets.isEmpty)
    }

    private func winCurrentMatch(_ session: GameSession, time: inout Double) {
        // The engine resolves real points and emits the same record events as
        // gameplay. Only ball placement is controlled to avoid a balance oracle.
        for _ in 0..<3 {
            session.engine.state.phase = .playing
            session.engine.state.boss?.x = 18
            session.engine.state.boss?.movementTarget = 18
            session.engine.state.boss?.reactionRemaining = 1
            session.engine.state.ball = BallState(position: .init(x: 2, y: 43.9),
                                                  velocity: .init(x: 0, y: 46))
            frames(12, session: session, time: &time)
        }
        for _ in 0..<1_200 {
            if session.finished { break }
            frames(1, session: session, time: &time)
        }
        #expect(session.finished && session.engine.state.won)
    }

    @Test("Play Next follows the displayed five opponents, stores each win once and stops at Lobber")
    func playNextWholeRoster() {
        let (session, defaults, suite) = makeSession(id: .wall)
        defer { defaults.removePersistentDomain(forName: suite) }
        let order: [BossID] = [.wall, .banger, .poacher, .dinker, .lobber]
        #expect(BossRallyFlow.opponents == order)
        session.preferences.record(score: 8_000)
        session.beginIfActive(true)
        let sceneIdentity = ObjectIdentifier(session.scene)
        var time = 0.0
        session.scene.onFrame?(time)
        let matchScore = 3 * session.engine.tuning.bossPointScore + session.engine.tuning.bossVictoryBonus

        for index in order.indices {
            let id = order[index]
            #expect(session.mode == .bossRally(id))
            #expect(session.currentBossID == id)
            #expect(session.nextBossID == nil)
            #expect(!session.playNextBoss()) // A live match cannot be skipped.
            session.engine.state.currentBossMatchLongestRallyReturns = 7 + index
            session.engine.state.longestRallyReturns = 7 + index
            winCurrentMatch(session, time: &time)
            #expect(session.preferences.bossRecord(for: id) ==
                    BossRecord(wins: 1, bestScore: matchScore, longestRally: 7 + index))
            #expect(session.preferences.best == 8_000)
            frames(10, session: session, time: &time)
            #expect(session.preferences.bossRecord(for: id).wins == 1)

            guard index < order.count - 1 else {
                #expect(session.nextBossID == nil)
                #expect(!session.playNextBoss())
                #expect(session.finished)
                #expect(session.mode == .bossRally(.lobber))
                break
            }
            let next = order[index + 1]
            #expect(session.nextBossID == next)
            weak var retiredEngine = session.engine
            #expect(session.playNextBoss())
            #expect(retiredEngine == nil)
            #expect(ObjectIdentifier(session.scene) == sceneIdentity)
            #expect(session.scene.onFrame != nil)
            #expect(session.mode == .bossRally(next))
            #expect(session.engine.state.mode == .bossRally(next))
            #expect(session.currentBossID == next)
            #expect(!session.finished && !session.paused && !session.newBest)
            #expect(session.phase == .ready)
            #expect(session.score == 0 && session.playerRallyPoints == 0 && session.opponentRallyPoints == 0)
            #expect(session.engine.state.recoveriesRemaining == 0)
            #expect(session.engine.state.currentRallyReturns == 0)
            #expect(session.engine.state.longestRallyReturns == 0)
            #expect(session.engine.state.completedBossMatches.isEmpty)
            #expect(session.engine.state.playerX == CourtGeometry.centerX)
            #expect(session.engine.state.simulationTime == 0)
            #expect(!session.playNextBoss()) // A queued second tap cannot skip a boss.
            session.scene.onFrame?(time + 3_600)
            #expect(session.engine.state.simulationTime == 0) // Rebase the display clock.
            time += 3_600
        }
        #expect(order.allSatisfy { session.preferences.bossRecord(for: $0).wins == 1 })
    }

    @Test("Play Next resets before rematch, honors display inactivity, and retires on navigation")
    func nextRematchAndRetirement() {
        let (session, defaults, suite) = makeSession(id: .poacher)
        defer { defaults.removePersistentDomain(forName: suite) }
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        winCurrentMatch(session, time: &time)
        session.setActive(true, luminanceReduced: true)
        #expect(session.playNextBoss())
        #expect(session.mode == .bossRally(.dinker))
        #expect(session.paused && session.renderingPaused && !session.active)
        let inactive = session.engine.state
        frames(60, session: session, time: &time)
        session.resume()
        #expect(session.engine.state == inactive)
        session.setActive(true)
        #expect(session.paused)
        session.resume()
        #expect(!session.paused)
        #expect(session.engine.state.resumeCountdown == session.engine.tuning.resumeDuration)
        frames(200, session: session, time: &time)
        session.pause()
        let paused = session.engine.state
        frames(60, session: session, time: &time)
        #expect(session.engine.state == paused)
        session.restart()
        #expect(session.mode == .bossRally(.dinker))
        #expect(session.engine.state.bossID == .dinker)
        #expect(session.score == 0 && session.engine.state.recoveriesRemaining == 0)
        #expect(session.preferences.bossRecord(for: .poacher).wins == 1)
        #expect(session.preferences.bossRecord(for: .dinker).wins == 0)
        winCurrentMatch(session, time: &time)
        #expect(session.preferences.bossRecord(for: .dinker).wins == 1)
        #expect(session.nextBossID == .lobber)
        session.endPresentation()
        let retired = session.engine.state
        #expect(session.nextBossID == nil)
        #expect(!session.playNextBoss())
        session.restart()
        session.setActive(true)
        #expect(session.engine.state == retired)
        #expect(session.scene.onFrame == nil)
        #expect(!session.active && session.presentationEnded)
    }

    @Test("A loss offers no next opponent and retry stays with the current boss", arguments: BossID.allCases)
    func lossDoesNotAdvance(id: BossID) {
        let (session, defaults, suite) = makeSession(id: id)
        defer { defaults.removePersistentDomain(forName: suite) }
        session.beginIfActive(true)
        session.engine.state.phase = .playing
        session.engine.state.boss?.opponentPoints = 2
        session.engine.state.recoveriesRemaining = 0
        session.engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29),
                                              velocity: .init(x: 0, y: -26))
        var time = 0.0
        frames(4, session: session, time: &time)
        #expect(session.finished && !session.engine.state.won)
        #expect(session.nextBossID == nil)
        let result = session.engine.state
        #expect(!session.playNextBoss())
        #expect(session.engine.state == result)
        session.restart()
        #expect(session.mode == .bossRally(id))
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.playerRallyPoints == 0 && session.opponentRallyPoints == 0)
    }
}
