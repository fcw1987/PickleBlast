import Foundation

/// Gameplay values are in court feet and seconds; rendering never changes them.
public struct GameTuning: Equatable, Sendable {
    /// Absolute values for this revision; do not reapply the baseline percentages.
    public static let revision = "easier-returns-1"
    public var fixedStep: Double = 1.0 / 120.0
    public var maximumFrameDelta: Double = 0.10
    public var maximumStepsPerFrame: Int = 12
    public var maximumCollisionsPerStep: Int = 8
    public var collisionEpsilon: Double = 0.000_01
    public var initialLives: Int = 3
    public var playerY: Double = 2.2
    public var playerHalfWidth: Double = 3.25
    public var playerMargin: Double = 1.1
    public var ballRadius: Double = 0.30
    public var initialBallSpeed: Double = 26
    public var maximumBallSpeed: Double = 46
    // Screen-angle policy uses a conservative envelope of the unchanged native projections.
    public var receivingBoundaryY: Double = 22
    public var maximumIncomingApparentAngle: Double = .pi * 35 / 180
    public var maximumOutgoingApparentAngle: Double = .pi * 45 / 180
    public var receivingProjectionSlopeFactor: Double = 2.434
    public var stallNoProgressDuration: Double = 8
    public var stallShallowFraction: Double = 0.35
    public var stallRecoveryVerticalFraction: Double = 0.45
    public var playerVisualReachHorizontalFraction: Double = 0.52
    public var playerVisualReachVerticalFraction: Double = 0.30
    public var freeRecoveriesPerStage: Int = 2
    public var recoveryReadyDuration: Double = 0.75
    public var cleanupTargetThreshold: Int = 4
    public var cleanupStepDuration: Double = 0.10
    public var minimumVerticalFraction: Double = 0.24
    public var centeredContactFraction: Double = 0.20
    // Below every authored target, so a new ball never spawns inside a target.
    public var launchY: Double = 21.5
    public var readyDuration: Double = 1.15
    public var resumeDuration: Double = 0.85
    public var anticipationDuration: Double = 0.22
    public var swingDuration: Double = 0.055
    public var contactDuration: Double = 0.065
    public var followThroughDuration: Double = 0.12
    public var recoveryDuration: Double = 0.16
    public var missAnimationDuration: Double = 0.40
    public var targetRadius: Double = 1.2
    public var smallTargetRadius: Double = 0.50
    public var mediumTargetRadius: Double = 0.75
    public var basketTargetRadius: Double = 0.85
    public var largeTargetRadius: Double = 0.95
    public var paddleScore: Int = 100
    public var mediumPaddleHitScore: Int = 125
    public var mediumPaddleDestructionBonus: Int = 100
    public var largePaddleHitScore: Int = 200
    public var largePaddleDestructionBonus: Int = 200
    public var comboMultipliers: [Int] = [1, 2, 3, 3, 5]
    public var coneScore: Int = 125
    public var basketHitScore: Int = 75
    public var basketDestroyScore: Int = 175
    public var waveBonus: Int = 250
    public var bossPointScore: Int = 500
    public var bossVictoryBonus: Int = 1_000
    public var impactDuration: Double = 0.20
    public var celebrationDuration: Double = 2.0
    public var bossCelebrationDuration: Double = 4.6
    public var blackoutDuration: Double = 0.18
    public var celebrationCapacity: Int = 128
    public var celebrationEmissionRate: Double = 60
    public var celebrationBallRadius: Double = 4.2
    public var boss: BossConfiguration = BossConfiguration()
    public var banger: BossConfiguration = .banger
    public var poacher: BossConfiguration = .poacher
    /// Separate Boss Rally behavior. The accepted Arcade Wall uses `boss` only.
    public var rallyWall: RallyOpponentConfiguration = .wall
    public var rallyBanger: RallyOpponentConfiguration = .banger
    public var rallyPoacher: RallyOpponentConfiguration = .poacher
    public var rallyPointReadyDuration: Double = 1.0
    /// Experimental contact-only movement influence. Disabled for the playable build.
    public var rallyMotionInfluenceEnabled: Bool = false
    public var rallyMotionSampleWindow: Double = 0.12
    public var rallyMotionDeadband: Double = 0.20
    public var rallyMotionMaximumApparentAngle: Double = .pi * 4 / 180
    public init() {}
    public func bossConfiguration(for id: BossID) -> BossConfiguration {
        switch id {
        case .wall: return boss
        case .banger: return banger
        case .poacher: return poacher
        }
    }
    public func rallyOpponentConfiguration(for id: BossID) -> RallyOpponentConfiguration {
        switch id {
        case .wall: return rallyWall
        case .banger: return rallyBanger
        case .poacher: return rallyPoacher
        }
    }
    public func comboMultiplier(for chain: Int) -> Int {
        guard chain > 0, !comboMultipliers.isEmpty else { return 1 }
        return max(1, comboMultipliers[min(chain, comboMultipliers.count) - 1])
    }

