import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Dense maximum-speed contacts")
struct DenseCollisionTests {
    @Test("Small, medium and large faces, backs, sides and corners resolve once",
          arguments: [TargetSize.small, .medium, .large])
    func directions(size: TargetSize) {
        let radius = size == .small ? 0.55 : (size == .medium ? 0.75 : 0.95)
        for normal in [Vector2(x: 0, y: -1), .init(x: 0, y: 1),
                       .init(x: -1, y: 0), .init(x: 1, y: 0),
                       .init(x: sqrt(0.5), y: sqrt(0.5))] {
            var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0 // Isolate continued CCD traversal.
            let engine = activeEngine(tuning: tuning)
            let center = Vector2(x: 10, y: 35)
            engine.state.targets = [TargetState(id: 1, kind: .paddle, position: center,
                                                 radius: radius, size: size),
                                    target(id: 2, kind: .paddle, x: 18, y: 30)]
            engine.state.ball = BallState(position: center + normal * (radius + 0.30 + 0.04),
                                          velocity: normal * -46)
            let events = engine.update(delta: engine.tuning.fixedStep)
            #expect(events.targetHits == 1)
            #expect(engine.state.ball!.velocity.dot(normal) > 0)
            expectNear(engine.state.ball!.speed, 46)
            #expect(engine.state.targets.first { $0.id == 1 }?.health ==
                    (size == .small ? nil : size.maximumHealth - 1))
            #expect(engine.update(delta: engine.tuning.fixedStep).targetHits == 0)
        }
    }

    @Test("Separate adjacent targets can both be hit inside one fixed step")
    func nearbyContacts() {
        var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0 // Isolate continued CCD traversal.
            let engine = activeEngine(tuning: tuning)
        engine.state.targets = [
            TargetState(id: 1, kind: .paddle, position: .init(x: 10, y: 30), radius: 0.55),
            TargetState(id: 2, kind: .paddle, position: .init(x: 10, y: 28.25), radius: 0.55),
            target(id: 3, kind: .paddle, x: 18, y: 35)
        ]
        engine.state.ball = BallState(position: .init(x: 10, y: 29.125), velocity: .init(x: 0, y: 46))
        let events = engine.update(delta: engine.tuning.fixedStep)
        #expect(events.targetHits == 2)
        #expect(engine.state.targets.map(\.id) == [3])
        #expect(engine.state.targetChain == 2)
        #expect(engine.state.score == 300)
        expectNear(engine.state.ball!.speed, 46)
    }

    @Test("Far wall and target back resolve remaining movement without tunneling")
    func farWallBack() {
        var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0 // Isolate continued CCD traversal.
            let engine = activeEngine(tuning: tuning)
        engine.state.targets = [
            TargetState(id: 1, kind: .paddle, position: .init(x: 10, y: 42.8), radius: 0.55),
            target(id: 2, kind: .paddle, x: 18, y: 35)
        ]
        engine.state.ball = BallState(position: .init(x: 10, y: 43.68), velocity: .init(x: 0, y: 46))
        let events = engine.update(delta: engine.tuning.fixedStep)
        #expect(events.targetHits == 1)
        #expect(events.contains(.wallContact))
        #expect(engine.state.targets.map(\.id) == [2])
        #expect(engine.state.ball!.position.y <= 43.7)
        expectNear(engine.state.ball!.speed, 46)
    }

    @Test("Collision iteration cap holds position before unchecked remaining movement")
    func safeIterationCap() {
        var tuning = GameTuning()
        tuning.maximumCollisionsPerStep = 1
        tuning.cleanupTargetThreshold = 0
        let engine = activeEngine(tuning: tuning)
        engine.state.targets = [
            TargetState(id: 1, kind: .paddle, position: .init(x: 10, y: 30), radius: 0.55),
            TargetState(id: 2, kind: .paddle, position: .init(x: 10, y: 28.25), radius: 0.55)
        ]
        engine.state.ball = BallState(position: .init(x: 10, y: 29.125), velocity: .init(x: 0, y: 46))
        #expect(engine.update(delta: tuning.fixedStep).targetHits == 1)
        #expect(engine.state.ball!.position.y > 29.1)
        #expect(engine.state.ball!.position.y < 29.15)
        #expect(engine.state.targets.map(\.id) == [2])
        #expect(engine.update(delta: tuning.fixedStep).targetHits == 1)
    }

    @Test("Symmetric simultaneous contacts use stable authored order")
    func deterministicTie() {
        func run() -> ([GameEvent], GameState) {
            var tuning = GameTuning(); tuning.cleanupTargetThreshold = 0 // Isolate continued CCD traversal.
            let engine = activeEngine(tuning: tuning)
            engine.state.targets = [
                TargetState(id: 9, kind: .paddle, position: .init(x: 9.2, y: 30), radius: 0.55),
                TargetState(id: 4, kind: .paddle, position: .init(x: 10.8, y: 30), radius: 0.55),
                target(id: 3, kind: .paddle, x: 18, y: 35)
            ]
            engine.state.ball = BallState(position: .init(x: 10, y: 29.6), velocity: .init(x: 0, y: 46))
            return (engine.update(delta: engine.tuning.fixedStep), engine.state)
        }
        let first = run()
        let second = run()
        #expect(first.0 == second.0)
        #expect(first.1 == second.1)
        let hitIDs = first.0.compactMap { event -> Int? in
            if case let .targetHit(id, _, _, _) = event { return id }; return nil
        }
        #expect(hitIDs.first == 9)
        #expect(Set(hitIDs).count == hitIDs.count)
    }
}
