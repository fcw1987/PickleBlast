import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Independent recovery session review")
@MainActor
struct RecoverySessionReviewTests {
    @Test("Session publishes free recovery and charged loss without erasing progress or replenishing on interruption")
    func recoveryPublicationAndInterruption() {
        let suite = "PickleBlast-recovery-session-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GameSession(preferences: AppPreferences(storage: LocalStore(defaults: defaults)))
        session.beginIfActive(true)
        var time = 0.0
        session.scene.onFrame?(time)
        session.engine.state.score = 725
        let targets = session.engine.state.targets
        for miss in 1...3 {
            session.engine.state.phase = .playing
            session.engine.state.targetChain = 5
            session.engine.state.ball = BallState(position: .init(x: 0.3, y: -0.29), velocity: .init(x: 0, y: -26))
            time += 1.0 / 30
            session.scene.onFrame?(time)
            #expect(session.phase == .ready)
            #expect(session.lives == (miss <= 2 ? 3 : 2))
            #expect(session.score == 725)
            #expect(session.engine.state.targetChain == 0)
            #expect(session.engine.state.recoveriesRemaining == max(0, 2 - miss))
            #expect(session.engine.state.targets == targets)
            #expect(!session.finished)
            if miss == 1 {
                session.setActive(true, luminanceReduced: true)
                let frozen = session.engine.state
                time += 3_600
                session.scene.onFrame?(time)
                #expect(session.engine.state == frozen)
                session.setActive(true)
                #expect(session.paused)
                session.resume()
                session.scene.onFrame?(time) // Rebase after waking, consume no background time.
                #expect(session.engine.state.phaseTimeRemaining == frozen.phaseTimeRemaining)
                for _ in 0..<104 {
                    time += 1.0 / 120
                    session.scene.onFrame?(time)
                }
                #expect(session.engine.state.resumeCountdown == 0)
                #expect(session.engine.state.recoveriesRemaining == 1)
                #expect(session.engine.state.targets == targets)
            }
        }
    }

}
