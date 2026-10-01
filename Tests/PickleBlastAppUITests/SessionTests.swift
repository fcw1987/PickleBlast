import Foundation
import Testing
@testable import PickleBlastAppUI
@testable import PickleBlastCore

@Suite("Host session lifecycle and input")
@MainActor
struct SessionTests {
    private func session() -> (GameSession, UserDefaults, String) {
        let suite = "PickleBlast-session-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(storage: LocalStore(defaults: defaults))
        return (GameSession(preferences: preferences), defaults, suite)
    }
    private func frames(_ count: Int, session: GameSession, time: inout Double) {
        for _ in 0..<count { time += 1.0 / 120; session.scene.onFrame?(time) }
    }

    @Test("Minimum, default and maximum Crown settings use exact slow linear gains",
          arguments: [(0.5, 0.075), (1.0, 0.150), (2.0, 0.300)])
    func exactCrownGain(setting: (Double, Double)) {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        game.preferences.sensitivity = setting.0
        game.beginIfActive(true)
        let start = game.engine.state.playerX
        game.setCrownPosition(game.crownPosition + 1)
        #expect(abs(game.engine.state.playerX - start - setting.1) < 0.000_001)
        let moved = game.engine.state.playerX
        game.crownVelocity(1_000)
        #expect(game.engine.state.playerX == moved)
        game.setCrownPosition(game.crownPosition - 0.25)
        #expect(abs(game.engine.state.playerX - moved + setting.1 * 0.25) < 0.000_001)
    }

