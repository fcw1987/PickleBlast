import Foundation
#if canImport(PickleBlastCore)
import PickleBlastCore
#endif

/// Reproducible, bounded player controls for boss-behavior evaluation.
///
/// This controller receives only the ball, phase, player position, and public
/// gameplay events. It never reads BossState, an engine prediction, a future
/// input sample, or a hidden boss target. All player motion is emitted as a
/// bounded Crown delta that callers apply through GameEngine.movePlayer.
public struct BossPolicyObservation: Equatable, Sendable {
    public let time: Double
    public let phase: GamePhase
    public let ball: BallState?
    public let playerX: Double

    public init(time: Double, phase: GamePhase, ball: BallState?, playerX: Double) {
        self.time = time
        self.phase = phase
        self.ball = ball
        self.playerX = playerX
    }
}

public enum BossPlayerPolicy: String, CaseIterable, Codable, Sendable {
    case neutral
    case placer
    case patternSetter
    case powerResponder
    case casual
    case stationary
    /// Deliberately impaired synthetic stress control; not a human calibration.
    case lateCasual

    public static let frozenComparisonCases: [BossPlayerPolicy] = [
        .neutral, .placer, .patternSetter, .powerResponder, .casual, .stationary
    ]
}

public struct BossPolicyConfiguration: Equatable, Sendable {
    public let observationDelay: Double
    public let decisionInterval: Double
    public let maximumMovementSpeed: Double
    public let movementAcceleration: Double
    public let movementBraking: Double
    public let broadLaneOffset: Double

    public init(observationDelay: Double, decisionInterval: Double = 0.10,
                maximumMovementSpeed: Double, movementAcceleration: Double,
                movementBraking: Double? = nil, broadLaneOffset: Double = 0.68) {
        self.observationDelay = max(0, observationDelay)
        self.decisionInterval = max(0.025, decisionInterval)
        self.maximumMovementSpeed = max(0, maximumMovementSpeed)
        self.movementAcceleration = max(0, movementAcceleration)
        self.movementBraking = max(0, movementBraking ?? movementAcceleration)
        self.broadLaneOffset = min(0.90, max(0.15, abs(broadLaneOffset)))
    }

    public static func profile(for policy: BossPlayerPolicy) -> Self {
        switch policy {
        case .neutral:
            .init(observationDelay: 0.18, maximumMovementSpeed: 8.0,
                  movementAcceleration: 28, movementBraking: 30)
        case .placer:
            .init(observationDelay: 0.20, maximumMovementSpeed: 8.0,
                  movementAcceleration: 28, movementBraking: 30)
        case .patternSetter:
            .init(observationDelay: 0.22, maximumMovementSpeed: 8.0,
                  movementAcceleration: 28, movementBraking: 30)
        case .powerResponder:
            .init(observationDelay: 0.20, maximumMovementSpeed: 8.5,
                  movementAcceleration: 30, movementBraking: 32)
        case .casual:
            .init(observationDelay: 0.32, maximumMovementSpeed: 5.5,
                  movementAcceleration: 16, movementBraking: 18)
        case .stationary:
            .init(observationDelay: 0.32, maximumMovementSpeed: 0,
                  movementAcceleration: 0, movementBraking: 0)
        case .lateCasual:
            .init(observationDelay: 0.45, maximumMovementSpeed: 4,
                  movementAcceleration: 14, movementBraking: 16)
        }
    }
}

public struct BossPolicyDiagnostics: Equatable, Sendable {
    public let observationTime: Double?
    public let predictedInterceptX: Double?
    public let selectedContactOffset: Double
    public let targetX: Double
    public let targetUpdateTime: Double
    public let predictedFlightTime: Double?
}

public struct BossEvaluationPolicy: Sendable {
    public let kind: BossPlayerPolicy
    public let configuration: BossPolicyConfiguration
    private let tuning: GameTuning
    private var rng: UInt64
    private var observations: [BossPolicyObservation] = []
    private var nextDecisionTime = 0.0
    private var targetX = CourtGeometry.centerX
    private let initialStagingX: Double
    private var hasStartedRun = false
    private var playerVelocity = 0.0
    private var completedPlayerContacts = 0
    private var observedPowerContact = false
    private var priorShotOffset = 0.0
    private var incomingFlightID: UInt64 = 0
    private var selectedOffsetFlightID: UInt64?
    private var selectedFlightOffset = 0.0
    private var casualError = 0.0
    private var lateCasualErrorFlightID: UInt64?
    private var lateCasualPositioningError = 0.0
    private var diagnostics = BossPolicyDiagnostics(observationTime: nil,
        predictedInterceptX: nil, selectedContactOffset: 0,
        targetX: CourtGeometry.centerX, targetUpdateTime: 0,
        predictedFlightTime: nil)

