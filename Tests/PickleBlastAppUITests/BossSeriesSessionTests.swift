import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Boss Series session records")
@MainActor
struct BossSeriesSessionTests {
    private let order: [BossID] = [.wall, .banger, .poacher]

    private func makeSession() -> (GameSession, UserDefaults, String) {
        let suite = "PickleBlast-boss-series-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(storage: LocalStore(defaults: defaults))
        return (GameSession(preferences: preferences, mode: .bossSeries), defaults, suite)
    }

    private func frames(_ count: Int, session: GameSession, time: inout Double) {
        for _ in 0..<count {
            time += 1.0 / 120
            session.scene.onFrame?(time)
        }
    }

    private func scoreWinningMatch(_ session: GameSession, for id: BossID, time: inout Double) {
        for _ in 0..<3 {
            session.engine.state.phase = .playing
            session.engine.state.boss?.x = 18
            session.engine.state.boss?.movementTarget = 18
            session.engine.state.boss?.reactionRemaining = 1
            session.engine.state.ball = BallState(position: .init(x: 2, y: 43.9),
                                                  velocity: .init(x: 0, y: 46))
            frames(12, session: session, time: &time)
        }
    }

    @Test("Each resolved boss win records once, in sequence, without changing the Arcade best")
    func everyMatchRecordIsIsolated() {
        let (session, defaults, suite) = makeSession()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(session.preferences.record(score: 8_000))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time) // Establish the host frame clock.
        let expectedMatchScore = 3 * session.engine.tuning.bossPointScore
            + session.engine.tuning.bossVictoryBonus

        for index in order.indices {
            let id = order[index]
            session.engine.state.currentBossMatchLongestRallyReturns = 4 + index
            session.engine.state.longestRallyReturns = max(9, 4 + index)
            scoreWinningMatch(session, for: id, time: &time)

            let record = session.preferences.bossRecord(for: id)
            #expect(record.wins == 1)
            #expect(record.bestScore == expectedMatchScore)
            #expect(record.longestRally == 4 + index)
            #expect(session.engine.state.completedBossMatches.count == index + 1)
            #expect(session.preferences.best == 8_000)
            #expect(session.engine.state.bossID == (order.dropFirst(index + 1).first ?? .poacher))

            // Extra display frames after an event cannot persist it again.
            frames(8, session: session, time: &time)
            #expect(session.preferences.bossRecord(for: id).wins == 1)
        }

        #expect(session.engine.state.completedBossMatches.map(\.bossID) == order)
        #expect(session.engine.state.completedBossMatches.allSatisfy { $0.won })
        #expect(session.finished == false) // Final match still receives its victory cascade.
        #expect(session.preferences.bossRecord(for: .wall).wins == 1)
        #expect(session.preferences.bossRecord(for: .banger).wins == 1)
        #expect(session.preferences.bossRecord(for: .poacher).wins == 1)
        #expect(session.preferences.best == 8_000)
    }

    @Test("Series new-best feedback survives a final match below its saved record")
    func newBestSurvivesLaterUnimprovedMatch() {
        let (session, defaults, suite) = makeSession()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(session.preferences.record(score: 8_000))
        #expect(session.preferences.recordBoss(id: .poacher, won: true,
                                               score: 9_000, longestRally: 20))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        let expectedMatchScore = 3 * session.engine.tuning.bossPointScore
            + session.engine.tuning.bossVictoryBonus

        for id in order {
            scoreWinningMatch(session, for: id, time: &time)
        }

        #expect(session.engine.state.completedBossMatches.map(\.bossID) == order)
        #expect(session.preferences.bossRecord(for: .wall).bestScore == expectedMatchScore)
        #expect(session.preferences.bossRecord(for: .banger).bestScore == expectedMatchScore)
        #expect(session.preferences.bossRecord(for: .poacher).bestScore == 9_000)
        #expect(session.preferences.bossRecord(for: .poacher).wins == 2)
        #expect(session.newBest)
        #expect(session.preferences.best == 8_000)
        #expect(!session.finished) // Feedback remains available through the final cascade.
    }

    @Test("Losing the first match stores a loss once and replay restarts from The Wall")
    func lossAndReplayResetGeneration() {
        let (session, defaults, suite) = makeSession()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(session.preferences.record(score: 6_000))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        session.engine.state.score = 900
        session.engine.state.currentBossMatchLongestRallyReturns = 8
        session.engine.state.longestRallyReturns = 8
        session.engine.state.recoveriesRemaining = 0
        session.engine.state.boss?.opponentPoints = 2
        session.engine.state.phase = .playing
        session.engine.state.ball = BallState(position: .init(x: 10, y: -0.29),
                                              velocity: .init(x: 0, y: -26))
        frames(12, session: session, time: &time)

        #expect(session.finished)
        #expect(session.engine.state.phase == .results)
        #expect(session.engine.state.bossID == .wall)
        #expect(session.engine.state.completedBossMatches.count == 1)
        #expect(session.engine.state.completedBossMatches[0].won == false)
        #expect(session.preferences.bossRecord(for: .wall).wins == 0)
        #expect(session.preferences.bossRecord(for: .wall).bestScore == 900)
        #expect(session.preferences.bossRecord(for: .wall).longestRally == 8)
        #expect(session.preferences.bossRecord(for: .banger) == BossRecord())
        #expect(session.preferences.bossRecord(for: .poacher) == BossRecord())
        #expect(session.preferences.best == 6_000)

        frames(12, session: session, time: &time)
        #expect(session.preferences.bossRecord(for: .wall).wins == 0)
        session.restart()

        #expect(!session.finished)
        #expect(session.mode == .bossSeries)
        #expect(session.engine.state.mode == .bossSeries)
        #expect(session.engine.state.bossID == .wall)
        #expect(session.engine.state.completedBossMatches.isEmpty)
        #expect(session.engine.state.score == 0)
        #expect(session.engine.state.longestRallyReturns == 0)
        #expect(session.preferences.bossRecord(for: .wall).wins == 0)
        #expect(session.preferences.best == 6_000)
    }
}
