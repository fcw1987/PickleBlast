import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Bounded victory cascade")
struct CelebrationTests {
    @Test("Cascade grows past 100 sprites and stays within fixed pool capacity")
    func denseBoundedPool() {
        var pool = CelebrationPool(capacity: 128, seed: 7)
        for _ in 0..<360 { pool.update(delta: 1.0 / 120) }
        #expect(pool.activeCount >= 100)
        #expect(pool.activeCount <= 128)
        #expect(pool.particles.count == 128)
        for _ in 0..<12_000 { pool.update(delta: 1.0 / 120) }
        #expect(pool.activeCount == 128)
        #expect(pool.particles.count == 128)
        for particle in pool.particles {
            #expect(particle.position.x.isFinite && particle.position.y.isFinite)
            let radius = pool.baseRadius * particle.scale
            #expect(particle.position.x >= radius - 0.000_001)
            #expect(particle.position.x <= pool.width - radius + 0.000_001)
            #expect(particle.position.y >= radius - 0.000_001)
            #expect(particle.position.y <= pool.height - radius + 0.000_001)
        }
    }

    @Test("Seeded emission is repeatable and varies launch points, size and rotation")
    func deterministicVariety() {
        var first = CelebrationPool(seed: 19)
        var second = CelebrationPool(seed: 19)
        for _ in 0..<120 {
            first.update(delta: 1.0 / 120)
            second.update(delta: 1.0 / 120)
        }
        #expect(first == second)
        let active = first.particles.filter(\.isActive)
        #expect(Set(active.map(\.scale)).count > 5)
        #expect(Set(active.map { $0.position.x }).count > 5)
        #expect(Set(active.map(\.angularVelocity)).count > 5)
    }

    @Test("Reset reuses capacity and reproduces a supplied seed")
    func reusableReset() {
        var pool = CelebrationPool(capacity: 32, seed: 11)
        pool.update(delta: 0.1)
        let first = pool
        pool.reset(seed: 11)
        #expect(pool.activeCount == 0)
        #expect(pool.particles.count == 32)
        #expect(pool.particles.allSatisfy { !$0.isActive })
        pool.update(delta: 0.1)
        #expect(pool == first)
    }

    @Test("Invalid delta and zero capacity remain safe")
    func invalidPoolInput() {
        var empty = CelebrationPool(capacity: 0)
        empty.update(delta: 1_000_000)
        #expect(empty.activeCount == 0)
        #expect(empty.particles.isEmpty)
        var pool = CelebrationPool()
        let before = pool
        for value in [Double.nan, .infinity, -1, 0] { pool.update(delta: value) }
        #expect(pool == before)
        #expect(CelebrationPool(capacity: 10_000).particles.count <= 256)
    }
}
