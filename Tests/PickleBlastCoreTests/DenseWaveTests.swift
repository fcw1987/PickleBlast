import Testing
@testable import PickleBlastCore

@Suite("Authored dense formations and ball-sized routes")
struct DenseWaveTests {
    @Test("Exact target and health mixes stay stable", arguments: [1, 2, 3])
    func composition(number: Int) {
        let targets = AuthoredWaves.targets(for: number)
        #expect(targets == AuthoredWaves.targets(for: number))
        #expect(targets.count == [36, 48, 58][number - 1])
        #expect(Set(targets.map(\.id)).count == targets.count)
        #expect(targets.filter { $0.health == 1 }.count == [36, 48, 58][number - 1])
        #expect(targets.filter { $0.health == 2 }.count == 0)
        #expect(targets.filter { $0.health == 3 }.count == 0)
        #expect(targets.filter { $0.kind == .basket }.count == [0, 2, 0][number - 1])
        #expect(targets.reduce(0) { $0 + $1.health } == [36, 48, 58][number - 1])
        #expect(targets.allSatisfy { $0.health == $0.maximumHealth && !$0.isDamaged })
        #expect(AuthoredWaves.targets(for: 0).isEmpty)
        #expect(AuthoredWaves.targets(for: 4).isEmpty)
    }

    @Test("Every collision shape is separated and ball-inflated bounds clear serve and walls", arguments: [1, 2, 3])
    func collisionClearances(number: Int) {
        let tuning = GameTuning()
        let targets = AuthoredWaves.targets(for: number)
        for (index, target) in targets.enumerated() {
            let inflated = target.radius + tuning.ballRadius
            #expect(target.position.x - inflated > tuning.ballRadius)
            #expect(target.position.x + inflated < CourtGeometry.width - tuning.ballRadius)
            #expect(target.position.y - inflated > tuning.launchY)
            #expect(target.position.y + inflated < CourtGeometry.length - tuning.ballRadius)
            for other in targets.dropFirst(index + 1) {
                // Target bodies never overlap. Internal gaps may be narrower
                // than the ball: the intentional side entrances stay generous.
                #expect((target.position - other.position).length >
                        target.radius + other.radius)
            }
        }
    }

    @Test("Both side entrances connect to a generous continuous backfield", arguments: [1, 2, 3])
    func entryAndBackfield(number: Int) {
        let tuning = GameTuning()
        let targets = AuthoredWaves.targets(for: number)
        for laneX in [1.0, 19.0] {
            for target in targets {
                // A straight ball-center path runs from serve height through
                // the complete formation. Extra margin avoids pixel-perfect aim.
                #expect(abs(target.position.x - laneX) - target.radius - tuning.ballRadius >= 0.75)
            }
        }
        let backfieldLower = targets.map { $0.position.y + $0.radius + tuning.ballRadius }.max()!
        let backfieldUpper = CourtGeometry.length - tuning.ballRadius
        #expect(backfieldUpper - backfieldLower >= 1.1)
        if number > 1 {
            let front = targets.filter { $0.size == .small }.map(\.position.y).max()!
            #expect(targets.filter { $0.size != .small }.allSatisfy { $0.position.y > front })
        }
    }

    @Test("Central radius tuning reaches the authored tiers")
    func radiusConfiguration() {
        var tuning = GameTuning()
        tuning.smallTargetRadius = 0.4
        tuning.mediumTargetRadius = 0.6
        tuning.basketTargetRadius = 0.8
        tuning.largeTargetRadius = 0.9
        let second = AuthoredWaves.targets(for: 2, tuning: tuning)
        #expect(second.filter { $0.kind == .basket }.allSatisfy { $0.radius == 0.8 })
        let third = AuthoredWaves.targets(for: 3, tuning: tuning)
        #expect(third.filter { $0.size == .small }.allSatisfy { $0.radius == 0.4 })
        #expect(third.filter { $0.size == .medium }.allSatisfy { $0.radius == 0.6 })
        #expect(third.filter { $0.size == .large }.allSatisfy { $0.radius == 0.9 })
        let normal = AuthoredWaves.targets(for: 3)
        let scaled = AuthoredWaves.targets(for: 3, radius: GameTuning().smallTargetRadius * 0.5)
        for (original, smaller) in zip(normal, scaled) {
            #expect(smaller.radius == original.radius * 0.5)
            #expect(smaller.position == original.position)
        }
    }
}
