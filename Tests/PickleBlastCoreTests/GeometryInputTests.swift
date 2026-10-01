import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Regulation geometry and shared inputs")
struct GeometryInputTests {
    @Test("Initial and reset Crown coordinates equal the authoritative player position")
    func crownInitialAndResetSynchronization() {
        let engine = GameEngine(seed: 11)
        expectNear(engine.state.playerX, 10)
        expectNear(engine.state.crownInput, engine.state.playerX)
        engine.setPlayerX(4)
        expectNear(engine.state.crownInput, 4)
        engine.reset()
        expectNear(engine.state.playerX, 10)
        expectNear(engine.state.crownInput, engine.state.playerX)
    }

    @Test("Stage transitions recenter Crown and player together", arguments: [1, 2, 3])
    func stageRecenterSynchronization(completedWave: Int) {
        let engine = GameEngine(seed: 11)
        engine.setPlayerX(4)
        expectNear(engine.state.crownInput, 4)
        engine.state.stage = .wave(completedWave)
        engine.state.phase = .blackout
        engine.state.phaseTimeRemaining = engine.tuning.fixedStep
        _ = engine.update(delta: engine.tuning.fixedStep)
        #expect(engine.state.stage == (completedWave < 3 ? .wave(completedWave + 1) : .boss))
        #expect(engine.state.phase == .ready)
        expectNear(engine.state.playerX, 10)
        expectNear(engine.state.crownInput, engine.state.playerX)
    }

    @Test("Court coordinates are exactly regulation sized")
    func regulationDimensions() {
        #expect(CourtGeometry.width == 20)
        #expect(CourtGeometry.length == 44)
        #expect(CourtGeometry.netY == 22)
        #expect(CourtGeometry.netY - CourtGeometry.nearNonVolleyY == 7)
        #expect(CourtGeometry.farNonVolleyY - CourtGeometry.netY == 7)
        #expect(CourtGeometry.boundaryLines.count == 4)
        #expect(CourtGeometry.nonVolleyLines.count == 2)
        #expect(CourtGeometry.lines.count == 8)
    }

    @Test("Service centerlines stop at kitchen boundaries")
    func noKitchenCenterline() {
        #expect(CourtGeometry.serviceLines == [CourtLine(.init(x: 10, y: 0), .init(x: 10, y: 15)), CourtLine(.init(x: 10, y: 29), .init(x: 10, y: 44))])
        #expect(!CourtGeometry.lines.contains { $0.start.x == 10 && $0.end.x == 10 && max($0.start.y, $0.end.y) > 15 && min($0.start.y, $0.end.y) < 29 })
        #expect(CourtGeometry.net == CourtLine(.init(x: 0, y: 22), .init(x: 20, y: 22)))
    }

    @Test("Mapping fits large and small Watch displays without distortion", arguments: [(211.0, 257.0), (162.0, 197.0), (184.0, 224.0), (422.0, 514.0)])
    func responsiveMapping(size: (Double, Double)) {
        let transform = CourtTransform(viewportWidth: size.0, viewportHeight: size.1)
        let near = transform.screenPoint(for: .zero)
        let far = transform.screenPoint(for: .init(x: 20, y: 44))
        #expect(near.x >= 12 && near.y >= 12)
        #expect(far.x <= size.0 - 12 + 0.000_001)
        #expect(far.y <= size.1 - 28 + 0.000_001)
        expectNear((far.x - near.x) / (far.y - near.y), 20.0 / 44.0)
        for point in [Vector2.zero, .init(x: 10, y: 22), .init(x: 20, y: 44), .init(x: 4.2, y: 13.7)] {
            let roundTrip = transform.courtPoint(for: transform.screenPoint(for: point))
            expectNear(roundTrip.x, point.x)
            expectNear(roundTrip.y, point.y)
        }
    }

    @Test("Zero and invalid view sizes retain a finite invertible transform")
    func invalidGeometry() {
        for value in [0.0, -10, .nan, .infinity] {
            let transform = CourtTransform(viewportWidth: value, viewportHeight: value)
            #expect(transform.scale.isFinite && transform.scale > 0)
            let point = transform.courtPoint(for: transform.screenPoint(for: .init(x: 10, y: 22)))
            expectNear(point.x, 10)
            expectNear(point.y, 22)
        }
    }

