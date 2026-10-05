import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Sequential boss series")
struct BossSeriesTests {
    private let order: [BossID] = [.wall, .banger, .poacher]

    private func scoreWinningPoint(_ engine: GameEngine, for id: BossID) -> [GameEvent] {
        var events: [GameEvent] = []
        for _ in 0..<3 {
            engine.state.phase = .playing
            engine.state.boss?.x = 18
            engine.state.boss?.movementTarget = 18
            engine.state.boss?.reactionRemaining = 1
            engine.state.ball = BallState(position: .init(x: 2, y: 43.9),
                                          velocity: .init(x: 0, y: 46))
            events += advance(engine, seconds: 0.08)
        }
        return events
    }

    @Test("Boss Series starts at The Wall and advances through each real scoring collision")
    func sequentialWinsUseCoreCollisionEvents() throws {
        let engine = GameEngine(mode: .bossSeries, seed: 71)
        #expect(engine.state.mode == .bossSeries)
        #expect(engine.state.stage == .boss)
        #expect(engine.state.bossID == .wall)
        #expect(engine.state.targets.isEmpty)

        engine.state.longestRallyReturns = 11
        var allMatchEvents: [GameEvent] = []
        let expectedMatchScore = 3 * engine.tuning.bossPointScore + engine.tuning.bossVictoryBonus

        for index in order.indices {
            let id = order[index]
            engine.state.currentBossMatchLongestRallyReturns = 7
            engine.state.consecutivePlayerReturns = 20
            engine.state.recoveriesRemaining = 1
            let events = scoreWinningPoint(engine, for: id)
            allMatchEvents += events

            let ended = events.compactMap { event -> BossMatchResult? in
                guard case let .bossMatchEnded(result) = event else { return nil }
                return result
            }
            #expect(ended.count == 1)
            #expect(ended.first?.bossID == id)
            #expect(ended.first?.won == true)
            #expect(ended.first?.score == expectedMatchScore)
            #expect(ended.first?.longestRallyReturns == 7)
            #expect(engine.state.completedBossMatches.count == index + 1)
            #expect(engine.state.completedBossMatches.last == ended.first)

            if let next = order.dropFirst(index + 1).first {
                #expect(engine.state.phase == .ready)
                #expect(engine.state.bossID == next)
                #expect(engine.state.boss?.id == next)
                #expect(engine.state.boss?.points == 0)
                #expect(engine.state.boss?.opponentPoints == 0)
                #expect(engine.state.boss?.returnCount == 0)
                #expect(engine.state.boss?.lastShotPurpose == nil)
                #expect(engine.state.boss?.plannedReceivingX == nil)
                #expect(engine.state.boss?.predictedInterceptX == nil)
                #expect(engine.state.boss?.specialPhase == .idle)
                #expect(engine.state.boss?.specialRemaining == 0)
                #expect(engine.state.boss?.lateralVelocity == 0)
                #expect(engine.state.ball == nil)
                #expect(engine.state.currentRallyReturns == 0)
                #expect(engine.state.consecutivePlayerReturns == 0)
                #expect(engine.state.currentBossMatchLongestRallyReturns == 0)
                #expect(engine.state.recoveriesRemaining == 0)
                #expect(engine.state.longestRallyReturns == 11)
                #expect(engine.state.score == (index + 1) * expectedMatchScore)
                #expect(!events.contains(.bossDefeated))
            }
        }

        let allEnded = allMatchEvents.filter { if case .bossMatchEnded = $0 { return true }; return false }
        #expect(allEnded.count == 3)
        #expect(engine.state.completedBossMatches.map(\.bossID) == order)
        #expect(engine.state.completedBossMatches.allSatisfy { $0.won })
    }

    @Test("A loss ends the current boss match without advancing the series")
    func lossIsTerminalAndRecordedOnce() {
        let engine = GameEngine(mode: .bossSeries, seed: 99)
        engine.state.score = 1_300
        engine.state.longestRallyReturns = 9
        engine.state.currentBossMatchLongestRallyReturns = 6
        engine.state.recoveriesRemaining = 0
        engine.state.boss?.opponentPoints = 2
        engine.state.phase = .playing
        engine.state.ball = BallState(position: .init(x: 10, y: -0.29),
                                      velocity: .init(x: 0, y: -26))

        let events = advance(engine, seconds: 0.08)
        let results = events.compactMap { event -> BossMatchResult? in
            guard case let .bossMatchEnded(result) = event else { return nil }
            return result
        }

        #expect(results.count == 1)
        #expect(results.first?.bossID == .wall)
        #expect(results.first?.won == false)
        #expect(results.first?.score == 1_300)
        #expect(results.first?.longestRallyReturns == 6)
        #expect(engine.state.completedBossMatches == results)
        #expect(engine.state.phase == .results)
        #expect(engine.state.bossID == .wall)
        #expect(engine.state.completedBossMatches.count == 1)
        #expect(events.filter { if case .runEnded = $0 { return true }; return false }.count == 1)
        #expect(engine.update(delta: 0.1).isEmpty)
        #expect(engine.state.completedBossMatches.count == 1)
    }

    @Test("Reset cancels completed match history and replays the same first boss")
    func resetStartsFreshSeries() {
        let engine = GameEngine(mode: .bossSeries, seed: 15)
        _ = scoreWinningPoint(engine, for: .wall)
        #expect(engine.state.bossID == .banger)
        #expect(engine.state.completedBossMatches.count == 1)

        engine.state.consecutivePlayerReturns = 20
        engine.state.recoveriesRemaining = 1
        engine.reset()

        #expect(engine.state.mode == .bossSeries)
        #expect(engine.state.bossID == .wall)
        #expect(engine.state.stage == .boss)
        #expect(engine.state.completedBossMatches.isEmpty)
        #expect(engine.state.score == 0)
        #expect(engine.state.longestRallyReturns == 0)
        #expect(engine.state.consecutivePlayerReturns == 0)
        #expect(engine.state.recoveriesRemaining == 0)
        #expect(engine.state.boss?.points == 0)
        #expect(engine.state.boss?.opponentPoints == 0)
    }
}
