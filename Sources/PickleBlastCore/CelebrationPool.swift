import Foundation

/// Small deterministic generator shared by boss decisions and visual celebrations.
struct SeededGenerator: Equatable, Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
    mutating func signed() -> Double { unit() * 2 - 1 }
}

public struct CelebrationParticle: Equatable, Sendable {
    public var isActive: Bool = false
    public var position: Vector2 = .zero
    public var velocity: Vector2 = .zero
    public var rotation: Double = 0
    public var angularVelocity: Double = 0
    public var scale: Double = 1
    public init() {}
}

/// A fixed-capacity pure model. Positions are normalized display units, not court feet.
public struct CelebrationPool: Equatable, Sendable {
    public private(set) var particles: [CelebrationParticle]
    public private(set) var activeCount: Int = 0
    public let width: Double
    public let height: Double
    public let emissionRate: Double
    public let baseRadius: Double
    private var emissionAccumulator: Double = 0
    private var generator: SeededGenerator
    public init(capacity: Int = 128, width: Double = 100, height: Double = 120,
                emissionRate: Double = 60, baseRadius: Double = 4.2, seed: UInt64 = 0xCA5CADE) {
        particles = Array(repeating: CelebrationParticle(), count: max(0, min(256, capacity)))
        self.width = width.isFinite ? max(1, width) : 100
        self.height = height.isFinite ? max(1, height) : 120
        self.emissionRate = emissionRate.isFinite ? max(0, emissionRate) : 60
        self.baseRadius = baseRadius.isFinite ? max(0.1, baseRadius) : 4.2
        self.generator = SeededGenerator(seed: seed)
    }
    public mutating func reset(seed: UInt64? = nil) {
        activeCount = 0; emissionAccumulator = 0
        for index in particles.indices { particles[index].isActive = false }
        if let seed { generator = SeededGenerator(seed: seed) }
    }
    public mutating func update(delta: Double) {
        guard delta.isFinite, delta > 0 else { return }
        // Engine calls fixed steps. Public callers cannot cause an unbounded catch-up.
        let elapsed = min(delta, 0.10)
        emissionAccumulator += elapsed * emissionRate
        while emissionAccumulator >= 1, activeCount < particles.count {
            emissionAccumulator -= 1
            let group = activeCount % 5
            let size = 0.75 + generator.unit() * 1.40
            particles[activeCount] = CelebrationParticle()
            particles[activeCount].isActive = true
            particles[activeCount].position = .init(x: width * (0.12 + Double(group) * 0.19),
                                                    y: self.baseRadius * size)
            particles[activeCount].velocity = .init(x: generator.signed() * 63, y: 75 + generator.unit() * 78)
            particles[activeCount].scale = size
            particles[activeCount].rotation = generator.unit() * .pi * 2
            particles[activeCount].angularVelocity = generator.signed() * 6
            activeCount += 1
        }
        if activeCount == particles.count { emissionAccumulator = 0 }
        for index in 0..<activeCount {
            var particle = particles[index]
            particle.velocity.y -= 15 * elapsed
            particle.position = particle.position + particle.velocity * elapsed
            particle.rotation += particle.angularVelocity * elapsed
            let radius = baseRadius * particle.scale
            reflect(&particle.position.x, velocity: &particle.velocity.x,
                    lower: radius, upper: width - radius)
            reflect(&particle.position.y, velocity: &particle.velocity.y,
                    lower: radius, upper: height - radius)
            particles[index] = particle
        }
    }
    private func reflect(_ position: inout Double, velocity: inout Double, lower: Double, upper: Double) {
        guard upper > lower else { position = (lower + upper) / 2; velocity = 0; return }
        if position < lower { position = min(upper, lower + lower - position); velocity = abs(velocity) }
        if position > upper { position = max(lower, upper - (position - upper)); velocity = -abs(velocity) }
    }
}