    @Test("Disappearance, inactive wall time and 50 reappearances preserve a live frame callback")
    func repeatedViewRecovery() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        var time = 0.0
        game.beginIfActive(true)
        frames(160, session: game, time: &time)
        #expect(game.engine.state.phase == .playing)
        for _ in 0..<50 {
            let frozen = game.engine.state
            game.setActive(false) // RunView.onDisappear and inactive scenePhase path.
            #expect(game.scene.onFrame != nil)
            time += 3_600
            game.scene.onFrame?(time)
            #expect(game.engine.state.ball == frozen.ball)
            #expect(game.engine.state.score == frozen.score)
            #expect(game.engine.state.lives == frozen.lives)
            game.beginIfActive(true)
            #expect(game.paused)
            game.resume()
            game.scene.onFrame?(time)
            #expect(game.engine.state.ball == frozen.ball)
            frames(120, session: game, time: &time)
            #expect(game.engine.state.resumeCountdown == 0)
            // Dense ricochets can leave this repeated interruption in ready
            // after a legitimate miss. A ready ball remains nil while its timer
            // advances; that is not a frozen scene callback.
            #expect(game.engine.state.simulationTime > frozen.simulationTime)
            if frozen.ball != nil || game.engine.state.ball != nil {
                #expect(game.engine.state.ball != frozen.ball)
            } else {
                #expect(game.engine.state.phaseTimeRemaining < frozen.phaseTimeRemaining)
            }
            #expect(!game.finished)
        }
    }

    @Test("Bounded Crown binding and drag read the same position at both boundaries")
    func bindingReversalAndDrag() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        game.preferences.sensitivity = 2
        game.beginIfActive(true)
        for _ in 0..<20 { game.setCrownPosition(game.crownMaximum + 100) }
        #expect(game.crownPosition == game.crownMaximum)
        game.setCrownPosition(game.crownPosition - 0.1)
        #expect(abs(game.engine.state.playerX - (20 - game.engine.tuning.playerMargin - 0.03)) < 0.0001)
        for _ in 0..<20 { game.setCrownPosition(game.crownMinimum - 100) }
        game.setCrownPosition(game.crownPosition + 0.1)
        #expect(abs(game.engine.state.playerX - (game.engine.tuning.playerMargin + 0.03)) < 0.0001)
        let screenX = game.scene.courtProjection.screenPoint(for: .init(x: 13, y: game.engine.tuning.playerY + game.engine.tuning.ballRadius)).x
        game.drag(screenX: screenX)
        #expect(abs(game.crownPosition - 13 / game.crownGain) < 0.0001)
        game.setCrownPosition(game.crownPosition + 0.25)
        #expect(abs(game.engine.state.playerX - 13.075) < 0.0001)
    }

    @Test("Results persist once, and repeated replay restores a playable scene")
    func resultAndReplay() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sceneIdentity = ObjectIdentifier(game.scene)
        let engineIdentity = ObjectIdentifier(game.engine)
        game.beginIfActive(true)
        var time = 0.0
        for run in 0..<3 {
            game.engine.state.phase = .playing
            game.engine.state.recoveriesRemaining = 0 // Result persistence after all free recoveries.
            game.engine.state.lives = 1
            game.engine.state.score = 500 + run * 100
            game.engine.state.ball = BallState(position: .init(x: 19, y: -0.29), velocity: .init(x: 0, y: -26))
            frames(3, session: game, time: &time)
            #expect(game.finished)
            #expect(game.newBest)
            #expect(game.preferences.best == 500 + run * 100)
            game.restart()
            #expect(!game.finished && !game.paused)
            #expect(game.score == 0 && game.lives == 3)
            #expect(ObjectIdentifier(game.scene) == sceneIdentity)
            #expect(ObjectIdentifier(game.engine) == engineIdentity)
            #expect(game.scene.onFrame != nil)
            frames(160, session: game, time: &time)
            #expect(game.engine.state.phase == .playing)
        }
    }

    @Test("Phase transitions refresh Crown binding and expose the true-black cut")
    func semanticUpdates() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        game.beginIfActive(true)
        game.setCrownPosition(game.crownMinimum)
        game.engine.state.phase = .blackout
        game.engine.state.phaseTimeRemaining = 0.03
        var time = 0.0
        let revision = game.inputRevision
        frames(2, session: game, time: &time)
        #expect(game.phase == .blackout)
        frames(10, session: game, time: &time)
        #expect(game.phase == .ready)
        #expect(game.engine.state.playerX == 10)
        #expect(game.inputRevision > revision)
    }

    @Test("An initially reduced display cannot start, resume, restart, or accept input")
    func initialReducedLuminance() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        game.beginIfActive(true, luminanceReduced: true)
        #expect(!game.active && game.paused && game.renderingPaused)
        let frozen = game.engine.state
        var time = 3_600.0
        game.resume()
        game.setCrownPosition(game.crownMaximum)
        game.drag(screenX: 0)
        frames(120, session: game, time: &time)
        #expect(game.engine.state == frozen)
        game.restart()
        #expect(!game.active && game.paused && game.renderingPaused)
        #expect(game.engine.state.simulationTime == 0)

        game.setActive(true, luminanceReduced: false)
        #expect(game.active && game.paused && game.renderingPaused)
        game.resume()
        #expect(!game.paused && !game.renderingPaused)
        game.scene.onFrame?(time)
        #expect(game.engine.state.simulationTime == 0)
        #expect(game.engine.state.resumeCountdown == game.engine.tuning.resumeDuration)
        frames(160, session: game, time: &time)
        #expect(game.engine.state.resumeCountdown == 0)
        #expect(game.engine.state.lives == 3)
    }

    @Test("Reduced luminance during resume countdown freezes the run until explicit eligible resume")
    func luminanceInterruptionDuringCountdown() {
        let (game, defaults, suite) = session()
        defer { defaults.removePersistentDomain(forName: suite) }
        game.beginIfActive(true)
        game.engine.state.phase = .playing
        game.engine.state.ball = BallState(position: .init(x: 10, y: 20),
                                           velocity: .init(x: 0, y: -26))
        var time = 0.0
        game.pause()
        game.resume()
        frames(30, session: game, time: &time)
        #expect(game.engine.state.resumeCountdown > 0)
        let ball = game.engine.state.ball

        game.setActive(true, luminanceReduced: true)
        let frozen = game.engine.state
        time += 3_600
        game.scene.onFrame?(time)
        game.beginIfActive(true, luminanceReduced: true)
        game.resume()
        frames(120, session: game, time: &time)
        #expect(game.engine.state == frozen)
        #expect(game.renderingPaused)

        // Brightening is insufficient while the scene remains inactive.
        game.setActive(false, luminanceReduced: false)
        game.resume()
        #expect(game.paused && !game.active)
        game.setActive(true, luminanceReduced: false)
        #expect(game.paused)
        game.resume()
        game.scene.onFrame?(time)
        #expect(game.engine.state.ball == ball)
        #expect(game.engine.state.resumeCountdown == game.engine.tuning.resumeDuration)
        frames(30, session: game, time: &time)
        #expect(game.engine.state.ball == ball)
        frames(100, session: game, time: &time)
        #expect(game.engine.state.resumeCountdown == 0)
        #expect(game.engine.state.ball != ball)
        #expect(game.engine.state.lives == 3 && game.engine.state.score == 0)
    }

    @Test("An escaped scene callback does not retain a dismissed session or its scene")
    func sessionAndSceneRelease() {
        let suite = "PickleBlast-session-release-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(storage: LocalStore(defaults: defaults))
        var owner: GameSession? = GameSession(preferences: preferences)
        weak var observedSession = owner
        weak var observedScene = owner?.scene
        let callback = owner?.scene.onFrame
        owner?.beginIfActive(true)
        callback?(0)
        callback?(1.0 / 30)
        owner?.setActive(false)
        owner = nil
        #expect(observedSession == nil)
        #expect(observedScene == nil)
        // A pending display callback is harmless after the owner disappears.
        callback?(3_600)
    }
}
