import Foundation

public struct Vector2: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = Vector2(x: 0, y: 0)
    public var length: Double { hypot(x, y) }
    public static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func * (lhs: Self, rhs: Double) -> Self { .init(x: lhs.x * rhs, y: lhs.y * rhs) }
    public func dot(_ other: Self) -> Double { x * other.x + y * other.y }
}

public enum GamePhase: String, Equatable, Sendable {
    case ready, playing, cleanup, impact, celebration, blackout, results
}

public enum GameStage: Equatable, Sendable {
    case wave(Int)
    case boss
    public var waveNumber: Int? { if case let .wave(number) = self { return number }; return nil }
    public var isBoss: Bool { self == .boss }
}

public enum BossID: String, CaseIterable, Codable, Hashable, Sendable {
    case wall, banger, poacher, dinker, lobber
    /// The accepted three-match run remains independent of the selectable roster.
    public static let seriesOrder: [BossID] = [.wall, .banger, .poacher]
}

public enum GameMode: Equatable, Sendable {
    case arcade
    case bossRally(BossID)
    case bossSeries

    public var isBossRally: Bool {
        switch self {
        case .arcade: return false
        case .bossRally, .bossSeries: return true
        }
    }
}

/// A short ordered run. Future authored challenges can provide another stage
/// list without changing collision or stage-transition authority.
struct RunPlan {
    struct Entry {
        let stage: GameStage
        let bossID: BossID?
        init(stage: GameStage, bossID: BossID? = nil) {
            self.stage = stage; self.bossID = bossID
        }
    }
    let stages: [Entry]
    init(mode: GameMode) {
        switch mode {
        case .arcade:
            stages = [.init(stage: .wave(1)), .init(stage: .wave(2)),
                      .init(stage: .wave(3)), .init(stage: .boss, bossID: .wall)]
        case let .bossRally(id): stages = [.init(stage: .boss, bossID: id)]
        case .bossSeries:
            stages = [.init(stage: .boss, bossID: .wall),
                      .init(stage: .boss, bossID: .banger),
                      .init(stage: .boss, bossID: .poacher)]
        }
    }
    func next(after stage: GameStage, bossID: BossID) -> Entry? {
        // Authoritative state selects the active entry. Boss identity makes
        // consecutive .boss stages distinct without a second progression state.
        guard let index = stages.firstIndex(where: {
            $0.stage == stage && (!stage.isBoss || $0.bossID == bossID)
        }), stages.indices.contains(index + 1) else { return nil }
        return stages[index + 1]
    }
}

public struct BossMatchResult: Equatable, Sendable {
    public let bossID: BossID
    public let won: Bool
    /// Score earned in this match, including its victory bonus when won.
    public let score: Int
    public let longestRallyReturns: Int
    public init(bossID: BossID, won: Bool, score: Int, longestRallyReturns: Int) {
        self.bossID = bossID; self.won = won; self.score = score
        self.longestRallyReturns = longestRallyReturns
    }
}

public enum BossSide: String, Equatable, Sendable { case left, right }
public enum BossSpecialPhase: String, Equatable, Sendable {
    case idle, powerWindup, powerRecovery, poachCommitment, poachRecovery
    case softWindup, softRecovery, lobWindup, lobRecovery
}

public enum SwingSide: String, Equatable, Sendable { case forehand, backhand, block }

public enum PlayerAnimation: String, CaseIterable, Equatable, Sendable {
    case ready
    case forehandAnticipation, forehandSwing, forehandContact, forehandFollowThrough, forehandRecovery
    case backhandAnticipation, backhandSwing, backhandContact, backhandFollowThrough, backhandRecovery
    case block, miss, victory
}

public struct BallState: Equatable, Sendable {
    public var position: Vector2
    public var velocity: Vector2
    public var radius: Double
    public var speed: Double { velocity.length }
    public init(position: Vector2, velocity: Vector2, radius: Double = 0.30) {
        self.position = position; self.velocity = velocity; self.radius = radius
    }
}

public enum TargetKind: String, CaseIterable, Equatable, Sendable {
    case paddle, cone, basket
    public var maximumHealth: Int { self == .basket ? 2 : 1 }
}

public enum TargetSize: String, CaseIterable, Equatable, Sendable {
    case small, medium, large
    public var maximumHealth: Int {
        switch self { case .small: return 1; case .medium: return 2; case .large: return 3 }
    }
}

public struct TargetState: Equatable, Sendable, Identifiable {
    public let id: Int
    public let kind: TargetKind
    public var position: Vector2
    public var radius: Double
    public var health: Int
    public let size: TargetSize
    public let maximumHealth: Int
    public var isDamaged: Bool { health < maximumHealth }
    public init(id: Int, kind: TargetKind, position: Vector2, radius: Double = 1.2, health: Int? = nil,
                size: TargetSize = .small, maximumHealth: Int? = nil) {
        self.id = id; self.kind = kind; self.position = position; self.radius = radius
        self.size = size
        self.maximumHealth = max(1, maximumHealth ?? (kind == .basket ? 2 : size.maximumHealth))
        self.health = health ?? self.maximumHealth
    }
}

