import Foundation
import Combine
import SpriteKit
import PickleBlastCore
import PickleBlastRendering
#if os(watchOS)
import WatchKit
#endif

/// One displayed order for individual matches and the explicit Play Next action.
/// The legacy three-match series keeps its separate internal run plan.
enum BossRallyFlow {
    static let opponents: [BossID] = [.wall, .banger, .poacher, .dinker, .lobber]

    static func next(after boss: BossID) -> BossID? {
        guard let index = opponents.firstIndex(of: boss),
              opponents.indices.contains(index + 1) else { return nil }
        return opponents[index + 1]
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private let storage: LocalStore
    @Published var sensitivity: Double { didSet { save() } }
    @Published var haptics: Bool { didSet { save() } }
    @Published private(set) var best: Int
    @Published private(set) var bossRecords: [BossID: BossRecord]
    #if DEBUG
    @Published var diagnostics = false
    #endif

    init(storage: LocalStore = LocalStore()) {
        self.storage = storage
        sensitivity = storage.settings.crownSensitivity
        haptics = storage.settings.hapticsEnabled
        best = storage.bestScore
        bossRecords = Dictionary(uniqueKeysWithValues: BossID.allCases.map { ($0, storage.bossRecord(for: $0)) })
    }
    private func save() {
        storage.settings = GameSettings(crownSensitivity: sensitivity, hapticsEnabled: haptics)
    }
    @discardableResult func record(score: Int) -> Bool {
        let isNewBest = storage.record(score: score)
        best = storage.bestScore
        return isNewBest
    }
    func bossRecord(for id: BossID) -> BossRecord { bossRecords[id] ?? BossRecord() }
    @discardableResult func recordBoss(id: BossID, won: Bool, score: Int, longestRally: Int) -> Bool {
        let newBest = storage.recordBoss(id: id, won: won, score: score, longestRally: longestRally)
        bossRecords[id] = storage.bossRecord(for: id)
        return newBest
    }
}

/// The scene drives this session. SwiftUI observes only input and semantic changes.
@MainActor
final class GameSession: ObservableObject {
    private(set) var engine: GameEngine
    let scene: PickleBlastScene
    let preferences: AppPreferences
    var mode: GameMode { engine.mode }
    @Published private(set) var paused = false
    // True only while the scene is active and the display is not luminance reduced.
    @Published private(set) var active = false
    @Published private(set) var finished = false
    @Published private(set) var presentationEnded = false
    @Published private(set) var newBest = false
    @Published private(set) var inputRevision = 0
    @Published private(set) var score = 0
    @Published private(set) var lives = 3
    @Published private(set) var playerRallyPoints = 0
    @Published private(set) var opponentRallyPoints = 0
    @Published private(set) var currentBossID: BossID = .wall
    @Published private(set) var phase: GamePhase = .ready
    #if DEBUG
    private var validation = DebugValidation()
    private var validationFrames = 0
    private var validationElapsed = 0.0
    private var validationIntervals: [Double] = []
    private var validationLongFrames = 0
    #endif
    private var lastFrame: TimeInterval?
    private var recordedBossMatches = 0
    private var feedbackPolicy = GameplayFeedbackPolicy()

    /// Sanitized direct linear gain. Crown velocity is retained only for the
    /// optional diagnostics readout and never amplifies movement.
    var crownGain: Double { GameSettings(crownSensitivity: preferences.sensitivity).effectiveCrownGain }
    var crownPosition: Double { engine.state.playerX / crownGain }
    var crownMinimum: Double { engine.tuning.playerMargin / crownGain }
    var crownMaximum: Double { (CourtGeometry.width - engine.tuning.playerMargin) / crownGain }
    var renderingPaused: Bool { !active || paused || finished }
    var nextBossID: BossID? {
        guard finished, !presentationEnded, engine.state.won,
              case let .bossRally(id) = mode else { return nil }
        return BossRallyFlow.next(after: id)
    }

