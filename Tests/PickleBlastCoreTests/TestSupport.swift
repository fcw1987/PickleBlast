import Foundation
import Testing
@testable import PickleBlastCore

/// Collision expectations use tolerances smaller than a visible court pixel.
func expectNear(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.000_001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.isFinite, sourceLocation: sourceLocation)
    #expect(abs(actual - expected) <= tolerance, sourceLocation: sourceLocation)
}

func activeEngine(boss: Bool = false, tuning: GameTuning = GameTuning(), seed: UInt64 = 42) -> GameEngine {
    let engine = GameEngine(tuning: tuning, seed: seed)
    engine.state.phase = .playing
    engine.state.phaseTimeRemaining = 0
    engine.state.targets = []
    engine.state.ball = nil
    if boss {
        engine.state.stage = .boss
        engine.state.boss = BossState()
    }
    return engine
}

@discardableResult
func advance(_ engine: GameEngine, seconds: Double, frame: Double = 1.0 / 120.0) -> [GameEvent] {
    var remaining = seconds
    var events: [GameEvent] = []
    while remaining > 0.000_000_01 {
        let dt = min(frame, remaining)
        events.append(contentsOf: engine.update(delta: dt))
        remaining -= dt
    }
    return events
}

func target(id: Int, kind: TargetKind, x: Double = 10, y: Double = 30) -> TargetState {
    TargetState(id: id, kind: kind, position: .init(x: x, y: y))
}

extension Array where Element == GameEvent {
    var paddleContacts: Int { filter { if case .paddleContact = $0 { return true }; return false }.count }
    var targetHits: Int { filter { if case .targetHit = $0 { return true }; return false }.count }
    var lifeLosses: Int { filter { if case .lifeLost = $0 { return true }; return false }.count }
    var bossContacts: Int { filter { if case .bossContact = $0 { return true }; return false }.count }
    var bossPoints: Int { filter { if case .bossPoint = $0 { return true }; return false }.count }
}
