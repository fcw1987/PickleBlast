#if DEBUG
import Foundation
import PickleBlastCore

/// Explicit development evidence fixtures. This entire file has no Release symbols.
struct DebugValidation {
    private final class WeakObject {
        weak var value: AnyObject?
        init(_ value: AnyObject) { self.value = value }
    }
    @MainActor private static var sessionProbes: [WeakObject] = []
    @MainActor private static var sceneProbes: [WeakObject] = []
    @MainActor private static var textureProbes: [WeakObject] = []
    @MainActor private static var lifetimeSequence = 0

    /// Explicit native diagnostic only. Weak references cannot keep a dismissed
    /// game alive; each next session reports what survived the previous Home.
    @MainActor static func trackLifetime(of session: GameSession) {
        guard ProcessInfo.processInfo.arguments.contains("--validation-lifetimes") else { return }
        sessionProbes.removeAll { $0.value == nil }
        sceneProbes.removeAll { $0.value == nil }
        textureProbes.removeAll { $0.value == nil }
        let record = "sequence=\(lifetimeSequence) priorSessions=\(sessionProbes.count) priorScenes=\(sceneProbes.count) priorTextureLibraries=\(textureProbes.count) selected=\(session.engine.state.bossID.rawValue) characterAtlases=\(session.scene.debugLoadedCharacterAtlases.joined(separator: ","))\n"
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let path = directory.appendingPathComponent("validation-lifetimes.log")
            do {
                if lifetimeSequence == 0 { try Data(record.utf8).write(to: path, options: .atomic) }
                else {
                    let file = try FileHandle(forWritingTo: path)
                    defer { try? file.close() }
                    try file.seekToEnd()
                    try file.write(contentsOf: Data(record.utf8))
                }
            } catch { log("VALIDATION LIFETIME probe write failed: \(error)") }
        }
        lifetimeSequence += 1
        sessionProbes.append(WeakObject(session))
        sceneProbes.append(WeakObject(session.scene))
        textureProbes.append(WeakObject(session.scene.debugTextureLibraryForLifetimeProbe))
    }

    static var startMode: GameMode {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--validation-series") { return .bossSeries }
        guard let argument = args.first(where: { $0.hasPrefix("--validation-boss=") }),
              let id = BossID(rawValue: String(argument.dropFirst("--validation-boss=".count))) else { return .arcade }
        return .bossRally(id)
    }
    static var fixture: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--validation-fixture"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var autoplay: Bool { ProcessInfo.processInfo.arguments.contains("--validation-autoplay") }
    static var policyKind: BossPlayerPolicy? {
        guard let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--validation-policy=") }) else { return nil }
        return BossPlayerPolicy(rawValue: String(value.dropFirst("--validation-policy=".count)))
    }
    static var seed: UInt64 {
        if let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--validation-seed=") }),
           let seed = UInt64(value.dropFirst("--validation-seed=".count)) { return seed }
        return autoplay || policyKind != nil ? 7 : 0xB1A57
    }
    static var scripted: Bool { autoplay || policyKind != nil }
    static var realtime: Bool { ProcessInfo.processInfo.arguments.contains("--validation-realtime") }
    static var controls: Bool { ProcessInfo.processInfo.arguments.contains("--validation-controls") }
    static var startsRun: Bool {
        !ProcessInfo.processInfo.arguments.contains("--validation-manual-start")
            && (fixture != nil || scripted || controls)
    }
    static var isValidationLaunch: Bool {
        let flags = ["--validation-fixture", "--validation-autoplay", "--validation-realtime",
                     "--validation-controls", "--validation-lifetimes", "--validation-pause-special", "--validation-series", "--validation-manual-start"]
        return ProcessInfo.processInfo.arguments.contains { flags.contains($0) || $0.hasPrefix("--validation-boss=") || $0.hasPrefix("--validation-policy=") || $0.hasPrefix("--validation-seed=") || $0.hasPrefix("--validation-pause-lob=") }
    }
    static func snapshot(_ name: String) -> (GameState, [GameEvent]) {
        let tuning = GameTuning()
        var state = GameState()
        state.phase = .playing
        state.stage = .wave(2)
        state.score = 250
        state.targets = AuthoredWaves.targets(for: 2)
        state.ball = BallState(position: .init(x: 12, y: 18), velocity: .init(x: 5, y: -25))
        if let index = state.targets.firstIndex(where: { $0.kind == .basket }) { state.targets[index].health = 1 }
        var events: [GameEvent] = []
        if name == "wave1" { state.stage = .wave(1); state.targets = AuthoredWaves.targets(for: 1) }
        if name == "wave2" { state.stage = .wave(2) }
        if name == "wave3" || name.hasPrefix("large") || name == "combo" {
            state.stage = .wave(3); state.targets = AuthoredWaves.targets(for: 3)
        }
        if name == "combo" {
            state.targetChain = 5
            state.ball = BallState(position: .init(x: 10, y: 43), velocity: .init(x: 22, y: -14))
            events = [.targetHit(id: 348, kind: .paddle, destroyed: true, score: 500),
                      .comboChanged(chain: 5, multiplier: 5)]
        }
        let contactClip = name.split(separator: "-").first.map(String.init) ?? name
        if ["forehand", "backhand", "block"].contains(contactClip) {
            if name.hasSuffix("-left") { state.playerX = tuning.playerMargin }
            if name.hasSuffix("-right") { state.playerX = CourtGeometry.width - tuning.playerMargin }
            let requestedOffset = contactClip == "forehand" ? tuning.playerHalfWidth + tuning.ballRadius : (contactClip == "backhand" ? -tuning.playerHalfWidth - tuning.ballRadius : 0)
            let ballX = min(CourtGeometry.width - tuning.ballRadius, max(tuning.ballRadius, state.playerX + requestedOffset))
            let offset = ballX - state.playerX
            state.ball = BallState(position: .init(x: state.playerX + offset, y: tuning.playerY + tuning.ballRadius), velocity: .init(x: 0, y: 26))
            events = [.paddleContact(x: state.playerX + offset, side: SwingSide(rawValue: contactClip)!, centered: contactClip == "block")]
        }
        if name.hasPrefix("boss") {
            state.mode = startMode
            state.stage = .boss
            state.targets = []
            let id = state.bossID
            let configuration = tuning.bossConfiguration(for: id)
            state.boss = BossState(id: id, x: 12, movementTarget: 16, points: 1)
            state.score = 3650
            if name.hasPrefix("boss-contact") {
                // Front-facing bosses have the opposite handedness on screen.
                let offset = name.hasSuffix("backhand") ? 1.2 : (name.hasSuffix("block") ? 0 : -1.2)
                let x = 12 + offset
                state.ball = BallState(position: .init(x: x, y: configuration.y - tuning.ballRadius), velocity: .init(x: 0, y: -30))
                events = [.bossContact(x: x)]
            }
            if name == "boss-power" {
                state.boss?.specialPhase = .powerWindup
                state.ball = BallState(position: .init(x: 12, y: 28), velocity: .init(x: 0, y: 30))
                events = [.bossPowerTelegraph]
            }
            if name == "boss-power-recovery" {
                state.boss?.specialPhase = .powerRecovery
                state.boss?.specialRemaining = 1.5
            }
            if name == "boss-poach" || name == "boss-poach-recovery" {
                state.boss?.specialPhase = name == "boss-poach" ? .poachCommitment : .poachRecovery
                state.boss?.committedSide = .right
                state.boss?.committedTargetX = 16
                state.boss?.specialRemaining = 1
                events = name == "boss-poach" ? [.bossPoachCommitment(side: .right, targetX: 16)] : [.bossPoachRecovery]
            }
        }
        if name == "receiving" {
            let position = Vector2(x: 15, y: tuning.receivingBoundaryY)
            let velocity = ReceivingTrajectory.constrained(.init(x: 25, y: -7.141428), at: position,
                maximumApparentAngle: tuning.maximumIncomingApparentAngle,
                projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
            state.ball = BallState(position: position, velocity: velocity)
        }
        if name == "saved" || name == "charged-miss" {
            state.phase = .ready; state.ball = nil
            state.recoveriesRemaining = name == "saved" ? 1 : 0
            state.lives = name == "saved" ? 3 : 2
            events = name == "saved" ? [.ballRecovered(remaining: 1)] : [.lifeLost(remaining: 2)]
        }
        if name == "cleanup" {
            state.phase = .cleanup; state.ball = nil
            state.targets = Array(state.targets.suffix(4))
        }
        if name == "cascade" {
            state.phase = .celebration; state.ball = nil; state.targets = []
            for _ in 0..<360 { state.celebration.update(delta: 1.0 / 120) }
        }
        // Held native HUD evidence only; no Release code or core rule changes.
        if name.hasPrefix("boss-hud-") {
            state.mode = startMode
            state.stage = .boss
            state.targets = []
            state.boss = BossState(id: state.bossID, points: name == "boss-hud-points" ? 2 : 1)
            state.boss?.opponentPoints = name == "boss-hud-points" ? 1 : 0
            state.ball = BallState(position: .init(x: 10, y: 18), velocity: .init(x: 0, y: -26))
            state.consecutivePlayerReturns = name == "boss-hud-milestone" ? 20 : (name == "boss-hud-earned" ? 21 : 7)
            state.recoveriesRemaining = ["boss-hud-earned", "boss-hud-milestone"].contains(name) ? 1 : 0
            events = name == "boss-hud-milestone" ? [.rallyMilestone(returns: 20), .recoveryEarned] : []
        }
        if name == "blackout" { state.phase = .blackout; state.ball = nil }
        return (state, events)
    }

    static func log(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }

    private var specialPauseUsed = false
    mutating func shouldPauseForSpecial(_ events: [GameEvent], state: GameState) -> Bool {
        guard !specialPauseUsed else { return false }
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--validation-pause-lob=") }),
           let flight = state.rallyShot?.lobFlight {
            let phase = String(argument.dropFirst("--validation-pause-lob=".count))
            let threshold = ["rise": 0.15, "apex": 0.50, "descent": 0.85][phase]
            if let threshold, flight.fraction >= threshold {
                specialPauseUsed = true
                Self.log("VALIDATION SPECIAL INTERRUPTION lob \(phase) fraction=\(flight.fraction)")
                return true
            }
        }
        guard ProcessInfo.processInfo.arguments.contains("--validation-pause-special"),
              events.contains(.bossPowerTelegraph) else { return false }
        specialPauseUsed = true
        Self.log("VALIDATION SPECIAL INTERRUPTION powerWindup")
        return true
    }

    private var policy: BossEvaluationPolicy?
    private var policyAccumulator = 0.0
    private var policyPendingEvents: [GameEvent] = []
    /// Exact fixed-tick policy used by the host comparisons. Rendering only
    /// determines when a bounded batch runs; it does not change player inputs.
    mutating func advancePolicy(in engine: GameEngine, delta: Double) -> [GameEvent] {
        guard let kind = Self.policyKind else { return [] }
        if policy == nil {
            let policySeed = Self.seed ^ (UInt64(kind.rawValue.utf8.reduce(0) { ($0 &* 33) &+ UInt64($1) }) << 16)
            policy = BossEvaluationPolicy(kind: kind, seed: policySeed, tuning: engine.tuning,
                                          startingPositionSeed: Self.seed)
        }
        policyAccumulator += min(max(0, delta), engine.tuning.maximumFrameDelta)
        var all: [GameEvent] = []
        let step = engine.tuning.fixedStep
        var count = 0
        while policyAccumulator + 1e-12 >= step && count < engine.tuning.maximumStepsPerFrame {
            policyAccumulator = max(0, policyAccumulator - step)
            policy?.observe(.init(time: engine.state.simulationTime, phase: engine.state.phase,
                                  ball: engine.state.ball, playerX: engine.state.playerX), events: policyPendingEvents)
            let movement = policy?.movementDelta(currentPlayerX: engine.state.playerX, elapsed: step) ?? 0
            engine.movePlayer(crownDelta: movement, sensitivity: 1)
            let events = engine.update(delta: step)
            policyPendingEvents = events
            observe(events, stage: engine.state.stage)
            for event in events {
                switch event {
                case .paddleContact, .bossContact, .bossPoint, .opponentPoint, .ballRecovered,
                     .bossPowerTelegraph, .bossPowerContact, .bossPoachCommitment, .bossPoachRecovery, .rallyShotLaunched, .bossMatchEnded, .runEnded:
                    Self.log("VALIDATION POLICY t=\(engine.state.simulationTime) policy=\(kind.rawValue) event=\(event) points=\(engine.state.playerRallyPoints)-\(engine.state.opponentRallyPoints) returns=\(engine.state.currentRallyReturns) bossX=\(engine.state.boss?.x ?? 0)")
                default: break
                }
            }
            all += events
            count += 1
            if engine.state.phase == .results { policyAccumulator = 0; break }
        }
        return all
    }

    private var returns = 0
    private var bossReturns = 0
    private var plannedReturn = -1
    private var plannedAngle = 0.0
    private var loggedBackfield = false
    mutating func observe(_ events: [GameEvent], stage: GameStage) {
        for event in events {
            if case .paddleContact = event { returns += 1; if stage.isBoss { bossReturns += 1 } }
            switch event {
            case .phaseChanged(let phase):
                Self.log("VALIDATION SCRIPTED phase=\(phase) stage=\(stage)")
            case .comboChanged(let chain, let multiplier) where multiplier > 1:
                Self.log("VALIDATION SCRIPTED combo chain=\(chain) multiplier=\(multiplier)")
            case .targetHit(let id, _, let destroyed, let score) where id >= 354:
                Self.log("VALIDATION SCRIPTED large target=\(id) destroyed=\(destroyed) score=\(score)")
            case .waveCleared, .bossIncoming, .bossPoint, .opponentPoint, .bossDefeated, .bossMatchEnded, .runEnded, .ballRecovered, .lifeLost, .targetCleaned,
                 .bossPowerTelegraph, .bossPowerContact, .bossPoachCommitment, .bossPoachRecovery:
                Self.log("VALIDATION SCRIPTED \(event)")
            default: break
            }
        }
    }
    mutating func position(in engine: GameEngine) {
        if let wave = engine.state.stage.waveNumber, let ball = engine.state.ball,
           ball.position.y > [33.8, 42.2, 42.25][wave - 1], !loggedBackfield {
            Self.log("VALIDATION SCRIPTED backfield wave=\(wave) x=\(ball.position.x) y=\(ball.position.y) chain=\(engine.state.targetChain)")
            loggedBackfield = true
        }
        if engine.state.phase == .ready { loggedBackfield = false }
        guard let ball = engine.state.ball, ball.velocity.y < 0, engine.state.phase == .playing else { return }
        if !engine.state.stage.isBoss,
           let front = engine.state.targets.map({ $0.position.y - $0.radius - ball.radius }).min(),
           ball.position.y > front - 0.1 { return }
        let contactY = engine.tuning.playerY + ball.radius
        let time = max(0, (contactY - ball.position.y) / ball.velocity.y)
        let span = 20 - 2 * ball.radius
        var folded = (ball.position.x + ball.velocity.x * time - ball.radius).truncatingRemainder(dividingBy: 2 * span)
        if folded < 0 { folded += 2 * span }
        let landing = ball.radius + (folded <= span ? folded : 2 * span - folded)
        var angle = 0.0
        if engine.state.stage.isBoss {
            let fractions = [0.92, -0.88, 0.68, -0.97, 0.82, -0.72]
            angle = fractions[bossReturns % fractions.count] * engine.tuning.maximumOutgoingApparentAngle
        } else {
            if plannedReturn != returns {
                plannedAngle = denseWaveAngle(in: engine, landing: landing, contactY: contactY)
                plannedReturn = returns
            }
            angle = plannedAngle
        }
        let desired = landing - angle / engine.tuning.maximumOutgoingApparentAngle * engine.tuning.playerHalfWidth
        if returns.isMultiple(of: 2) { engine.movePlayer(crownDelta: desired - engine.state.playerX, sensitivity: 1) }
        else {
            let transform = CourtTransform(viewportWidth: 211, viewportHeight: 257)
            engine.setPlayerFromTouch(screenX: transform.screenPoint(for: .init(x: desired, y: 0)).x, transform: transform)
        }
    }
    /// DEBUG/test-only ray planning. It chooses a return angle through the same
    /// public player control; it never alters a ball, target, score or transition.
    /// Mirrored target images represent ordinary side/far-wall reflections.
    private func denseWaveAngle(in engine: GameEngine, landing: Double, contactY: Double) -> Double {
        let radius = engine.tuning.ballRadius
        let span = CourtGeometry.width - 2 * radius
        let far = CourtGeometry.length - radius
        var images: [(position: Vector2, radius: Double)] = []
        images.reserveCapacity(engine.state.targets.count * 6)
        for target in engine.state.targets {
            let x = target.position.x
            for imageX in [x, 2 * radius - x, 2 * (CourtGeometry.width - radius) - x] {
                for imageY in [target.position.y, 2 * far - target.position.y] {
                    images.append((.init(x: imageX, y: imageY), target.radius + radius))
                }
            }
        }
        let start = Vector2(x: landing, y: contactY)
        var bestAngle = 0.0
        var bestValue = -Double.infinity
        for aim in images {
            let angle = atan2(aim.position.x - landing, aim.position.y - contactY)
            let apparent = atan(ReceivingTrajectory.projectedSlope(of: .init(x: sin(angle), y: cos(angle)),
                at: start, projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor))
            let playerX = landing - apparent / engine.tuning.maximumOutgoingApparentAngle * engine.tuning.playerHalfWidth
            guard abs(apparent) <= engine.tuning.maximumOutgoingApparentAngle,
                  playerX >= engine.tuning.playerMargin,
                  playerX <= CourtGeometry.width - engine.tuning.playerMargin else { continue }
            let direction = Vector2(x: sin(angle), y: cos(angle))
            var first = Double.infinity
            for obstacle in images {
                let offset = obstacle.position - start
                let along = offset.dot(direction)
                let perpendicularSquared = offset.dot(offset) - along * along
                guard along > 0, perpendicularSquared <= obstacle.radius * obstacle.radius else { continue }
                let distance = along - sqrt(max(0, obstacle.radius * obstacle.radius - perpendicularSquared))
                if distance > 0 { first = min(first, distance) }
            }
            guard first.isFinite else { continue }
            let firstY = contactY + direction.y * first
            let worldY = firstY <= far ? firstY : 2 * far - firstY
            // Prefer a real bank behind the field; otherwise open the deepest
            // available target. Slight angular preference makes ties stable.
            let frontX = landing + tan(angle) * (23.0 - contactY)
            var folded = (frontX - radius).truncatingRemainder(dividingBy: 2 * span)
            if folded < 0 { folded += 2 * span }
            let entryX = radius + (folded <= span ? folded : 2 * span - folded)
            let sideEntry = entryX < 2 || entryX > 18
            let value = worldY + (firstY > far ? 20 : 0) + (sideEntry ? 2 : 0) - abs(angle) * 0.01
            if value > bestValue { bestValue = value; bestAngle = apparent }
        }
        return bestAngle
    }

}
#endif
