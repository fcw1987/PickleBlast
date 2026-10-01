import Foundation

/// The only authority for gameplay. The host supplies active foreground frame time.
/// Internal setters are an intentional @testable scenario seam, not a release control.
public final class GameEngine {
    public internal(set) var state: GameState
    public let mode: GameMode
    public let tuning: GameTuning
    private let runPlan: RunPlan
    private var bossMatchStartScore = 0
    private var bossMatchResolved = false
    private var accumulator: Double = 0
    private var initialSeed: UInt64
    private var generator: SeededGenerator
    private var targetContacts: Set<Int> = []
    private var swingSide: SwingSide?
    private var swingElapsed: Double = 0
    private var missRemaining: Double = 0
    private var incomingGuided = false
    private var noProgressTime = 0.0
    private var stallRedirected = false
    private struct RallyObservation {
        let time: Double
        let ball: BallState
        let playerX: Double
    }
    private struct PlayerMotionSample { let time: Double; let x: Double }
    private var rallyObservations = Array<RallyObservation?>(repeating: nil, count: 96)
    private var rallyObservationCursor = 0
    private var rallyObservationCount = 0
    private var rallyDecisionRemaining = 0.0
    private var rallyFlightError = 0.0
    private var rallyCompletedLanes: [Double] = []
    private var rallyPendingPlayerLane: Double?
    private var rallyLastPowerReturn = -100
    private var rallyPowerTelegraphTime: Double?
    private var rallyLastPoachReturn = -100
    private var rallyBalanceRemaining = 0.0
    private var rallyLastShotSide = 0
    private var playerMotionSamples: [PlayerMotionSample] = []

    public var activeBossConfiguration: BossConfiguration { tuning.bossConfiguration(for: state.bossID) }

    public init(mode: GameMode = .arcade, tuning: GameTuning = GameTuning(), seed: UInt64 = 0xB1A57) {
        self.mode = mode
        self.tuning = tuning
        self.runPlan = RunPlan(mode: mode)
        self.initialSeed = seed
        self.generator = SeededGenerator(seed: seed)
        self.state = GameState(celebration: CelebrationPool(capacity: tuning.celebrationCapacity,
                                                            emissionRate: tuning.celebrationEmissionRate,
                                                            baseRadius: tuning.celebrationBallRadius,
                                                            seed: seed ^ 0xCA5CADE))
        state.mode = mode
        state.recoveriesRemaining = max(0, tuning.freeRecoveriesPerStage)
        state.lives = tuning.initialLives
        state.stage = runPlan.stages[0].stage
        if let id = runPlan.stages[0].bossID {
            state.boss = BossState(id: id, reactionRemaining: tuning.rallyOpponentConfiguration(for: id).observationDelay)
        } else {
            state.targets = AuthoredWaves.targets(for: 1, tuning: tuning)
        }
        state.phaseTimeRemaining = tuning.readyDuration
        incomingGuided = false; noProgressTime = 0; stallRedirected = false
        resetRallyRuntime()
    }

    public func reset(seed: UInt64? = nil) {
        if let seed { initialSeed = seed }
        generator = SeededGenerator(seed: initialSeed)
        bossMatchStartScore = 0; bossMatchResolved = false
        accumulator = 0; targetContacts.removeAll(keepingCapacity: true)
        swingSide = nil; swingElapsed = 0; missRemaining = 0
        state = GameState(celebration: CelebrationPool(capacity: tuning.celebrationCapacity,
                                                      emissionRate: tuning.celebrationEmissionRate,
                                                      baseRadius: tuning.celebrationBallRadius,
                                                      seed: initialSeed ^ 0xCA5CADE))
        state.mode = mode
        state.recoveriesRemaining = max(0, tuning.freeRecoveriesPerStage)
        state.lives = tuning.initialLives
        state.stage = runPlan.stages[0].stage
        if let id = runPlan.stages[0].bossID {
            state.boss = BossState(id: id, reactionRemaining: tuning.rallyOpponentConfiguration(for: id).observationDelay)
        } else {
            state.targets = AuthoredWaves.targets(for: 1, tuning: tuning)
        }
        state.phaseTimeRemaining = tuning.readyDuration
        incomingGuided = false; noProgressTime = 0; stallRedirected = false
        resetRallyRuntime()
    }

    public func setPlayerX(_ x: Double) {
        guard acceptsInput, x.isFinite else { return }
        state.playerX = clamp(x, tuning.playerMargin, CourtGeometry.width - tuning.playerMargin)
        state.crownInput = state.playerX
    }

    public func movePlayer(crownDelta: Double, sensitivity: Double = 1) {
        guard acceptsInput, crownDelta.isFinite, sensitivity.isFinite else { return }
        let factor = clamp(sensitivity, GameSettings.minimumSensitivity, GameSettings.maximumSensitivity)
        let movement = crownDelta * factor
        setPlayerX(movement.isFinite ? state.playerX + movement : (crownDelta > 0 ? CourtGeometry.width : 0))
    }

    /// Diagnostics only. Crown speed never affects position, gain, momentum or
    /// simulation; movement is a direct linear function of the binding delta.
    public func recordCrownVelocity(_ velocity: Double) {
        guard acceptsInput else { return }
        state.crownVelocity = velocity.isFinite ? velocity : 0
    }

    public func setPlayerFromTouch(screenX: Double, transform: CourtTransform) {
        guard screenX.isFinite else { return }
        setPlayerX(transform.courtPoint(for: .init(x: screenX, y: transform.origin.y)).x)
    }

    public func pause() {
        guard state.phase != .results else { return }
        state.isPaused = true
        accumulator = 0
        if mode.isBossRally {
            playerMotionSamples.removeAll(keepingCapacity: true)
            clearRallyObservations()
            rallyPowerTelegraphTime = nil
            if state.boss?.specialPhase == .powerWindup
                || state.boss?.specialPhase == .poachCommitment {
                state.boss?.specialPhase = .idle
                state.boss?.specialRemaining = 0
                state.boss?.committedSide = nil
                state.boss?.committedTargetX = nil
                let heldX = state.boss?.x ?? CourtGeometry.centerX
                state.boss?.movementTarget = heldX
            }
        }
    }

