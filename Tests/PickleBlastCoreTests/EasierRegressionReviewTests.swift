import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Independent receiving and finishing-boundary regression review")
struct EasierRegressionReviewTests {
    @Test("Boundary and adjacent wall crossings agree between grouped and individual ticks")
    func receivingCrossingReplay() throws {
        for speed in [1.0, 26, 46] {
            for fraction in [0.24, 0.50, 0.90] {
                for x in [0.301, 1, 10, 19, 19.699] {
                    for direction in [-1.0, 1.0] {
                        func fixture() -> GameEngine {
                            let engine = activeEngine()
                            engine.state.ball = BallState(position: .init(x: x, y: 22.001),
                                velocity: .init(x: direction * speed * sqrt(1 - fraction * fraction),
                                                y: -speed * fraction))
                            return engine
                        }
                        let fixed = fixture(), grouped = fixture()
                        let fixedEvents = advance(fixed, seconds: 0.1)
                        let groupedEvents = grouped.update(delta: 0.1)
                        #expect(fixedEvents == groupedEvents)
                        #expect(fixed.state == grouped.state)
                        let ball = try #require(grouped.state.ball)
                        expectNear(ball.speed, speed)
                        #expect(ball.position.x >= ball.radius - 1e-5 && ball.position.x <= 20 - ball.radius + 1e-5)
                        #expect(ball.position.y < 22)
                        #expect(ReceivingTrajectory.apparentAngle(of: ball.velocity, at: ball.position,
                            projectionSlopeFactor: grouped.tuning.receivingProjectionSlopeFactor)
                            <= grouped.tuning.maximumIncomingApparentAngle + 1e-10)
                        #expect(fixedEvents.paddleContacts == 0 && fixedEvents.lifeLosses == 0)
                    }
                }
            }
        }
    }

    @Test("Cleanup remains exact across grouped frames through celebration and stage allowance reset")
    func cleanupReplayAndNewStage() {
        func fixture() -> GameEngine {
            let engine = activeEngine()
            engine.state.recoveriesRemaining = 0
            engine.state.targets = [target(id: 5, kind: .paddle)] + (1...4).map { id in
                TargetState(id: id, kind: .paddle, position: .init(x: Double(id) * 4, y: 40),
                            radius: 0.5, health: 1, size: id == 4 ? .large : .small, maximumHealth: 1)
            }
            engine.state.ball = BallState(position: .init(x: 10, y: 28.45), velocity: .init(x: 0, y: 26))
            return engine
        }
        let fixed = fixture(), grouped = fixture()
        let fixedEvents = advance(fixed, seconds: 3, frame: 1.0 / 120)
        let groupedEvents = advance(grouped, seconds: 3, frame: 0.1)
        #expect(fixedEvents == groupedEvents)
        #expect(fixed.state == grouped.state)
        #expect(grouped.state.stage == .wave(2))
        #expect(grouped.state.recoveriesRemaining == 2)
        #expect(grouped.state.lives == 3)
        #expect(grouped.state.score == 1_050)
        #expect(fixedEvents.targetHits == 1)
        #expect(fixedEvents.filter { if case .targetCleaned = $0 { return true }; return false }.count == 4)
        #expect(fixedEvents.filter { if case .waveCleared = $0 { return true }; return false }.count == 1)
        #expect(fixedEvents.lifeLosses == 0)
    }
}