public struct BossState: Equatable, Sendable {
    public var id: BossID
    public var x: Double
    public var movementTarget: Double
    public var reactionRemaining: Double
    public var points: Int
    /// Points won by the opponent in Boss Rally. `points` remains the player's
    /// points, including the accepted Arcade boss encounter.
    public var opponentPoints: Int
    public var returnCount: Int
    public var lateralVelocity: Double
    /// Bounded Rally-only diagnostics for visual and scenario verification.
    public var lastShotPurpose: RallyShotPurpose?
    public var plannedReceivingX: Double?
    public var lastObservedTime: Double?
    public var predictedInterceptX: Double?
    public var reachableLeftX: Double?
    public var reachableRightX: Double?
    public var specialPhase: BossSpecialPhase
    public var specialRemaining: Double
    public var committedSide: BossSide?
    public var committedTargetX: Double?
    /// Expected completed-shot lane, distinct from the early movement offset.
    public var committedReadX: Double?
    public var specialTriggeredForReturn: Bool
    public init(id: BossID = .wall, x: Double = 10, movementTarget: Double = 10,
                reactionRemaining: Double = 0, points: Int = 0, opponentPoints: Int = 0,
                returnCount: Int = 0, lateralVelocity: Double = 0,
                lastShotPurpose: RallyShotPurpose? = nil, plannedReceivingX: Double? = nil,
                lastObservedTime: Double? = nil, predictedInterceptX: Double? = nil,
                reachableLeftX: Double? = nil, reachableRightX: Double? = nil,
                specialPhase: BossSpecialPhase = .idle, specialRemaining: Double = 0,
                committedSide: BossSide? = nil, committedTargetX: Double? = nil, committedReadX: Double? = nil,
                specialTriggeredForReturn: Bool = false) {
        self.id = id; self.x = x; self.movementTarget = movementTarget
        self.reactionRemaining = reactionRemaining; self.points = points
        self.opponentPoints = opponentPoints
        self.returnCount = returnCount; self.lateralVelocity = lateralVelocity
        self.lastShotPurpose = lastShotPurpose; self.plannedReceivingX = plannedReceivingX
        self.lastObservedTime = lastObservedTime
        self.predictedInterceptX = predictedInterceptX
        self.reachableLeftX = reachableLeftX; self.reachableRightX = reachableRightX
        self.specialPhase = specialPhase
        self.specialRemaining = specialRemaining; self.committedSide = committedSide
        self.committedTargetX = committedTargetX
        self.committedReadX = committedReadX
        self.specialTriggeredForReturn = specialTriggeredForReturn
    }
}

public struct GameState: Equatable, Sendable {
    public var mode: GameMode = .arcade
    public var phase: GamePhase = .ready
    public var stage: GameStage = .wave(1)
    public var playerX: Double = CourtGeometry.centerX
    public var playerAnimation: PlayerAnimation = .ready
    public var ball: BallState?
    public var rallyShot: RallyShotState?
    public var targets: [TargetState] = []
    public var boss: BossState?
    public var score: Int = 0
    public var targetChain: Int = 0
    /// Arcade allowances, or a single earned Boss Rally save (zero or one).
    /// Boss Rally banks this across won points, but never across matches.
    public var recoveriesRemaining: Int = 2
    public var lives: Int = 3
    public var won: Bool = false
    public var isPaused: Bool = false
    public var resumeCountdown: Double = 0
    public var phaseTimeRemaining: Double = 0
    public var rallyTime: Double = 0
    /// Both players' returns, retained for existing match records.
    public var currentRallyReturns: Int = 0
    /// Successful PLAYER paddle contacts within this point. Boss contacts,
    /// walls and serves do not count; either side's point or a save resets it.
    public var consecutivePlayerReturns: Int = 0
    public var longestRallyReturns: Int = 0
    public var currentBossMatchLongestRallyReturns: Int = 0
    public var completedBossMatches: [BossMatchResult] = []
    public var simulationTime: Double = 0
    public var crownInput: Double = CourtGeometry.centerX
    public var crownVelocity: Double = 0
    public var celebration: CelebrationPool
    public init(celebration: CelebrationPool = CelebrationPool()) { self.celebration = celebration }
    public var waveNumber: Int { stage.waveNumber ?? 3 }
    public var bossPoints: Int { boss?.points ?? 0 }
    public var playerRallyPoints: Int { mode == .arcade ? 0 : (boss?.points ?? 0) }
    public var opponentRallyPoints: Int { mode == .arcade ? 0 : (boss?.opponentPoints ?? 0) }
    public var bossID: BossID {
        if let boss { return boss.id }
        if case let .bossRally(id) = mode { return id }
        return .wall
    }
}

public enum GameEvent: Equatable, Sendable {
    case phaseChanged(GamePhase)
    case paddleContact(x: Double, side: SwingSide, centered: Bool)
    case targetHit(id: Int, kind: TargetKind, destroyed: Bool, score: Int)
    case targetCleaned(id: Int, kind: TargetKind, score: Int)
    case ballRecovered(remaining: Int)
    /// Emitted once on a Boss Rally save bank transition from zero to one.
    case recoveryEarned
    /// Emitted at each 20-return boundary, including while a save is banked.
    case rallyMilestone(returns: Int)
    case comboChanged(chain: Int, multiplier: Int)
    case wallContact
    case lifeLost(remaining: Int)
    case waveCleared(number: Int)
    case bossIncoming
    case rallyShotPrepared(rallyID: UInt64, shotID: UInt64, kind: RallyShotKind)
    case rallyShotLaunched(rallyID: UInt64, shotID: UInt64, kind: RallyShotKind)
    case bossContact(x: Double)
    case bossPowerTelegraph
    case bossPowerContact(x: Double)
    case bossPoachCommitment(side: BossSide, targetX: Double)
    case bossPoachRecovery
    case bossPoint(points: Int)
    case opponentPoint(points: Int)
    case bossDefeated
    case bossMatchEnded(result: BossMatchResult)
    case runEnded(won: Bool, score: Int)
}
