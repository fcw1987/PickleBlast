import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Repeated session and replay reliability")
@MainActor
struct ReliabilityStressTests {
    private func makeSession() -> (GameSession, UserDefaults, String) {
        let suite = "PickleBlast-reliability-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = GameSession(preferences: AppPreferences(storage: LocalStore(defaults: defaults)))
        return (session, defaults, suite)
    }

    private func advanceFrames(_ count: Int, session: GameSession, time: inout Double) {
        for _ in 0..<count {
            time += 1.0 / 120
            session.scene.onFrame?(time)
        }
    }

    @Test("Thirty-two result and replay cycles preserve one best score and a playable scene")
    func repeatedResultAndReplay() {
        let (session, defaults, suite) = makeSession()
        defer { defaults.removePersistentDomain(forName: suite) }
        session.beginIfActive(true)
        var time = 0.0

        for run in 1...32 {
            let resultScore = 1_000 + run * 125
            session.engine.state.phase = .playing
            session.engine.state.lives = 1
            session.engine.state.recoveriesRemaining = 0
            session.engine.state.score = resultScore
            session.engine.state.ball = BallState(
                position: .init(x: 19, y: -0.29), velocity: .init(x: 0, y: -26))

            advanceFrames(3, session: session, time: &time)
            #expect(session.finished)
            #expect(session.phase == .results)
            #expect(session.preferences.best == resultScore)

            session.restart()
            #expect(!session.finished && !session.paused)
            #expect(session.score == 0 && session.lives == 3)
            #expect(session.engine.state.stage == .wave(1))
            #expect(session.engine.state.boss == nil)
            #expect(session.scene.onFrame != nil)

            advanceFrames(150, session: session, time: &time)
            #expect(session.engine.state.phase == .playing)
            #expect(session.preferences.best == resultScore)
        }

        #expect(session.preferences.best == 5_000)
    }

    @Test("Thirty-two fresh sessions freeze cascades across inactivity and release scene callbacks")
    func repeatedSessionCreationBackgroundAndRelease() {
        for cycle in 0..<32 {
            let suite = "PickleBlast-reliability-release-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            var owner: GameSession? = GameSession(
                preferences: AppPreferences(storage: LocalStore(defaults: defaults)))
            weak var observedSession = owner
            weak var observedScene = owner?.scene
            let pendingFrame = owner?.scene.onFrame
            defer { defaults.removePersistentDomain(forName: suite) }

            owner?.beginIfActive(true)
            owner?.engine.state.phase = .celebration
            owner?.engine.state.phaseTimeRemaining = 2
            owner?.engine.state.celebration.update(delta: 0.2)

            var time = Double(cycle) * 10
            advanceFrames(3, session: owner!, time: &time)
            #expect(owner!.engine.state.celebration.activeCount > 0)

            owner?.setActive(false)
            let suspended = owner!.engine.state
            time += 3_600
            pendingFrame?(time)
            #expect(owner?.engine.state == suspended)

            owner?.setActive(true)
            #expect(owner?.paused == true)
            owner?.resume()
            var resumed = suspended
            resumed.isPaused = false
            resumed.resumeCountdown = owner!.engine.tuning.resumeDuration
            pendingFrame?(time) // First resumed frame rebases; it consumes no suspended time.
            #expect(owner?.engine.state == resumed)
            advanceFrames(150, session: owner!, time: &time)
            #expect(owner?.engine.state.resumeCountdown == 0)
            #expect(owner?.engine.state.phase == .celebration)
            #expect(owner!.engine.state.phaseTimeRemaining < suspended.phaseTimeRemaining)

            owner = nil
            #expect(observedSession == nil)
            #expect(observedScene == nil)
            pendingFrame?(time + 3_600)
        }
    }
}
