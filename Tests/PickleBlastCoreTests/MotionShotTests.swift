import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Optional Boss Rally contact motion")
struct MotionShotTests {
    private enum Input: Equatable { case direct, touch, crown }

    private func set(_ x: Double, on engine: GameEngine, using input: Input) {
        switch input {
        case .direct: engine.setPlayerX(x)
        case .touch:
            let transform = CourtTransform(viewportWidth: 211, viewportHeight: 257)
            engine.setPlayerFromTouch(screenX: transform.screenPoint(for: .init(x: x, y: 0)).x,
                                      transform: transform)
        case .crown:
            engine.movePlayer(crownDelta: x - engine.state.playerX, sensitivity: 1)
        }
    }

    private func apparentAngle(of velocity: Vector2, tuning: GameTuning, contactX: Double = 10) -> Double {
        atan(ReceivingTrajectory.projectedSlope(of: velocity,
            at: .init(x: contactX, y: tuning.playerY + tuning.ballRadius),
            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor))
    }

    /// The 60 Hz caller repeats each 30 Hz input value. Thus both schedules
    /// present precisely the same post-clamp position to every fixed core tick.
    private func scriptedReturn(renderRate: Int, input: Input, enabled: Bool,
                                mode: GameMode = .bossRally(.wall)) -> Double? {
        var tuning = GameTuning()
        tuning.rallyMotionInfluenceEnabled = enabled
        let engine = GameEngine(mode: mode, tuning: tuning, seed: 11)
        engine.state.stage = .boss
        engine.state.boss = BossState(id: .wall)
        engine.state.phase = .playing
        engine.state.ball = BallState(position: .init(x: 10, y: 6.1),
                                      velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
        for frame in 0..<(renderRate / 30 * 12) {
            let inputStep = frame / (renderRate / 30)
            set(min(9.8, 8 + 0.45 * Double(inputStep)), on: engine, using: input)
            let events = engine.update(delta: 1.0 / Double(renderRate))
            if events.contains(where: {
                if case .paddleContact = $0 { return true }
                return false
            }), let velocity = engine.state.ball?.velocity {
                return apparentAngle(of: velocity, tuning: tuning)
            }
        }
        return nil
    }

    @Test("Motion is bounded and identical under 30/60 Hz updates and touch/Crown paths")
    func fixedTickMotionAndInputParity() throws {
        let neutral = try #require(scriptedReturn(renderRate: 30, input: .direct, enabled: false))
        let at30 = try #require(scriptedReturn(renderRate: 30, input: .direct, enabled: true))
        let at60 = try #require(scriptedReturn(renderRate: 60, input: .direct, enabled: true))
        let touch = try #require(scriptedReturn(renderRate: 30, input: .touch, enabled: true))
        let crown = try #require(scriptedReturn(renderRate: 30, input: .crown, enabled: true))
        #expect(at30 > neutral)
        #expect(at30 - neutral <= GameTuning().rallyMotionMaximumApparentAngle + 1e-8)
        #expect(abs(at30 - at60) < 1e-8)
        #expect(abs(at30 - touch) < 1e-8)
        #expect(abs(at30 - crown) < 1e-8)
        let arcade = try #require(scriptedReturn(renderRate: 30, input: .direct,
                                                enabled: true, mode: .arcade))
        #expect(abs(arcade - neutral) < 1e-8,
                "The optional Boss Rally input history cannot change Arcade contacts")
    }

    @Test("Requests beyond a clamped boundary cannot build hidden shot motion")
    func boundaryClampingHasNoGhostAngle() throws {
        var tuning = GameTuning()
        tuning.rallyMotionInfluenceEnabled = true
        for input in [Input.touch, .crown] {
            let engine = GameEngine(mode: .bossRally(.wall), tuning: tuning)
            engine.state.phase = .playing
            engine.state.ball = BallState(position: .init(x: 18.9, y: 10),
                                          velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
            for _ in 0..<30 {
                if input == .crown {
                    engine.movePlayer(crownDelta: 100, sensitivity: 1)
                } else {
                    set(25, on: engine, using: input)
                }
                _ = engine.update(delta: tuning.fixedStep)
            }
            #expect(abs(engine.state.playerX - (CourtGeometry.width - tuning.playerMargin)) < 1e-10)
            engine.state.ball = BallState(position: .init(x: engine.state.playerX, y: 3.0),
                                          velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
            var returnAngle: Double?
            for _ in 0..<8 {
                let events = engine.update(delta: tuning.fixedStep)
                if events.contains(where: {
                    if case .paddleContact = $0 { return true }
                    return false
                }), let velocity = engine.state.ball?.velocity {
                    returnAngle = apparentAngle(of: velocity, tuning: tuning, contactX: engine.state.playerX)
                    break
                }
            }
            let angle = try #require(returnAngle)
            #expect(abs(angle) < 1e-8)
        }
    }

    @Test("Pause, serve and match restart discard old movement before another contact")
    func lifecycleClearsMotion() throws {
        var tuning = GameTuning()
        tuning.rallyMotionInfluenceEnabled = true
        for transition in 0..<3 {
            let engine = GameEngine(mode: .bossRally(.wall), tuning: tuning)
            engine.state.phase = .playing
            engine.state.ball = BallState(position: .init(x: 10, y: 9),
                                          velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
            for index in 0..<12 {
                engine.setPlayerX(8 + 0.15 * Double(index))
                _ = engine.update(delta: tuning.fixedStep)
            }
            switch transition {
            case 0:
                engine.pause()
                engine.resume()
                while engine.state.resumeCountdown > 0 {
                    _ = engine.update(delta: tuning.maximumFrameDelta)
                }
            case 1:
                engine.state.phase = .ready
                engine.state.phaseTimeRemaining = 0
                _ = engine.update(delta: tuning.fixedStep)
            default:
                engine.reset()
                engine.state.phase = .playing
            }
            engine.state.ball = BallState(position: .init(x: 10, y: 3.0),
                                          velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
            let playerX = engine.state.playerX
            var returnAngle: Double?
            for _ in 0..<8 {
                let events = engine.update(delta: tuning.fixedStep)
                if events.contains(where: {
                    if case .paddleContact = $0 { return true }
                    return false
                }), let velocity = engine.state.ball?.velocity {
                    returnAngle = apparentAngle(of: velocity, tuning: tuning)
                    break
                }
            }
            let expectedOffset = (10 - playerX) / tuning.playerHalfWidth
            let angle = try #require(returnAngle)
            #expect(abs(angle - expectedOffset * tuning.maximumOutgoingApparentAngle) < 1e-8)
        }
    }
}
