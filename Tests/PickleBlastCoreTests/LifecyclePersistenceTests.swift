import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Lifecycle, persistence, and bounded timing")
struct LifecyclePersistenceTests {
    @Test("Pause freezes every phase, all timers, input, score, lives and effects", arguments: [GamePhase.ready, .playing, .impact, .celebration, .blackout, .results])
    func everyPhaseFreezes(phase: GamePhase) {
        let engine = activeEngine()
        engine.state.phase = phase
        engine.state.phaseTimeRemaining = 0.2
        engine.state.ball = BallState(position: .init(x: 18, y: 0.1), velocity: .init(x: 0, y: -46))
        engine.state.celebration.update(delta: 0.1)
        engine.pause()
        let frozen = engine.state
        for _ in 0..<20 {
            #expect(engine.update(delta: 60).isEmpty)
            engine.movePlayer(crownDelta: 1, sensitivity: 1)
            engine.setPlayerX(2)
        }
        #expect(engine.state == frozen)
    }

    @Test("Resume gives a countdown and does not consume suspended time")
    func resumeCountdown() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 20), velocity: .init(x: 0, y: -26))
        engine.pause()
        _ = engine.update(delta: 3_600)
        engine.resume()
        #expect(!engine.state.isPaused)
        #expect(engine.state.resumeCountdown > 0)
        let before = engine.state.ball
        let events = advance(engine, seconds: engine.tuning.resumeDuration / 2)
        #expect(engine.state.ball == before)
        #expect(events.isEmpty)
        _ = advance(engine, seconds: engine.tuning.resumeDuration)
        #expect(engine.state.resumeCountdown == 0)
        #expect(try #require(engine.state.ball).position.y < 20)
        #expect(engine.state.lives == 3)
    }

    @Test("Repeated interruptions during the countdown never advance the ball")
    func interruptionsDuringCountdown() {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 20), velocity: .init(x: 0, y: -26))
        let start = engine.state.ball
        for _ in 0..<50 {
            engine.pause()
            let frozen = engine.state
            #expect(engine.update(delta: 10_000).isEmpty)
            #expect(engine.state == frozen)
            engine.resume()
            _ = advance(engine, seconds: 0.2)
            #expect(engine.state.ball == start)
        }
        #expect(engine.state.score == 0)
        #expect(engine.state.lives == 3)
        #expect(engine.state.rallyTime == 0)
    }

    @Test("Fifty complete pause-resume cycles freeze then resume active play")
    func repeatedInterruptionRecovery() throws {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 20), velocity: .init(x: 0, y: -26))
        for _ in 0..<50 {
            engine.pause()
            let frozen = engine.state
            #expect(engine.update(delta: 10_000).isEmpty)
            #expect(engine.state == frozen)
            engine.resume()
            var countdownSteps = 0
            while engine.state.resumeCountdown > 0 && countdownSteps < 200 {
                #expect(engine.update(delta: engine.tuning.fixedStep).isEmpty)
                #expect(engine.state.ball == frozen.ball)
                #expect(engine.state.rallyTime == frozen.rallyTime)
                countdownSteps += 1
            }
            #expect(engine.state.resumeCountdown == 0)
            #expect(countdownSteps >= 102)
            _ = engine.update(delta: engine.tuning.fixedStep)
            let before = try #require(frozen.ball)
            let after = try #require(engine.state.ball)
            expectNear(after.position.y, before.position.y - 26 * engine.tuning.fixedStep)
            expectNear(engine.state.rallyTime, frozen.rallyTime + engine.tuning.fixedStep)
        }
        expectNear(engine.state.ball?.position.y ?? 0, 20 - 26 * 50 * engine.tuning.fixedStep)
        #expect(engine.state.score == 0)
        #expect(engine.state.lives == 3)
    }

    @Test("Fifty complete pause-resume cycles also freeze and resume the cascade")
    func repeatedCelebrationRecovery() {
        let engine = activeEngine()
        engine.state.phase = .celebration
        engine.state.phaseTimeRemaining = engine.tuning.celebrationDuration
        for _ in 0..<50 {
            engine.pause()
            let frozen = engine.state
            #expect(engine.update(delta: 10_000).isEmpty)
            #expect(engine.state == frozen)
            engine.resume()
            var countdownSteps = 0
            while engine.state.resumeCountdown > 0 && countdownSteps < 200 {
                #expect(engine.update(delta: engine.tuning.fixedStep).isEmpty)
                #expect(engine.state.celebration == frozen.celebration)
                #expect(engine.state.phaseTimeRemaining == frozen.phaseTimeRemaining)
                countdownSteps += 1
            }
            #expect(engine.state.resumeCountdown == 0)
            _ = engine.update(delta: engine.tuning.fixedStep)
            #expect(engine.state.celebration != frozen.celebration)
            expectNear(engine.state.phaseTimeRemaining, frozen.phaseTimeRemaining - engine.tuning.fixedStep)
        }
        #expect(engine.state.celebration.activeCount >= 24)
        #expect(engine.state.phase == .celebration)
        #expect(engine.state.score == 0)
        #expect(engine.state.lives == 3)
    }

    @Test("Invalid time deltas do not advance simulation", arguments: [0.0, -1, Double.nan, .infinity, -.infinity])
    func invalidTime(delta: Double) {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 20), velocity: .init(x: 0, y: -26))
        let before = engine.state
        #expect(engine.update(delta: delta).isEmpty)
        #expect(engine.state == before)
    }

    @Test("Huge frame deltas process only a bounded amount of work")
    func boundedCatchup() {
        let engine = activeEngine()
        engine.state.ball = BallState(position: .init(x: 10, y: 20), velocity: .init(x: 0, y: -26))
        _ = engine.update(delta: 3_600)
        #expect(engine.state.simulationTime <= engine.tuning.maximumFrameDelta + 0.000_001)
        #expect(engine.state.ball?.position.y ?? 0 >= 17)
        #expect(engine.state.lives == 3)
    }

    @Test("Fixed-step outcomes agree at 30 and 60 rendered frames per second")
    func renderRateIndependence() throws {
        let thirty = activeEngine()
        let sixty = activeEngine()
        let ball = BallState(position: .init(x: 8, y: 20), velocity: .init(x: 6, y: 25))
        thirty.state.ball = ball
        sixty.state.ball = ball
        let firstEvents = advance(thirty, seconds: 1, frame: 1.0 / 30)
        let secondEvents = advance(sixty, seconds: 1, frame: 1.0 / 60)
        let first = try #require(thirty.state.ball)
        let second = try #require(sixty.state.ball)
        expectNear(first.position.x, second.position.x)
        expectNear(first.position.y, second.position.y)
        #expect(first.velocity == second.velocity)
        #expect(firstEvents == secondEvents)
    }

    @Test("Fresh run resets all prior gameplay and celebration state")
    func freshRun() {
        let engine = activeEngine(boss: true)
        engine.state.score = 9_000
        engine.state.lives = 1
        engine.state.won = true
        engine.state.phase = .results
        engine.state.boss?.points = 3
        engine.state.celebration.update(delta: 0.1)
        engine.pause()
        engine.reset(seed: 42)
        #expect(engine.state.phase == .ready)
        #expect(engine.state.stage == .wave(1))
        #expect(engine.state.score == 0)
        #expect(engine.state.lives == 3)
        #expect(!engine.state.won && !engine.state.isPaused)
        #expect(engine.state.boss == nil)
        #expect(engine.state.ball == nil)
        #expect(engine.state.targets == AuthoredWaves.targets(for: 1))
        #expect(engine.state.celebration.activeCount == 0)
        expectNear(engine.state.playerX, 10)
    }

    @Test("A fresh rally launches toward the player without a firing input")
    func automaticIncomingLaunch() throws {
        let engine = GameEngine(seed: 42)
        _ = advance(engine, seconds: engine.tuning.readyDuration + 0.05)
        #expect(engine.state.phase == .playing)
        #expect(try #require(engine.state.ball).velocity.y < 0)
        #expect(engine.state.score == 0)
    }

    @Test("Personal best persists and only strictly greater scores are new records")
    func personalBestPersistence() throws {
        let name = "PickleBlastTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = LocalStore(defaults: defaults)
        #expect(first.bestScore == 0)
        #expect(!first.record(score: -5))
        #expect(first.record(score: 1_250))
        #expect(!first.record(score: 1_250))
        #expect(!first.record(score: 100))
        let reloaded = LocalStore(defaults: defaults)
        #expect(reloaded.bestScore == 1_250)
        #expect(reloaded.record(score: 2_000))
        #expect(first.bestScore == 2_000)
    }

    @Test("Sensitivity and haptic preferences persist locally and sanitize values")
    func settingsPersistence() throws {
        let name = "PickleBlastSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = LocalStore(defaults: defaults)
        #expect(first.settings == GameSettings())
        first.settings = GameSettings(crownSensitivity: 1.7, hapticsEnabled: false)
        let reloaded = LocalStore(defaults: defaults)
        expectNear(reloaded.settings.crownSensitivity, 1.7)
        #expect(!reloaded.settings.hapticsEnabled)
        #expect(GameSettings(crownSensitivity: .nan).crownSensitivity == 1)
        #expect(GameSettings(crownSensitivity: -1).crownSensitivity == GameSettings.minimumSensitivity)
        #expect(GameSettings(crownSensitivity: 100).crownSensitivity == GameSettings.maximumSensitivity)
        expectNear(GameSettings(crownSensitivity: GameSettings.minimumSensitivity).effectiveCrownGain, 0.075)
        expectNear(GameSettings().effectiveCrownGain, 0.150)
        expectNear(GameSettings(crownSensitivity: GameSettings.maximumSensitivity).effectiveCrownGain, 0.300)
        #expect(GameSettings(crownSensitivity: GameSettings.minimumSensitivity).oldMinimumPercentage == 15)
        #expect(GameSettings().oldMinimumPercentage == 30)
        #expect(GameSettings(crownSensitivity: GameSettings.maximumSensitivity).oldMinimumPercentage == 60)
    }

    @Test("Legacy sensitivity values clamp once without compounding across reloads")
    func legacySensitivityMigration() throws {
        let name = "PickleBlastLegacySettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(2.5, forKey: "pickleblast.sensitivity")
        defaults.set(false, forKey: "pickleblast.haptics")
        let first = LocalStore(defaults: defaults)
        #expect(first.settings.crownSensitivity == 2)
        #expect(first.settings.effectiveCrownGain == 0.3)
        first.settings = first.settings
        let second = LocalStore(defaults: defaults)
        #expect(second.settings.crownSensitivity == 2)
        #expect(second.settings.effectiveCrownGain == 0.3)
        #expect(!second.settings.hapticsEnabled)
    }
}