    init(preferences: AppPreferences, mode: GameMode = .arcade) {
        self.preferences = preferences
        #if DEBUG
        engine = GameEngine(mode: mode, seed: DebugValidation.seed)
        let sceneStart = ProcessInfo.processInfo.systemUptime
        #else
        engine = GameEngine(mode: mode)
        #endif
        currentBossID = engine.state.bossID
        scene = PickleBlastScene(size: CGSize(width: 211, height: 240), tuning: engine.tuning)
        scene.onFrame = { [weak self] time in self?.frame(time) }
        scene.render(state: engine.state, events: [], delta: 0)
        #if DEBUG
        DebugValidation.trackLifetime(of: self)
        if DebugValidation.startsRun {
            DebugValidation.log("VALIDATION SCENE_INIT milliseconds=\((ProcessInfo.processInfo.systemUptime - sceneStart) * 1_000) mode=\(mode)")
        }
        #endif
    }

    func resize(_ size: CGSize, safeTop: CGFloat = 28, safeBottom: CGFloat = 8,
                safeLeading: CGFloat = 0, safeTrailing: CGFloat = 0) {
        guard size.width > 0, size.height > 0 else { return }
        scene.setViewport(size, safeTop: safeTop, safeBottom: safeBottom,
                          safeLeading: safeLeading, safeTrailing: safeTrailing)
        scene.render(state: engine.state, events: [], delta: 0)
        #if DEBUG
        if DebugValidation.startsRun {
            DebugValidation.log("PRESENTATION viewport=\(size.width)x\(size.height) safe=\(safeTop),\(safeBottom),\(safeLeading),\(safeTrailing)")
        }
        #endif
    }

    func setCrownPosition(_ value: Double) {
        guard active, !paused, !finished, value.isFinite else { return }
        // A bounded binding reads the actual clamped position after every input.
        // There is no separate requested position to accumulate beyond a wall.
        let requested = value * crownGain
        engine.movePlayer(crownDelta: requested - engine.state.playerX, sensitivity: 1)
        inputRevision &+= 1
        scene.render(state: engine.state, events: [], delta: 0)
    }

    func crownVelocity(_ velocity: Double) {
        guard active, !paused, !finished else { return }
        engine.recordCrownVelocity(velocity)
    }

    func drag(screenX: Double) {
        guard active, !paused, !finished else { return }
        guard screenX.isFinite else { return }
        engine.setPlayerX(scene.courtX(forViewX: screenX))
        inputRevision &+= 1
        scene.render(state: engine.state, events: [], delta: 0)
    }

    func setActive(_ isActive: Bool, luminanceReduced: Bool = false) {
        guard !presentationEnded else { active = false; lastFrame = nil; return }
        active = isActive && !luminanceReduced
        lastFrame = nil
        if !active && !finished { pause() }
        #if DEBUG
        // Explicit evidence launches opt into starting once the display activates.
        // Ordinary user runs always retain their explicit Resume requirement.
        if active && DebugValidation.startsRun {
            engine.resume(); paused = false
            if DebugValidation.controls {
                while engine.state.resumeCountdown > 0 { _ = engine.update(delta: engine.tuning.maximumFrameDelta) }
            }
        }
        #endif
        // Returning to an eligible display intentionally leaves an ordinary run paused.
    }

    func beginIfActive(_ isActive: Bool, luminanceReduced: Bool = false) {
        setActive(isActive, luminanceReduced: luminanceReduced)
    }

    /// Stop callbacks before permanent navigation. The native host explicitly
    /// detaches its scene when dismantled; interruptions preserve this session
    /// and its callback so the existing run can resume.
    func endPresentation() {
        setActive(false)
        scene.onFrame = nil
        presentationEnded = true
    }

    func pause() {
        guard !finished else { return }
        engine.pause()
        paused = true
        lastFrame = nil
    }

    func resume() {
        guard active, paused, !finished else { return }
        lastFrame = nil
        engine.resume()
        paused = false
        inputRevision &+= 1
    }

