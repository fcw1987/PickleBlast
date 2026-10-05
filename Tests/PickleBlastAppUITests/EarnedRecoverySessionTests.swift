import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Earned-save session lifecycle")
@MainActor
struct EarnedRecoverySessionTests {
    private func frames(_ count: Int, _ session: GameSession, time: inout Double) {
        for _ in 0..<count {
            time += 1.0 / 120
            session.scene.onFrame?(time)
        }
    }

    private func returnBall(_ session: GameSession, time: inout Double) {
        session.engine.state.phase = .playing
        session.engine.state.ball = BallState(position: .init(x: 10, y: 3), velocity: .init(x: 0, y: -26))
        frames(4, session, time: &time)
    }

    @Test("Nineteen returns survive interruption, twentieth earns a save, consumption cannot duplicate it")
    func interruptionAndConsumption() {
        let suite = "PickleBlast-earned-session-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GameSession(preferences: AppPreferences(storage: LocalStore(defaults: defaults)),
                                  mode: .bossRally(.lobber))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        #expect(session.engine.state.recoveriesRemaining == 0)
        for _ in 1...19 { returnBall(session, time: &time) }
        #expect(session.engine.state.consecutivePlayerReturns == 19)
        #expect(session.engine.state.recoveriesRemaining == 0)

        session.setActive(true, luminanceReduced: true)
        let paused = session.engine.state
        time += 3_600
        session.scene.onFrame?(time)
        #expect(session.engine.state == paused)
        session.setActive(true)
        session.resume()
        session.scene.onFrame?(time)
        frames(103, session, time: &time)
        #expect(session.engine.state.consecutivePlayerReturns == 19)
        #expect(session.engine.state.recoveriesRemaining == 0)
        returnBall(session, time: &time)
        #expect(session.engine.state.consecutivePlayerReturns == 20)
        #expect(session.engine.state.recoveriesRemaining == 1)

        session.engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29), velocity: .init(x: 0, y: -26))
        frames(4, session, time: &time)
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.consecutivePlayerReturns == 0)
        #expect(session.opponentRallyPoints == 0 && session.phase == .ready)
        session.pause()
        session.resume()
        session.scene.onFrame?(time)
        frames(103, session, time: &time)
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.consecutivePlayerReturns == 0)
    }

    @Test("A won match banks one save until Play Next; next boss and rematch both start empty")
    func nextAndRematchResetBank() {
        let suite = "PickleBlast-earned-next-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GameSession(preferences: AppPreferences(storage: LocalStore(defaults: defaults)),
                                  mode: .bossRally(.wall))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        for _ in 1...20 { returnBall(session, time: &time) }
        #expect(session.engine.state.recoveriesRemaining == 1)
        for _ in 1...3 {
            session.engine.state.phase = .playing
            session.engine.state.boss?.x = 2
            session.engine.state.boss?.movementTarget = 2
            session.engine.state.ball = BallState(position: .init(x: 18, y: 43.9), velocity: .init(x: 0, y: 26))
            frames(4, session, time: &time)
        }
        for _ in 0..<800 {
            if session.finished { break }
            frames(1, session, time: &time)
        }
        #expect(session.finished && session.engine.state.won)
        #expect(session.engine.state.recoveriesRemaining == 1)
        #expect(session.engine.state.consecutivePlayerReturns == 0)
        #expect(session.preferences.bossRecord(for: .wall).longestRally == 20)
        #expect(session.playNextBoss())
        #expect(session.mode == .bossRally(.banger))
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.consecutivePlayerReturns == 0)
        #expect(!session.playNextBoss())
        session.scene.onFrame?(time)
        for _ in 1...20 { returnBall(session, time: &time) }
        #expect(session.engine.state.recoveriesRemaining == 1)
        session.restart()
        #expect(session.mode == .bossRally(.banger))
        #expect(session.engine.state.recoveriesRemaining == 0)
        #expect(session.engine.state.consecutivePlayerReturns == 0)
        #expect(session.preferences.bossRecord(for: .wall).longestRally == 20)
    }
}