    public func resume() {
        guard state.isPaused else { return }
        state.isPaused = false
        state.resumeCountdown = max(0, tuning.resumeDuration)
        accumulator = 0
        if mode.isBossRally { playerMotionSamples.removeAll(keepingCapacity: true); clearRallyObservations() }
    }

    /// Invalid time and background time are never consumed. Long frames deliberately
    /// slow simulation rather than replaying suspended time or doing unbounded work.
    @discardableResult public func update(delta: Double) -> [GameEvent] {
        guard !state.isPaused, state.phase != .results, delta.isFinite, delta > 0 else { return [] }
        let step = max(0.001, tuning.fixedStep)
        accumulator += min(delta, max(step, tuning.maximumFrameDelta))
        var events: [GameEvent] = []
        var count = 0
        while accumulator + 1e-12 >= step, count < max(1, tuning.maximumStepsPerFrame) {
            accumulator = max(0, accumulator - step)
            tick(step, events: &events)
            count += 1
            if state.phase == .results { accumulator = 0; break }
        }
        if count == max(1, tuning.maximumStepsPerFrame), accumulator >= step { accumulator = 0 }
        return events
    }

    public func playerReturnVelocity(contactX: Double, speed: Double) -> Vector2 {
        let offset = clamp((contactX - state.playerX) / tuning.playerHalfWidth, -1, 1)
        let safeSpeed = min(tuning.maximumBallSpeed, max(0, speed.isFinite ? speed : tuning.initialBallSpeed))
        return ReceivingTrajectory.outgoing(apparentAngle: offset * tuning.maximumOutgoingApparentAngle,
            at: .init(x: contactX, y: tuning.playerY + tuning.ballRadius), speed: safeSpeed,
            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
    }

    private var acceptsInput: Bool {
        !state.isPaused && state.resumeCountdown <= 0 && state.phase != .results
    }

    private func tick(_ delta: Double, events: inout [GameEvent]) {
        state.simulationTime += delta
        if state.resumeCountdown > 0 {
            state.resumeCountdown = max(0, state.resumeCountdown - delta)
            return
        }
        updateAnimation(delta)
        switch state.phase {
        case .ready:
            state.phaseTimeRemaining = max(0, state.phaseTimeRemaining - delta)
            if state.phaseTimeRemaining <= 1e-10 { launch(events: &events) }
        case .playing:
            state.rallyTime += delta
            noProgressTime += delta
            if mode.isBossRally { recordPlayerMotion() }
            if state.stage.isBoss { updateBoss(delta, events: &events) }
            if var ball = state.ball {
                ball.velocity = limitedVelocity(ball.velocity)
                if state.stage.isBoss {
                    let growth: Double
                    if mode.isBossRally {
                        let id = state.bossID
                        growth = tuning.rallyOpponentConfiguration(for: id).speedGrowthPerSecond
                    } else {
                        growth = activeBossConfiguration.accelerationPerSecond
                    }
                    let speed = min(tuning.maximumBallSpeed,
                                    ball.speed + growth * delta)
                    if ball.speed > 0 { ball.velocity = ball.velocity * (speed / ball.speed) }
                }
                if ball.position.y > tuning.receivingBoundaryY { incomingGuided = false }
                if ball.velocity.y < 0, ball.position.y <= tuning.receivingBoundaryY, !incomingGuided {
                    guideReceiving(&ball)
                }
                if !stallRedirected, noProgressTime >= tuning.stallNoProgressDuration,
                   abs(ball.velocity.y) < ball.speed * tuning.stallShallowFraction {
                    ball.velocity = ReceivingTrajectory.stallRedirect(ball.velocity,
                        minimumVerticalFraction: tuning.stallRecoveryVerticalFraction)
                    stallRedirected = true
                }
                state.ball = ball
            }
            advanceBall(delta, events: &events)
        case .cleanup:
            state.phaseTimeRemaining = max(0, state.phaseTimeRemaining - delta)
            if state.phaseTimeRemaining <= 1e-10 {
                if let index = state.targets.indices.min(by: { state.targets[$0].id < state.targets[$1].id }) {
                    let target = state.targets.remove(at: index)
                    let points = tuning.score(for: target.kind, size: target.size, destroyed: true)
                    state.score += points
                    events.append(.targetCleaned(id: target.id, kind: target.kind, score: points))
                }
                if state.targets.isEmpty { completeWave(events: &events) }
                else { state.phaseTimeRemaining = max(tuning.fixedStep, tuning.cleanupStepDuration) }
            }
        case .impact:
            state.phaseTimeRemaining = max(0, state.phaseTimeRemaining - delta)
            if state.phaseTimeRemaining <= 1e-10 {
                state.ball = nil
                state.celebration.reset()
                changePhase(.celebration, duration: state.won ? tuning.bossCelebrationDuration : tuning.celebrationDuration,
                            events: &events)
            }
        case .celebration:
            state.celebration.update(delta: delta)
            state.phaseTimeRemaining = max(0, state.phaseTimeRemaining - delta)
            if state.phaseTimeRemaining <= 1e-10 {
                changePhase(.blackout, duration: tuning.blackoutDuration, events: &events)
            }
        case .blackout:
            state.phaseTimeRemaining = max(0, state.phaseTimeRemaining - delta)
            if state.phaseTimeRemaining <= 1e-10 {
                state.celebration.reset()
                if state.won { finish(won: true, events: &events) }
                else if let next = runPlan.next(after: state.stage, bossID: state.bossID) {
                    startStage(next, events: &events)
                }
                else { finish(won: true, events: &events) }
            }
        case .results: break
        }
    }

    private func launch(events: inout [GameEvent]) {
        let launchY = state.stage.isBoss ? activeBossConfiguration.y - tuning.ballRadius - tuning.collisionEpsilon : tuning.launchY
        state.ball = BallState(position: .init(x: CourtGeometry.centerX, y: launchY),
                               velocity: .init(x: 0, y: -min(tuning.initialBallSpeed, tuning.maximumBallSpeed)),
                               radius: tuning.ballRadius)
        state.rallyTime = 0
        incomingGuided = false; noProgressTime = 0; stallRedirected = false
        targetContacts.removeAll(keepingCapacity: true)
        swingSide = nil; missRemaining = 0
        state.playerAnimation = .ready
        if mode.isBossRally { playerMotionSamples.removeAll(keepingCapacity: true); clearRallyObservations() }
        changePhase(.playing, duration: 0, events: &events)
    }

    private func prepareRally(duration: Double? = nil, events: inout [GameEvent]) {
        state.ball = nil
        state.rallyTime = 0
        state.currentRallyReturns = 0
        incomingGuided = false; noProgressTime = 0; stallRedirected = false
        targetContacts.removeAll(keepingCapacity: true)
        if mode.isBossRally { resetRallyRuntime(retainingHistory: true) }
        if state.boss != nil {
            let reactionDelay: Double
            if mode.isBossRally {
                let id = state.bossID
                reactionDelay = tuning.rallyOpponentConfiguration(for: id).observationDelay
            } else { reactionDelay = activeBossConfiguration.reactionDelay }
            state.boss?.x = CourtGeometry.centerX
            state.boss?.movementTarget = CourtGeometry.centerX
            state.boss?.reactionRemaining = reactionDelay
            state.boss?.specialPhase = .idle
            state.boss?.specialRemaining = 0
            state.boss?.committedSide = nil
            state.boss?.committedTargetX = nil
            state.boss?.specialTriggeredForReturn = false
            state.boss?.lateralVelocity = 0
            state.boss?.lastShotPurpose = nil
            state.boss?.plannedReceivingX = nil
            state.boss?.lastObservedTime = nil
            state.boss?.predictedInterceptX = nil
            state.boss?.reachableLeftX = nil
            state.boss?.reachableRightX = nil
        }
        changePhase(.ready, duration: duration ?? tuning.readyDuration, events: &events)
    }

    private func startStage(_ entry: RunPlan.Entry, readyDuration: Double? = nil,
                            events: inout [GameEvent]) {
        resetTargetChain(events: &events)
        state.stage = entry.stage
        state.recoveriesRemaining = max(0, tuning.freeRecoveriesPerStage)
        state.playerX = CourtGeometry.centerX
        state.crownInput = state.playerX
        state.playerAnimation = .ready
        swingSide = nil; missRemaining = 0
        if let number = entry.stage.waveNumber {
            state.targets = AuthoredWaves.targets(for: number, tuning: tuning)
            state.boss = nil
        } else {
            state.targets.removeAll(keepingCapacity: true)
            let id = entry.bossID ?? .wall
            let reactionDelay = mode.isBossRally
                ? tuning.rallyOpponentConfiguration(for: id).observationDelay
                : tuning.bossConfiguration(for: id).reactionDelay
            state.boss = BossState(id: id, reactionRemaining: reactionDelay)
            events.append(.bossIncoming)
        }
        if mode.isBossRally {
            state.won = false
            state.currentBossMatchLongestRallyReturns = 0
            state.crownVelocity = 0
            swingElapsed = 0
            bossMatchStartScore = state.score
            bossMatchResolved = false
            resetRallyRuntime()
        }
        prepareRally(duration: readyDuration, events: &events)
    }

    private func resetTargetChain(events: inout [GameEvent]) {
        guard state.targetChain > 0 else { return }
        state.targetChain = 0
        events.append(.comboChanged(chain: 0, multiplier: 1))
    }

    private func changePhase(_ phase: GamePhase, duration: Double, events: inout [GameEvent]) {
        state.phase = phase
        state.phaseTimeRemaining = max(0, duration)
        events.append(.phaseChanged(phase))
    }

    private func finish(won: Bool, events: inout [GameEvent]) {
        if !won { resolveBossMatch(won: false, events: &events) }
        state.won = won
        state.ball = nil
        state.playerAnimation = won ? .victory : .miss
        changePhase(.results, duration: 0, events: &events)
        events.append(.runEnded(won: won, score: state.score))
    }

    private func resolveBossMatch(won: Bool, events: inout [GameEvent]) {
        guard mode.isBossRally, !bossMatchResolved else { return }
        bossMatchResolved = true
        let result = BossMatchResult(bossID: state.bossID, won: won,
            score: max(0, state.score - bossMatchStartScore),
            longestRallyReturns: mode == .bossSeries
                ? state.currentBossMatchLongestRallyReturns : state.longestRallyReturns)
        state.completedBossMatches.append(result)
        events.append(.bossMatchEnded(result: result))
    }

    private func updateBoss(_ delta: Double, events: inout [GameEvent]) {
        guard var boss = state.boss, let ball = state.ball else { return }
        if mode.isBossRally {
            updateRallyBoss(&boss, ball: ball, delta: delta, events: &events)
            state.boss = boss
            return
        }
        // Keep the accepted Wall sampling, RNG calls and movement sequence intact.
        if boss.id == .wall {
            boss.reactionRemaining -= delta
            if boss.reactionRemaining <= 1e-10 {
                // Samples current position only. No future bounce/interception knowledge.
                boss.movementTarget = clamp(ball.position.x + generator.signed() * tuning.boss.aimingError,
                                            tuning.boss.halfWidth, CourtGeometry.width - tuning.boss.halfWidth)
                boss.reactionRemaining += max(tuning.fixedStep, tuning.boss.reactionDelay)
            }
            let movement = clamp(boss.movementTarget - boss.x,
                                 -tuning.boss.movementSpeed * delta, tuning.boss.movementSpeed * delta)
            boss.x = clamp(boss.x + movement, tuning.boss.halfWidth, CourtGeometry.width - tuning.boss.halfWidth)
            state.boss = boss
            return
        }

    }

    private func clearRallyObservations() {
        rallyObservations = Array(repeating: nil, count: 96)
        rallyObservationCursor = 0
        rallyObservationCount = 0
        rallyDecisionRemaining = 0
    }

    private func resetRallyRuntime(retainingHistory: Bool = false) {
        clearRallyObservations()
        rallyFlightError = 0
        rallyPowerTelegraphTime = nil
        rallyPendingPlayerLane = nil
        rallyBalanceRemaining = 0
        playerMotionSamples.removeAll(keepingCapacity: true)
        if !retainingHistory {
            rallyCompletedLanes.removeAll(keepingCapacity: true)
            rallyLastPowerReturn = -100
            rallyLastPoachReturn = -100
            rallyLastShotSide = 0
        }
    }

    private func recordPlayerMotion() {
        guard tuning.rallyMotionInfluenceEnabled else { return }
        playerMotionSamples.append(.init(time: state.simulationTime, x: state.playerX))
        let earliest = state.simulationTime - max(0, tuning.rallyMotionSampleWindow)
        while playerMotionSamples.count > 1, playerMotionSamples[1].time < earliest {
            playerMotionSamples.removeFirst()
        }
        if playerMotionSamples.count > 32 { playerMotionSamples.removeFirst(playerMotionSamples.count - 32) }
    }

    private func rallyMotionAngle() -> Double {
        guard tuning.rallyMotionInfluenceEnabled,
              let first = playerMotionSamples.first, let last = playerMotionSamples.last,
              last.time > first.time else { return 0 }
        let distance = last.x - first.x
        let deadband = max(0, tuning.rallyMotionDeadband)
        guard abs(distance) > deadband else { return 0 }
        let strength = min(1, (abs(distance) - deadband) / 1.2)
        return (distance < 0 ? -1.0 : 1.0) * strength
            * max(0, tuning.rallyMotionMaximumApparentAngle)
    }

    private func recordRallyObservation(_ ball: BallState) {
        rallyObservations[rallyObservationCursor] = .init(time: state.simulationTime,
                                                           ball: ball, playerX: state.playerX)
        rallyObservationCursor = (rallyObservationCursor + 1) % rallyObservations.count
        rallyObservationCount = min(rallyObservationCount + 1, rallyObservations.count)
    }

    private func delayedRallyObservation(delay: Double) -> RallyObservation? {
        let cutoff = state.simulationTime - max(0, delay)
        for offset in 1...max(1, rallyObservationCount) {
            let index = (rallyObservationCursor - offset + rallyObservations.count) % rallyObservations.count
            if let observation = rallyObservations[index], observation.time <= cutoff + 1e-10 {
                return observation
            }
        }
        return nil
    }

    private func updateRallyBoss(_ boss: inout BossState, ball: BallState, delta: Double,
                                 events: inout [GameEvent]) {
        let policy = tuning.rallyOpponentConfiguration(for: boss.id)
        let geometry = activeBossConfiguration
        recordRallyObservation(ball)
        rallyBalanceRemaining = max(0, rallyBalanceRemaining - delta)
        if boss.specialPhase != .idle, boss.specialPhase != .powerWindup {
            boss.specialRemaining = max(0, boss.specialRemaining - delta)
            if boss.specialRemaining <= 1e-10 {
                if boss.specialPhase == .poachCommitment {
                    boss.specialPhase = .poachRecovery
                    boss.specialRemaining = 0.35
                    events.append(.bossPoachRecovery)
                } else {
                    boss.specialPhase = .idle
                    boss.committedSide = nil
                    boss.committedTargetX = nil
                }
            }
        }
        rallyDecisionRemaining -= delta
        if rallyDecisionRemaining <= 1e-10 {
            rallyDecisionRemaining += max(tuning.fixedStep, policy.decisionPeriod)
            if let observation = delayedRallyObservation(delay: policy.observationDelay) {
                boss.lastObservedTime = observation.time
                let predicted: RallyBallProjection.Arrival?
                if observation.ball.velocity.y > 0 {
                    predicted = RallyBallProjection.arrival(of: observation.ball,
                        atY: geometry.y - observation.ball.radius, tuning: tuning,
                        speedGrowth: policy.speedGrowthPerSecond)
                } else { predicted = nil }
                if let predicted,
                   predicted.time > state.simulationTime - observation.time + tuning.fixedStep {
                    let remainingFlight = max(0, predicted.time -
                        (state.simulationTime - observation.time))
                    let interval = rallyReachableInterval(boss: boss, time: remainingFlight,
                                                          policy: policy, geometry: geometry)
                    let landing = clamp(predicted.position.x + rallyFlightError,
                                        geometry.halfWidth, CourtGeometry.width - geometry.halfWidth)
                    boss.predictedInterceptX = predicted.position.x
                    boss.reachableLeftX = interval.lowerBound
                    boss.reachableRightX = interval.upperBound
                    let reachable = clamp(landing, interval.lowerBound, interval.upperBound)
                    if boss.specialPhase == .poachCommitment,
                       let committed = boss.committedTargetX,
                       abs(landing - committed) > geometry.halfWidth + 1.0 {
                        boss.specialPhase = .poachRecovery
                        boss.specialRemaining = 0.35
                        events.append(.bossPoachRecovery)
                    }
                    boss.movementTarget = reachable
                    if boss.id == .banger, boss.specialPhase == .idle,
                       boss.returnCount + 1 >= 2,
                       boss.returnCount + 1 - rallyLastPowerReturn >= policy.powerCooldownReturns,
                       observation.ball.position.y >= tuning.receivingBoundaryY,
                       remainingFlight >= policy.powerLeadTime + tuning.fixedStep,
                       abs(landing - boss.x) <= max(geometry.halfWidth + 1.0,
                                                    policy.maximumLateralSpeed * remainingFlight),
                       rallyBalanceRemaining <= 0.05,
                       predicted.velocity.length * policy.powerSpeedMultiplier
                           <= tuning.maximumBallSpeed + 1e-9 {
                        boss.specialPhase = .powerWindup
                        boss.specialTriggeredForReturn = true
                        rallyPowerTelegraphTime = state.simulationTime
                        events.append(.bossPowerTelegraph)
                    }
                } else if observation.ball.velocity.y < 0,
                          boss.specialPhase != .poachCommitment {
                    boss.predictedInterceptX = nil
                    boss.reachableLeftX = nil
                    boss.reachableRightX = nil
                    // Recover into the lanes the player has actually used,
                    // without following the departing ball's current x.
                    let recent = rallyCompletedLanes.suffix(3)
                    let mean = recent.isEmpty ? CourtGeometry.centerX : recent.reduce(0, +) / Double(recent.count)
                    boss.movementTarget = clamp(CourtGeometry.centerX * (1 - policy.recoveryBias)
                        + mean * policy.recoveryBias, geometry.halfWidth,
                        CourtGeometry.width - geometry.halfWidth)
                }
            }
        }
        boss.reactionRemaining = max(0, rallyDecisionRemaining)
        rallySteer(&boss, target: boss.movementTarget, delta: delta,
                   policy: policy, halfWidth: geometry.halfWidth,
                   balanceRemaining: rallyBalanceRemaining)
    }

    private func rallyReachableInterval(boss: BossState, time: Double,
                                        policy: RallyOpponentConfiguration,
                                        geometry: BossConfiguration) -> ClosedRange<Double> {
        let steps = max(1, min(120, Int(ceil(time / 0.025))))
        let dt = max(0, time) / Double(steps)
        var left = boss
        var right = boss
        for index in 0..<steps {
            let remainingBalance = max(0, rallyBalanceRemaining - Double(index) * dt)
            rallySteer(&left, target: geometry.halfWidth, delta: dt,
                       policy: policy, halfWidth: geometry.halfWidth,
                       balanceRemaining: remainingBalance)
            rallySteer(&right, target: CourtGeometry.width - geometry.halfWidth,
                       delta: dt, policy: policy, halfWidth: geometry.halfWidth,
                       balanceRemaining: remainingBalance)
        }
        return min(left.x, right.x)...max(left.x, right.x)
    }

    private func rallySteer(_ boss: inout BossState, target: Double, delta: Double,
                            policy: RallyOpponentConfiguration, halfWidth: Double,
                            balanceRemaining: Double) {
        guard delta > 0 else { return }
        let distance = target - boss.x
        let speedFactor: Double
        if balanceRemaining > 0 {
            let ratio = min(1, balanceRemaining / max(0.001, policy.balanceDuration))
            speedFactor = 1 - (1 - policy.minimumBalanceMobility) * ratio
        } else { speedFactor = 1 }
        let maximumSpeed = max(0, policy.maximumLateralSpeed * speedFactor)
        let brake = max(0.001, policy.lateralBraking)
        let desired: Double
        if abs(distance) <= policy.steeringDeadband {
            desired = 0
        } else {
            desired = (distance < 0 ? -1.0 : 1.0)
                * min(maximumSpeed, sqrt(2 * brake * abs(distance)))
        }
        let decelerating = boss.lateralVelocity * desired >= 0
            && abs(desired) < abs(boss.lateralVelocity)
        let acceleration = decelerating ? brake : max(0.001, policy.lateralAcceleration)
        boss.lateralVelocity += clamp(desired - boss.lateralVelocity,
                                      -acceleration * delta, acceleration * delta)
        let next = clamp(boss.x + boss.lateralVelocity * delta,
                         halfWidth, CourtGeometry.width - halfWidth)
        if next == halfWidth || next == CourtGeometry.width - halfWidth {
            boss.lateralVelocity = 0
        }
        boss.x = next
    }

    /// Commit from completed player returns only, before the next player swing.
    /// A fresh observed incoming ball can correct the read after the real delay.
    private func considerPoachCommitment(events: inout [GameEvent]) {
        guard var boss = state.boss, boss.id == .poacher else { return }
        let policy = tuning.rallyOpponentConfiguration(for: .poacher)
        guard boss.returnCount - rallyLastPoachReturn >= policy.poachCooldownReturns else { return }
        let recent = Array(rallyCompletedLanes.suffix(max(1, policy.poachHistoryLength)))
        guard recent.count >= max(2, policy.poachMinimumConfidence) else { return }
        let left = recent.filter { $0 < CourtGeometry.centerX - 1.2 }.count
        let right = recent.filter { $0 > CourtGeometry.centerX + 1.2 }.count
        let side: BossSide
        if left >= policy.poachMinimumConfidence, left > right { side = .left }
        else if right >= policy.poachMinimumConfidence, right > left { side = .right }
        else { return }
        let direction = side == .left ? -1.0 : 1.0
        let halfWidth = activeBossConfiguration.halfWidth
        let average = recent.reduce(0, +) / Double(recent.count)
        let desired = average + direction * policy.poachCommitmentOffset
        let target = clamp(clamp(desired,
                                 boss.x - policy.poachCommitmentOffset,
                                 boss.x + policy.poachCommitmentOffset),
                           halfWidth, CourtGeometry.width - halfWidth)
        guard abs(target - boss.x) >= 0.75 else { return }
        boss.specialPhase = .poachCommitment
        boss.specialRemaining = 2.0
        boss.committedSide = side
        boss.committedTargetX = target
        boss.movementTarget = target
        boss.specialTriggeredForReturn = true
        state.boss = boss
        rallyLastPoachReturn = boss.returnCount
        rallyBalanceRemaining = max(rallyBalanceRemaining, 0.20)
        events.append(.bossPoachCommitment(side: side, targetX: target))
    }

    private enum ContactKind { case side, farWall, receiving, player, target(Int), boss, miss, bossPoint }
    private struct Contact { let time: Double; let normal: Vector2; let kind: ContactKind }

    private func earliestContact(ball: BallState, duration: Double) -> Contact? {
        var earliest: Contact?
        let epsilon = tuning.collisionEpsilon
        func consider(_ time: Double, normal: Vector2, kind: ContactKind) {
            guard time.isFinite, time >= -epsilon, time <= duration + epsilon else { return }
            let adjusted = max(0, min(duration, time))
            if earliest == nil || adjusted < earliest!.time - epsilon {
                earliest = Contact(time: adjusted, normal: normal, kind: kind)
            }
        }
        let position = ball.position
        let velocity = ball.velocity
        let radius = ball.radius
        if velocity.x < -epsilon {
            consider((radius - position.x) / velocity.x, normal: .init(x: 1, y: 0), kind: .side)
        } else if velocity.x > epsilon {
            consider((CourtGeometry.width - radius - position.x) / velocity.x,
                     normal: .init(x: -1, y: 0), kind: .side)
        }
        if velocity.y < -epsilon {
            if position.y > tuning.receivingBoundaryY {
                consider((tuning.receivingBoundaryY - position.y) / velocity.y,
                         normal: .zero, kind: .receiving)
            }
            let time = (tuning.playerY + radius - position.y) / velocity.y
            let x = position.x + velocity.x * time
            if abs(x - state.playerX) <= tuning.playerHalfWidth + radius {
                consider(time, normal: .init(x: 0, y: 1), kind: .player)
            }
            consider((-radius - position.y) / velocity.y, normal: .init(x: 0, y: 1), kind: .miss)
        } else if velocity.y > epsilon {
            if state.stage.isBoss {
                if let boss = state.boss {
                    let config = activeBossConfiguration
                    let time = (config.y - radius - position.y) / velocity.y
                    let x = position.x + velocity.x * time
                    if abs(x - boss.x) <= config.halfWidth + radius {
                        consider(time, normal: .init(x: 0, y: -1), kind: .boss)
                    }
                }
                consider((CourtGeometry.length + radius - position.y) / velocity.y,
                         normal: .init(x: 0, y: -1), kind: .bossPoint)
            } else {
                consider((CourtGeometry.length - radius - position.y) / velocity.y,
                         normal: .init(x: 0, y: -1), kind: .farWall)
            }
        }
        for index in state.targets.indices {
            let target = state.targets[index]
            guard target.health > 0, !targetContacts.contains(target.id) else { continue }
            let offset = position - target.position
            let combinedRadius = radius + target.radius
            let squaredSpeed = velocity.dot(velocity)
            guard squaredSpeed > epsilon else { continue }
            let approach = offset.dot(velocity)
            let separation = offset.dot(offset) - combinedRadius * combinedRadius
            let discriminant = approach * approach - squaredSpeed * separation
            guard discriminant >= 0 else { continue }
            let time = separation <= 0 ? 0 : (-approach - sqrt(discriminant)) / squaredSpeed
            let contactOffset = offset + velocity * time
            let distance = contactOffset.length
            let normal = distance > epsilon ? contactOffset * (1 / distance) : velocity * (-1 / ball.speed)
            guard velocity.dot(normal) < -epsilon else { continue }
            consider(time, normal: normal, kind: .target(index))
        }
        return earliest
    }

    private func advanceBall(_ duration: Double, events: inout [GameEvent]) {
        guard var ball = state.ball else { return }
        var remaining = duration
        var contacts = 0
        while remaining > 1e-10, contacts < max(1, tuning.maximumCollisionsPerStep) {
            releaseExitedContacts(ball)
            guard let contact = earliestContact(ball: ball, duration: remaining) else {
                ball.position = ball.position + ball.velocity * remaining
                remaining = 0
                break
            }
            ball.position = ball.position + ball.velocity * contact.time
            remaining = max(0, remaining - contact.time)
            contacts += 1
            switch contact.kind {
            case .receiving:
                guideReceiving(&ball)
            case .side, .farWall:
                ball.velocity = reflected(ball.velocity, normal: contact.normal)
                ball.position = ball.position + contact.normal * tuning.collisionEpsilon
                if ball.position.y <= tuning.receivingBoundaryY { guideReceiving(&ball) }
                events.append(.wallContact)
            case .player:
                noteProgress()
                incomingGuided = false
                resetTargetChain(events: &events)
                if state.stage.isBoss {
                    state.currentRallyReturns += 1
                    state.longestRallyReturns = max(state.longestRallyReturns, state.currentRallyReturns)
                    state.currentBossMatchLongestRallyReturns = max(
                        state.currentBossMatchLongestRallyReturns, state.currentRallyReturns)
                    state.boss?.specialTriggeredForReturn = false
                }
                let offset = (ball.position.x - state.playerX) / tuning.playerHalfWidth
                let centered = abs(offset) <= tuning.centeredContactFraction
                let side: SwingSide = centered ? .block : (offset >= 0 ? .forehand : .backhand)
                ball.velocity = playerReturnVelocity(contactX: ball.position.x,
                                                     speed: ball.speed)
                if mode.isBossRally {
                    let id = state.bossID
                    let apparent = clamp(offset * tuning.maximumOutgoingApparentAngle
                        + rallyMotionAngle(), -tuning.maximumOutgoingApparentAngle,
                        tuning.maximumOutgoingApparentAngle)
                    ball.velocity = ReceivingTrajectory.outgoing(apparentAngle: apparent,
                        at: .init(x: ball.position.x, y: tuning.playerY + ball.radius),
                        speed: min(tuning.maximumBallSpeed, ball.speed),
                        projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
                    let policy = tuning.rallyOpponentConfiguration(for: id)
                    rallyPendingPlayerLane = RallyBallProjection.arrival(of:
                        BallState(position: .init(x: ball.position.x,
                                                  y: tuning.playerY + ball.radius + tuning.collisionEpsilon),
                                  velocity: ball.velocity, radius: ball.radius),
                        atY: activeBossConfiguration.y - ball.radius, tuning: tuning,
                        speedGrowth: policy.speedGrowthPerSecond)?.position.x
                    rallyFlightError = generator.signed() * policy.projectionError
                    playerMotionSamples.removeAll(keepingCapacity: true)
                }
                ball.position.y = tuning.playerY + ball.radius + tuning.collisionEpsilon
                swingSide = side; swingElapsed = 0
                state.playerAnimation = contactAnimation(side)
                events.append(.paddleContact(x: ball.position.x, side: side, centered: centered))
            case .target(let index):
                noteProgress()
                ball.velocity = reflected(ball.velocity, normal: contact.normal)
                ball.position = ball.position + contact.normal * tuning.collisionEpsilon
                let id = state.targets[index].id
                let kind = state.targets[index].kind
                let size = state.targets[index].size
                state.targets[index].health -= 1
                let destroyed = state.targets[index].health <= 0
                // One valid damage contact increments first, then awards its
                // multiplied base/final-hit reward. Walls never modify the chain.
                let previousMultiplier = tuning.comboMultiplier(for: state.targetChain)
                if !state.stage.isBoss { state.targetChain += 1 }
                let multiplier = state.stage.isBoss ? 1 : tuning.comboMultiplier(for: state.targetChain)
                let points = tuning.score(for: kind, size: size, destroyed: destroyed) * multiplier
                state.score += points
                if destroyed { state.targets.remove(at: index); targetContacts.remove(id) }
                else { targetContacts.insert(id) }
                events.append(.targetHit(id: id, kind: kind, destroyed: destroyed, score: points))
                if multiplier != previousMultiplier {
                    events.append(.comboChanged(chain: state.targetChain, multiplier: multiplier))
                }
                if destroyed, state.stage.waveNumber != nil,
                   state.targets.count <= max(0, tuning.cleanupTargetThreshold) {
                    state.ball = nil
                    targetContacts.removeAll(keepingCapacity: true)
                    if state.targets.isEmpty { completeWave(events: &events) }
                    else { changePhase(.cleanup, duration: tuning.cleanupStepDuration, events: &events) }
                    return
                }
                if ball.position.y <= tuning.receivingBoundaryY { guideReceiving(&ball) }
            case .boss:
                let config = activeBossConfiguration
                let powered: Bool
                if mode.isBossRally {
                    let id = state.bossID
                    let policy = tuning.rallyOpponentConfiguration(for: id)
                    powered = id == .banger && state.boss?.specialPhase == .powerWindup
                        && rallyPowerTelegraphTime.map {
                            state.simulationTime - $0 + 1e-10 >= policy.powerLeadTime
                        } == true
                        && ball.speed * policy.powerSpeedMultiplier <= tuning.maximumBallSpeed + 1e-9
                        && rallyBalanceRemaining <= 0.05
                        && abs(state.boss?.lateralVelocity ?? 0)
                           <= policy.maximumLateralSpeed * 0.70
                        && abs(ball.position.x - (state.boss?.x ?? ball.position.x))
                           <= config.halfWidth * 0.80
                    let balanced = rallyBalanceRemaining <= 0.05
                        && abs(state.boss?.lateralVelocity ?? 0)
                           <= policy.maximumLateralSpeed * 0.70
                    let observed = delayedRallyObservation(delay: policy.observationDelay)
                    let older = delayedRallyObservation(delay: policy.observationDelay + 0.12)
                    let observedX = observed?.playerX ?? CourtGeometry.centerX
                    let observedVelocity: Double
                    if let observed, let older, observed.time > older.time {
                        observedVelocity = clamp((observed.playerX - older.playerX)
                            / (observed.time - older.time), -10, 10)
                    } else { observedVelocity = 0 }
                    let shot = RallyShotPlanner.choose(contact: ball, bossY: config.y,
                        bossID: id, observedPlayerX: observedX,
                        observedPlayerVelocity: observedVelocity,
                        previousLandingSide: rallyLastShotSide, variation: generator.unit(),
                        powered: powered, balanced: balanced, tuning: tuning)
                    ball.velocity = shot.velocity
                    rallyLastShotSide = shot.laneSide
                    state.boss?.lastShotPurpose = shot.purpose
                    state.boss?.plannedReceivingX = shot.landingX
                    if let completed = rallyPendingPlayerLane {
                        rallyCompletedLanes.append(completed)
                        if rallyCompletedLanes.count > 4 { rallyCompletedLanes.removeFirst() }
                    }
                    rallyPendingPlayerLane = nil
                } else {
                    let targetX = clamp(state.playerX + generator.signed() * config.returnAimError,
                                        tuning.playerMargin, CourtGeometry.width - tuning.playerMargin)
                    let angle = clamp(atan2(targetX - ball.position.x, config.y - tuning.playerY),
                                      -config.maximumReturnAngle, config.maximumReturnAngle)
                    powered = state.boss?.id == .banger && state.boss?.specialPhase == .powerWindup
                        && ball.speed < tuning.maximumBallSpeed - 0.01
                    let outgoingSpeed = powered
                        ? min(tuning.maximumBallSpeed, ball.speed * max(1, config.powerSpeedMultiplier)) : ball.speed
                    ball.velocity = .init(x: sin(angle) * outgoingSpeed, y: -cos(angle) * outgoingSpeed)
                }
                ball.position.y = config.y - ball.radius - tuning.collisionEpsilon
                state.boss?.returnCount += 1
                state.currentRallyReturns += 1
                state.longestRallyReturns = max(state.longestRallyReturns, state.currentRallyReturns)
                state.currentBossMatchLongestRallyReturns = max(
                    state.currentBossMatchLongestRallyReturns, state.currentRallyReturns)
                events.append(.bossContact(x: ball.position.x))
                if mode.isBossRally {
                    let id = state.bossID
                    let policy = tuning.rallyOpponentConfiguration(for: id)
                    if powered {
                        rallyLastPowerReturn = state.boss?.returnCount ?? rallyLastPowerReturn
                        rallyBalanceRemaining = policy.balanceDuration
                        state.boss?.specialPhase = .powerRecovery
                        state.boss?.specialRemaining = policy.balanceDuration
                        events.append(.bossPowerContact(x: ball.position.x))
                    } else {
                        state.boss?.specialPhase = .idle
                        state.boss?.specialRemaining = 0
                    }
                    rallyPowerTelegraphTime = nil
                    if id == .poacher { considerPoachCommitment(events: &events) }
                } else if powered {
                    state.boss?.specialPhase = .powerRecovery
                    state.boss?.specialRemaining = max(0, config.powerRecoveryDuration)
                    events.append(.bossPowerContact(x: ball.position.x))
                }
            case .miss:
                resetTargetChain(events: &events)
                state.playerAnimation = .miss
                missRemaining = tuning.missAnimationDuration
                swingSide = nil
                if state.recoveriesRemaining > 0 {
                    state.recoveriesRemaining -= 1
                    events.append(.ballRecovered(remaining: state.recoveriesRemaining))
                    prepareRally(duration: tuning.recoveryReadyDuration, events: &events)
                } else if mode.isBossRally {
                    state.boss?.opponentPoints += 1
                    events.append(.opponentPoint(points: state.boss?.opponentPoints ?? 0))
                    if (state.boss?.opponentPoints ?? 0) >= activeBossConfiguration.pointsToWin {
                        finish(won: false, events: &events)
                    } else {
                        prepareRally(duration: tuning.rallyPointReadyDuration, events: &events)
                    }
                } else {
                    state.lives = max(0, state.lives - 1)
                    events.append(.lifeLost(remaining: state.lives))
                    if state.lives == 0 { finish(won: false, events: &events) }
                    else { prepareRally(events: &events) }
                }
                return
            case .bossPoint:
                noteProgress()
                guard state.boss != nil else { return }
                if mode.isBossRally, let completed = rallyPendingPlayerLane {
                    // A winning shot is completed history too. The Poacher may
                    // learn its lane across points without knowing the next shot.
                    rallyCompletedLanes.append(completed)
                    if rallyCompletedLanes.count > 4 { rallyCompletedLanes.removeFirst() }
                    rallyPendingPlayerLane = nil
                }
                state.boss!.points += 1
                state.score += tuning.bossPointScore
                events.append(.bossPoint(points: state.boss!.points))
                if state.boss!.points >= activeBossConfiguration.pointsToWin {
                    state.score += tuning.bossVictoryBonus
                    resolveBossMatch(won: true, events: &events)
                    if mode == .bossSeries,
                       let next = runPlan.next(after: state.stage, bossID: state.bossID) {
                        startStage(next, readyDuration: tuning.rallyPointReadyDuration, events: &events)
                    } else {
                        state.won = true
                        state.playerAnimation = .victory
                        state.ball = ball
                        events.append(.bossDefeated)
                        changePhase(.impact, duration: tuning.impactDuration, events: &events)
                    }
                } else if mode.isBossRally {
                    prepareRally(duration: tuning.rallyPointReadyDuration, events: &events)
                } else { prepareRally(events: &events) }
                return
            }
        }
        // A degenerate dense-contact step drops its unprocessed remainder safely.
        state.ball = ball
    }

    private func noteProgress() {
        noProgressTime = 0
        stallRedirected = false
    }

    private func guideReceiving(_ ball: inout BallState) {
        let incoming = ball.velocity.y < 0
        ball.velocity = ReceivingTrajectory.constrained(ball.velocity, at: ball.position,
            maximumApparentAngle: incoming ? tuning.maximumIncomingApparentAngle : tuning.maximumOutgoingApparentAngle,
            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
        incomingGuided = incoming
    }

    private func completeWave(events: inout [GameEvent]) {
        guard let number = state.stage.waveNumber else { return }
        state.score += tuning.waveBonus
        state.playerAnimation = .victory
        state.ball = nil
        events.append(.waveCleared(number: number))
        changePhase(.impact, duration: tuning.impactDuration, events: &events)
    }

    private func releaseExitedContacts(_ ball: BallState) {
        guard !targetContacts.isEmpty else { return }
        targetContacts = targetContacts.filter { id in
            guard let target = state.targets.first(where: { $0.id == id }) else { return false }
            return (ball.position - target.position).length <= target.radius + ball.radius + tuning.collisionEpsilon * 4
        }
    }

    private func reflected(_ velocity: Vector2, normal: Vector2) -> Vector2 {
        let reflection = velocity - normal * (2 * velocity.dot(normal))
        return limitedVelocity(reflection, outwardNormal: normal)
    }

    private func limitedVelocity(_ velocity: Vector2, outwardNormal: Vector2? = nil) -> Vector2 {
        guard velocity.x.isFinite, velocity.y.isFinite else {
            return .init(x: 0, y: -min(tuning.initialBallSpeed, tuning.maximumBallSpeed))
        }
        let speed = min(velocity.length, tuning.maximumBallSpeed)
        guard velocity.length > 0 else { return .init(x: 0, y: -min(tuning.initialBallSpeed, tuning.maximumBallSpeed)) }
        var result = velocity * (speed / velocity.length)
        let minimumVertical = speed * clamp(tuning.minimumVerticalFraction, 0, 0.8)
        if abs(result.y) < minimumVertical {
            result.y = result.y < 0 ? -minimumVertical : minimumVertical
            result.x = (result.x < 0 ? -1 : 1) * sqrt(max(0, speed * speed - result.y * result.y))
            if let normal = outwardNormal, result.dot(normal) < 0 { result.y = -result.y }
        }
        return result
    }

    private func updateAnimation(_ delta: Double) {
        if state.phase == .impact || state.phase == .celebration || state.won {
            state.playerAnimation = .victory
            return
        }
        if missRemaining > 0 {
            missRemaining = max(0, missRemaining - delta)
            state.playerAnimation = .miss
            return
        }
        if let side = swingSide {
            swingElapsed += delta
            if swingElapsed < tuning.contactDuration { state.playerAnimation = contactAnimation(side) }
            else if swingElapsed < tuning.contactDuration + tuning.followThroughDuration {
                state.playerAnimation = side == .forehand ? .forehandFollowThrough : (side == .backhand ? .backhandFollowThrough : .block)
            } else if swingElapsed < tuning.contactDuration + tuning.followThroughDuration + tuning.recoveryDuration {
                state.playerAnimation = side == .forehand ? .forehandRecovery : (side == .backhand ? .backhandRecovery : .ready)
            } else { swingSide = nil; state.playerAnimation = .ready }
            return
        }
        state.playerAnimation = .ready
        guard state.phase == .playing, let ball = state.ball, ball.velocity.y < 0 else { return }
        let untilContact = (tuning.playerY + ball.radius - ball.position.y) / ball.velocity.y
        guard untilContact >= 0, untilContact <= tuning.anticipationDuration else { return }
        let contactX = ball.position.x + ball.velocity.x * untilContact
        guard abs(contactX - state.playerX) <= tuning.playerHalfWidth + ball.radius else { return }
        let forehand = contactX >= state.playerX
        state.playerAnimation = untilContact <= tuning.swingDuration
            ? (forehand ? .forehandSwing : .backhandSwing)
            : (forehand ? .forehandAnticipation : .backhandAnticipation)
    }

    private func contactAnimation(_ side: SwingSide) -> PlayerAnimation {
        switch side { case .forehand: return .forehandContact; case .backhand: return .backhandContact; case .block: return .block }
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