    func restart() {
        guard !presentationEnded else { return }
        engine.reset()
        resetMatchPresentation()
    }

    /// Each opponent is an independent match with its own record. Reuse the
    /// scene and input surface, while a fresh engine owns the next encounter.
    @discardableResult
    func playNextBoss() -> Bool {
        guard let nextBossID else { return false }
        #if DEBUG
        engine = GameEngine(mode: .bossRally(nextBossID), tuning: engine.tuning,
                            seed: DebugValidation.seed)
        #else
        engine = GameEngine(mode: .bossRally(nextBossID), tuning: engine.tuning)
        #endif
        resetMatchPresentation()
        return true
    }

    private func resetMatchPresentation() {
        #if DEBUG
        validation = DebugValidation()
        validationFrames = 0; validationElapsed = 0; validationIntervals.removeAll(keepingCapacity: true); validationLongFrames = 0
        #endif
        finished = false
        newBest = false
        paused = false
        score = 0
        lives = engine.state.lives
        playerRallyPoints = engine.state.playerRallyPoints
        opponentRallyPoints = engine.state.opponentRallyPoints
        currentBossID = engine.state.bossID
        recordedBossMatches = 0
        phase = engine.state.phase
        lastFrame = nil
        feedbackPolicy = GameplayFeedbackPolicy()
        inputRevision &+= 1
        if !active { pause() }
        scene.render(state: engine.state, events: [], delta: 0)
    }

    private func frame(_ time: TimeInterval) {
        #if DEBUG
        if DebugValidation.controls {
            scene.render(state: engine.state, events: [], delta: 0)
            return
        }
        if let fixture = DebugValidation.fixture {
            let (snapshot, events) = DebugValidation.snapshot(fixture)
            if phase != snapshot.phase { phase = snapshot.phase }
            scene.render(state: snapshot, events: lastFrame == nil ? events : [], delta: 0)
            lastFrame = time
            return
        }
        #endif
        guard active, !paused, !finished else { lastFrame = nil; return }
        let rawDelta = lastFrame.map { max(0, time - $0) } ?? 0
        let delta = min(rawDelta, engine.tuning.maximumFrameDelta)
        lastFrame = time
        let previousPlayerX = engine.state.playerX
        let wasCountingDown = engine.state.resumeCountdown > 0
        var events: [GameEvent] = []
        #if DEBUG
        if DebugValidation.scripted {
            // Limited policies use exact fixed ticks at real time. The legacy
            // oracle remains separately labeled and may run four steps per frame.
            validationFrames += 1
            validationElapsed += rawDelta
            if rawDelta > 0 {
                if rawDelta > 0.05 { validationLongFrames += 1 }
                if validationIntervals.count < 2048 { validationIntervals.append(rawDelta) }
                else { validationIntervals[validationFrames % 2048] = rawDelta }
            }
            if DebugValidation.policyKind != nil {
                events = validation.advancePolicy(in: engine, delta: delta)
            } else {
                for _ in 0..<(DebugValidation.realtime ? 1 : 4) {
                    validation.position(in: engine)
                    let step = engine.update(delta: delta)
                    validation.observe(step, stage: engine.state.stage)
                    events += step
                }
            }
        } else { events = engine.update(delta: delta) }
        #else
        events = engine.update(delta: delta)
        #endif
        #if DEBUG
        if validation.shouldPauseForSpecial(events, state: engine.state) { pause() }
        #endif
        if previousPlayerX != engine.state.playerX || wasCountingDown != (engine.state.resumeCountdown > 0) {
            inputRevision &+= 1
        }
        #if DEBUG
        scene.debugEnabled = preferences.diagnostics
        #endif
        scene.render(state: engine.state, events: events, delta: delta)
        if score != engine.state.score { score = engine.state.score }
        if lives != engine.state.lives { lives = engine.state.lives }
        if playerRallyPoints != engine.state.playerRallyPoints { playerRallyPoints = engine.state.playerRallyPoints }
        if opponentRallyPoints != engine.state.opponentRallyPoints { opponentRallyPoints = engine.state.opponentRallyPoints }
        if currentBossID != engine.state.bossID { currentBossID = engine.state.bossID }
        if phase != engine.state.phase { phase = engine.state.phase }
        // Results remain in the authoritative state across immediate opponent
        // transitions. Persist each exactly once, including a win before Home.
        if mode.isBossRally {
            for result in engine.state.completedBossMatches.dropFirst(recordedBossMatches) {
                let matchBest = preferences.recordBoss(id: result.bossID, won: result.won,
                    score: result.score, longestRally: result.longestRallyReturns)
                newBest = mode == .bossSeries ? (newBest || matchBest) : matchBest
                recordedBossMatches += 1
            }
        }
        playFeedback(events, at: time)
        for event in events {
            if case let .runEnded(won, finalScore) = event {
                #if DEBUG
                if DebugValidation.scripted {
                    let sorted = validationIntervals.sorted()
                    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                    DebugValidation.log("VALIDATION PERFORMANCE frames=\(validationFrames) activeSeconds=\(validationElapsed) callbacksPerSecond=\(Double(validationFrames) / max(0.001, validationElapsed)) sampledP95ms=\(p95 * 1000) sampledMaxMs=\((sorted.last ?? 0) * 1000) callbacksOver50ms=\(validationLongFrames)")
                }
                #endif
                switch mode {
                case .arcade: newBest = preferences.record(score: finalScore)
                case let .bossRally(id):
                    // A recovered terminal snapshot may have no match event;
                    // ordinary resolved matches have already been recorded.
                    if recordedBossMatches == 0 {
                        newBest = preferences.recordBoss(id: id, won: won, score: finalScore,
                            longestRally: engine.state.longestRallyReturns)
                        recordedBossMatches = 1
                    }
                case .bossSeries: break
                }
                finished = true
                lastFrame = nil
            }
        }
    }