    @Test("Player clamps at both boundaries")
    func playerClamp() {
        let engine = activeEngine()
        engine.setPlayerX(-1_000)
        expectNear(engine.state.playerX, engine.tuning.playerMargin)
        engine.setPlayerX(1_000)
        expectNear(engine.state.playerX, 20 - engine.tuning.playerMargin)
    }

    @Test("Crown boundary overshoot reverses on the next small motion")
    func immediateCrownReversal() {
        let engine = activeEngine()
        engine.movePlayer(crownDelta: 10_000, sensitivity: 1)
        let right = engine.state.playerX
        engine.movePlayer(crownDelta: -0.01, sensitivity: 1)
        #expect(engine.state.playerX < right)
        engine.movePlayer(crownDelta: -10_000, sensitivity: 1)
        let left = engine.state.playerX
        engine.movePlayer(crownDelta: 0.01, sensitivity: 1)
        #expect(engine.state.playerX > left)
    }

    @Test("Sensitivity changes movement distance without affecting shot physics")
    func crownSensitivity() {
        let normal = activeEngine()
        let doubled = activeEngine()
        normal.movePlayer(crownDelta: 0.25, sensitivity: 1)
        doubled.movePlayer(crownDelta: 0.25, sensitivity: 2)
        let positions = (normal.state.playerX, doubled.state.playerX)
        normal.recordCrownVelocity(1)
        doubled.recordCrownVelocity(100)
        #expect(normal.state.playerX == positions.0 && doubled.state.playerX == positions.1)
        expectNear(doubled.state.playerX - 10, (normal.state.playerX - 10) * 2)
        // Compare identical authoritative positions: perspective compensation legitimately varies with X.
        doubled.setPlayerX(normal.state.playerX)
        normal.state.ball = BallState(position: .init(x: normal.state.playerX, y: 2.8), velocity: .init(x: 0, y: -26))
        doubled.state.ball = BallState(position: .init(x: doubled.state.playerX, y: 2.8), velocity: .init(x: 0, y: -26))
        _ = advance(normal, seconds: 0.04)
        _ = advance(doubled, seconds: 0.04)
        #expect(normal.state.ball?.velocity == doubled.state.ball?.velocity)
    }

    @Test("Touch and Crown write the same authoritative player position")
    func sharedPositionAuthority() {
        let engine = activeEngine()
        let transform = CourtTransform(viewportWidth: 211, viewportHeight: 257)
        engine.setPlayerFromTouch(screenX: transform.screenPoint(for: .init(x: 6, y: 0)).x, transform: transform)
        expectNear(engine.state.playerX, 6)
        engine.movePlayer(crownDelta: 1, sensitivity: 1)
        #expect(engine.state.playerX > 6)
        engine.setPlayerFromTouch(screenX: transform.screenPoint(for: .init(x: 14, y: 0)).x, transform: transform)
        expectNear(engine.state.playerX, 14)
        engine.movePlayer(crownDelta: -0.01, sensitivity: 1)
        #expect(engine.state.playerX < 14)
    }

    @Test("Nonfinite input cannot poison authoritative position")
    func invalidInputs() {
        let engine = activeEngine()
        for value in [Double.nan, .infinity, -.infinity] {
            engine.setPlayerX(value)
            engine.movePlayer(crownDelta: value, sensitivity: 1)
            engine.recordCrownVelocity(value)
            #expect(engine.state.playerX.isFinite)
            #expect(engine.state.playerX >= engine.tuning.playerMargin)
            #expect(engine.state.playerX <= 20 - engine.tuning.playerMargin)
        }
    }

    @Test("Three authored formations are deterministic, distinct, and on the far half")
    func authoredWaves() {
        #expect(AuthoredWaves.count == 3)
        #expect(AuthoredWaves.targets(for: 1).count == 36)
        #expect(AuthoredWaves.targets(for: 2).count == 48)
        #expect(AuthoredWaves.targets(for: 3).count == 58)
        var ids: Set<Int> = []
        for number in 1...3 {
            let targets = AuthoredWaves.targets(for: number)
            #expect(targets == AuthoredWaves.targets(for: number))
            for target in targets {
                #expect(ids.insert(target.id).inserted)
                #expect(target.position.y > 22 && target.position.y < 44)
                #expect(target.position.x > target.radius && target.position.x < 20 - target.radius)
            }
        }
        #expect(AuthoredWaves.targets(for: 4).isEmpty)
    }
}