    public init(kind: BossPlayerPolicy, seed: UInt64, tuning: GameTuning = GameTuning(),
                configuration: BossPolicyConfiguration? = nil,
                startingPositionSeed: UInt64? = nil) {
        self.kind = kind
        self.configuration = configuration ?? .profile(for: kind)
        self.tuning = tuning
        self.rng = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        self.targetX = CourtGeometry.centerX
        let staging = [2.5, 5.0, 7.5, 10.0, 12.5, 15.0, 17.5]
        self.initialStagingX = staging[Int((startingPositionSeed ?? seed) % UInt64(staging.count))]
    }

    public var diagnosticState: BossPolicyDiagnostics { diagnostics }

    /// Append only public, already-renderable state after an ordinary engine step.
    public mutating func observe(_ observation: BossPolicyObservation,
                                 events: [GameEvent] = []) {
        guard observation.time.isFinite, observation.playerX.isFinite else { return }
        observations.append(observation)
        let keepAfter = observation.time - max(1.0, configuration.observationDelay + 0.5)
        observations.removeAll { $0.time < keepAfter }

        for event in events {
            switch event {
            case .paddleContact:
                completedPlayerContacts += 1
                if kind == .casual { casualError = signedRandom() * 0.75 }
            case .bossContact:
                incomingFlightID &+= 1
            case .bossPowerContact:
                observedPowerContact = true
            case .phaseChanged(.playing):
                hasStartedRun = true
                incomingFlightID &+= 1
            default:
                break
            }
        }

        guard observation.time + 1e-9 >= nextDecisionTime else { return }
        nextDecisionTime = observation.time + configuration.decisionInterval
        chooseTarget(at: observation.time)
    }

    /// Return one ordinary Crown delta. The caller applies it with
    /// `engine.movePlayer(crownDelta:delta,sensitivity:1)` every simulation step.
    public mutating func movementDelta(currentPlayerX: Double, elapsed: Double) -> Double {
        guard kind != .stationary, currentPlayerX.isFinite, elapsed.isFinite, elapsed > 0,
              configuration.maximumMovementSpeed > 0 else { return 0 }
        let dt = min(elapsed, 0.10)
        let desiredVelocity = clamp((targetX - currentPlayerX) * 4.0,
            -configuration.maximumMovementSpeed, configuration.maximumMovementSpeed)
        let acceleratingAgainstMotion = desiredVelocity * playerVelocity < -1e-9
        let decelerating = abs(desiredVelocity) < abs(playerVelocity) - 1e-9
        let rate = acceleratingAgainstMotion || decelerating
            ? configuration.movementBraking : configuration.movementAcceleration
        let maxVelocityChange = rate * dt
        playerVelocity += clamp(desiredVelocity - playerVelocity,
                                -maxVelocityChange, maxVelocityChange)
        playerVelocity = clamp(playerVelocity, -configuration.maximumMovementSpeed,
                               configuration.maximumMovementSpeed)
        let delta = playerVelocity * dt
        let nextX = clamp(currentPlayerX + delta,
                          tuning.playerMargin, CourtGeometry.width - tuning.playerMargin)
        if nextX == tuning.playerMargin || nextX == CourtGeometry.width - tuning.playerMargin {
            if (nextX == tuning.playerMargin && playerVelocity < 0)
                || (nextX == CourtGeometry.width - tuning.playerMargin && playerVelocity > 0) {
                playerVelocity = 0
            }
        }
        return nextX - currentPlayerX
    }

