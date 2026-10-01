import Foundation
import Testing
@testable import PickleBlastCore

/// Independent collision-review fixtures, not public-control reachability evidence.
/// Seeded balls begin outside the authored obstacles at maximum supported speed.
/// Fine and grouped frame delivery must produce exactly the same simulation.
@Suite("Independent dense CCD review")
struct ReviewCCDTests {
    @Test("Seeded narrow contacts neither penetrate survivors nor depend on frame grouping")
    func noPenetrationAndFramePartition() {
        let tuning = GameTuning()
        var seed: UInt64 = 48_119
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
        var accepted = 0
        var damageContacts = 0
        for index in 0..<3_000 {
            let wave = index % 3 + 1
            let targets = AuthoredWaves.targets(for: wave)
            let margin = tuning.ballRadius + 0.01
            let start = Vector2(x: margin + random() * (CourtGeometry.width - 2 * margin),
                                y: 10 + random() * (CourtGeometry.length - margin - 10))
            guard targets.allSatisfy({ (start - $0.position).length > $0.radius + tuning.ballRadius + tuning.collisionEpsilon }) else { continue }
            accepted += 1
            let angle = random() * .pi * 2
            let initial = BallState(position: start,
                                    velocity: .init(x: sin(angle) * tuning.maximumBallSpeed,
                                                    y: cos(angle) * tuning.maximumBallSpeed))
            let fine = activeEngine()
            let grouped = activeEngine()
            for engine in [fine, grouped] {
                engine.state.targets = targets
                engine.state.ball = initial
                engine.state.stage = .wave(wave)
            }
            var fineEvents: [GameEvent] = []
            for _ in 0..<12 {
                fineEvents += fine.update(delta: tuning.fixedStep)
                if let ball = fine.state.ball, fine.state.phase == .playing {
                    for target in fine.state.targets {
                        #expect((ball.position - target.position).length >= ball.radius + target.radius - 0.0005,
                                "Penetration in sample \(index), target \(target.id)")
                    }
                }
            }
            damageContacts += fineEvents.filter { if case .targetHit = $0 { return true }; return false }.count
            let groupedEvents = grouped.update(delta: tuning.fixedStep * 12)
            #expect(fineEvents == groupedEvents, "Events depend on frame grouping in sample \(index)")
            #expect(fine.state == grouped.state, "State depends on frame grouping in sample \(index)")
        }
        // Ensure this sweep exercised collisions rather than passing vacuously.
        #expect(accepted > 2_000)
        #expect(damageContacts > 500)
        print("CCD_REVIEW candidates=3000 accepted=\(accepted) targetDamageContacts=\(damageContacts) maxSpeed=\(tuning.maximumBallSpeed) durationPerScenario=\(tuning.fixedStep * 12)")
    }
}