    /// Unmultiplied damage award. Destruction replaces the basket hit award and
    /// adds the paddle bonus exactly once, on its final damaging contact.
    public func score(for kind: TargetKind, size: TargetSize = .small, destroyed: Bool) -> Int {
        switch kind {
        case .paddle:
            switch size {
            case .small: return paddleScore
            case .medium: return mediumPaddleHitScore + (destroyed ? mediumPaddleDestructionBonus : 0)
            case .large: return largePaddleHitScore + (destroyed ? largePaddleDestructionBonus : 0)
            }
        case .cone: return coneScore
        case .basket: return destroyed ? basketDestroyScore : basketHitScore
        }
    }
}

/// Match-only locomotion, observation and shot policy. All values are court feet
/// and seconds. Geometry, collision reach and Arcade tuning remain in BossConfiguration.
public struct RallyOpponentConfiguration: Equatable, Sendable {
    public var maximumLateralSpeed: Double
    public var lateralAcceleration: Double
    public var lateralBraking: Double
    public var steeringDeadband: Double = 0.10
    public var observationDelay: Double
    public var decisionPeriod: Double
    public var projectionError: Double
    public var recoveryBias: Double = 0.45
    public var balanceDuration: Double = 0.45
    public var minimumBalanceMobility: Double = 0.76
    public var powerCooldownReturns: Int = 3
    public var powerLeadTime: Double = 0.25
    public var powerSpeedMultiplier: Double = 1.16
    public var speedGrowthPerSecond: Double = 0.16
    public var poachHistoryLength: Int = 3
    public var poachMinimumConfidence: Int = 2
    public var poachLeadTime: Double = 0.30
    public var poachCommitmentOffset: Double = 2.8
    public var poachCooldownReturns: Int = 2
    public init(maximumLateralSpeed: Double, lateralAcceleration: Double,
                lateralBraking: Double, observationDelay: Double,
                decisionPeriod: Double, projectionError: Double) {
        self.maximumLateralSpeed = maximumLateralSpeed
        self.lateralAcceleration = lateralAcceleration
        self.lateralBraking = lateralBraking
        self.observationDelay = observationDelay
        self.decisionPeriod = decisionPeriod
        self.projectionError = projectionError
    }
    public static var wall: Self {
        .init(maximumLateralSpeed: 7.2, lateralAcceleration: 24,
              lateralBraking: 30, observationDelay: 0.20,
              decisionPeriod: 0.09, projectionError: 0.18)
    }
    public static var banger: Self {
        .init(maximumLateralSpeed: 8.8, lateralAcceleration: 29,
              lateralBraking: 35, observationDelay: 0.20,
              decisionPeriod: 0.10, projectionError: 0.24)
    }
    public static var poacher: Self {
        var value = Self(maximumLateralSpeed: 9.4, lateralAcceleration: 31,
                         lateralBraking: 36, observationDelay: 0.17,
                         decisionPeriod: 0.08, projectionError: 0.28)
        value.poachCommitmentOffset = 3.0
        return value
    }
}

public struct BossConfiguration: Equatable, Sendable {
    public var name: String = "The Wall"
    public var y: Double = 40.7
    public var maximumReturnAngle: Double = .pi / 3
    public var halfWidth: Double = 1.75
    public var movementSpeed: Double = 5.5
    public var reactionDelay: Double = 0.22
    public var aimingError: Double = 1.0
    public var returnAimError: Double = 2.0
    public var accelerationPerSecond: Double = 0.65
    public var pointsToWin: Int = 3
    // Zero frequency disables a special. The Wall's accepted behavior stays
    // entirely on its original path and ignores these new settings.
    public var powerEveryReturns: Int = 0
    public var firstPowerReturn: Int = 0
    public var powerSpeedMultiplier: Double = 1
    public var powerRecoveryDuration: Double = 0
    public var powerRecoveryMovementSpeed: Double = 0
    public var powerTelegraphBoundaryY: Double = CourtGeometry.netY
    public var minimumPowerTelegraphLeadTime: Double = 0.30
    public var poachEveryReturns: Int = 0
    public var poachTriggerBoundaryY: Double = CourtGeometry.netY
    public var poachMinimumSideOffset: Double = 1.5
    public var poachCommitmentDistance: Double = 0
    public var poachHoldDuration: Double = 0
    public var poachRecoveryDuration: Double = 0
    public var poachRecoveryMovementSpeed: Double = 0
    public init() {}

    public static var banger: BossConfiguration {
        var value = BossConfiguration()
        value.name = "The Banger"
        value.movementSpeed = 5.9
        value.reactionDelay = 0.26
        value.aimingError = 1.1
        value.returnAimError = 2.2
        value.powerEveryReturns = 3
        value.firstPowerReturn = 2
        value.powerSpeedMultiplier = 1.35
        value.powerRecoveryDuration = 2.3
        value.powerRecoveryMovementSpeed = 0.6
        return value
    }

    public static var poacher: BossConfiguration {
        var value = BossConfiguration()
        value.name = "The Poacher"
        value.movementSpeed = 7.0
        value.reactionDelay = 0.28
        value.aimingError = 1.3
        value.returnAimError = 2.4
        value.poachEveryReturns = 3
        value.poachMinimumSideOffset = 1.5
        value.poachCommitmentDistance = 4.0
        value.poachHoldDuration = 2.3
        value.poachRecoveryDuration = 1.0
        value.poachRecoveryMovementSpeed = 3.0
        return value
    }
}