    private mutating func chooseTarget(at time: Double) {
        guard kind != .stationary else {
            targetX = CourtGeometry.centerX
            diagnostics = .init(observationTime: nil, predictedInterceptX: nil,
                selectedContactOffset: 0, targetX: targetX,
                targetUpdateTime: time, predictedFlightTime: nil)
            return
        }
        if !hasStartedRun, let sample = observations.last(where: { $0.time <= time + 1e-9 }),
           sample.phase == .ready {
            targetX = initialStagingX
            diagnostics = .init(observationTime: sample.time,
                predictedInterceptX: nil, selectedContactOffset: 0,
                targetX: targetX, targetUpdateTime: time,
                predictedFlightTime: nil)
            return
        }
        let cutoff = time - configuration.observationDelay
        guard let sample = observations.last(where: { $0.time <= cutoff + 1e-9 }) else { return }
        guard sample.phase == .playing, let ball = sample.ball,
              ball.velocity.y < -1e-6,
              let intercept = predictPlayerIntercept(ball) else {
            targetX = CourtGeometry.centerX
            diagnostics = .init(observationTime: sample.time, predictedInterceptX: nil,
                selectedContactOffset: 0, targetX: targetX,
                targetUpdateTime: time, predictedFlightTime: nil)
            return
        }

        if kind == .lateCasual {
            if lateCasualErrorFlightID != incomingFlightID {
                lateCasualPositioningError = signedRandom() * 4.5
                lateCasualErrorFlightID = incomingFlightID
            }
            // This impaired control only mispositions its feet. It never aims
            // the return toward a lane or uses boss-state diagnostics.
            targetX = clamp(intercept.x + lateCasualPositioningError,
                            tuning.playerMargin, CourtGeometry.width - tuning.playerMargin)
            diagnostics = .init(observationTime: sample.time,
                predictedInterceptX: intercept.x, selectedContactOffset: 0,
                targetX: targetX, targetUpdateTime: time,
                predictedFlightTime: intercept.time)
            return
        }

        if selectedOffsetFlightID != incomingFlightID {
            let requestedOffset = contactOffset(for: ball)
            let minimumOffset = (intercept.x - (CourtGeometry.width - tuning.playerMargin))
                / tuning.playerHalfWidth
            let maximumOffset = (intercept.x - tuning.playerMargin) / tuning.playerHalfWidth
            selectedFlightOffset = clamp(requestedOffset, minimumOffset, maximumOffset)
            selectedOffsetFlightID = incomingFlightID
            if kind == .powerResponder { priorShotOffset = selectedFlightOffset }
        }
        let offset = selectedFlightOffset
        // playerReturnVelocity uses (ballX - playerX) / halfWidth, so this
        // target places contact to one side without moving the ball or skipping
        // the engine's assistance and contact checks.
        targetX = clamp(intercept.x - offset * tuning.playerHalfWidth,
                        tuning.playerMargin, CourtGeometry.width - tuning.playerMargin)
        diagnostics = .init(observationTime: sample.time,
            predictedInterceptX: intercept.x, selectedContactOffset: offset,
            targetX: targetX, targetUpdateTime: time,
            predictedFlightTime: intercept.time)
    }

    private mutating func contactOffset(for ball: BallState) -> Double {
        let lane = configuration.broadLaneOffset
        switch kind {
        case .neutral:
            return 0
        case .placer:
            return completedPlayerContacts.isMultiple(of: 2) ? -lane : lane
        case .patternSetter:
            let twoShotBlock = (completedPlayerContacts / 2).isMultiple(of: 2)
            let sign = twoShotBlock ? -1.0 : 1.0
            return sign * lane
        case .powerResponder:
            if observedPowerContact || ball.speed >= tuning.initialBallSpeed * 1.22 {
                observedPowerContact = false
                return priorShotOffset == 0 ? -lane : -priorShotOffset
            }
            return 0
        case .casual:
            return clamp(signedRandom() * 0.30 + casualError / tuning.playerHalfWidth,
                         -0.55, 0.55)
        case .stationary:
            return 0
        case .lateCasual:
            return 0
        }
    }

    /// Project observed state with the core's pure fixed-step helper, including
    /// the side walls, speed limits, and receiving-angle correction. This policy
    /// deliberately assumes zero unseen speed growth; speed remains observable.
    private func predictPlayerIntercept(_ observed: BallState) -> (x: Double, time: Double)? {
        let contactY = tuning.playerY + observed.radius
        guard let arrival = RallyBallProjection.arrival(of: observed, atY: contactY,
            tuning: tuning, speedGrowth: 0,
            receivingAlreadyGuided: observed.position.y <= tuning.receivingBoundaryY,
            horizon: 8) else { return nil }
        return (arrival.position.x, arrival.time)
    }

    private mutating func signedRandom() -> Double {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        let unit = Double(rng >> 11) / Double(UInt64(1) << 53)
        return unit * 2 - 1
    }
}

private func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(upper, max(lower, value))
}