    private func playFeedback(_ events: [GameEvent], at time: TimeInterval) {
        guard let feedback = feedbackPolicy.select(events, at: time,
            enabled: active && !paused && preferences.haptics) else { return }
        #if os(watchOS)
        let type: WKHapticType
        switch feedback {
        case .failure: type = .failure
        case .success: type = .success
        case .contact, .combo: type = .click
        case .recovery: type = .directionDown
        }
        WKInterfaceDevice.current().play(type)
        #endif
    }
}

/// Semantic feedback selection is testable without sending physical haptics.
/// A combo has its own cooldown and never delays the next paddle contact.
struct GameplayFeedbackPolicy {
    enum Feedback: Equatable { case failure, success, contact, combo, recovery }
    private var lastPrimary: TimeInterval = -.infinity
    private var lastCombo: TimeInterval = -.infinity
    mutating func select(_ events: [GameEvent], at time: TimeInterval, enabled: Bool) -> Feedback? {
        guard enabled, time.isFinite else { return nil }
        var primary: Feedback?
        var priority = 0
        var milestone = false
        for event in events {
            switch event {
            case .lifeLost, .opponentPoint:
                if priority < 3 { primary = .failure; priority = 3 }
            case .waveCleared, .bossDefeated:
                if priority < 2 { primary = .success; priority = 2 }
            case let .bossMatchEnded(result):
                let resultPriority = result.won ? 2 : 3
                if priority < resultPriority {
                    primary = result.won ? .success : .failure
                    priority = resultPriority
                }
            case .ballRecovered:
                if priority < 1 { primary = .recovery; priority = 1 }
            case .paddleContact:
                if priority < 1 { primary = .contact; priority = 1 }
            case let .comboChanged(chain, _):
                milestone = milestone || chain == 3 || chain == 5
            default: break
            }
        }
        if let primary {
            guard time - lastPrimary >= 0.12 else { return nil }
            lastPrimary = time
            return primary
        }
        if milestone, time - lastCombo >= 0.8, time - lastPrimary >= 0.12 {
            lastCombo = time
            return .combo
        }
        return nil
    }
}
