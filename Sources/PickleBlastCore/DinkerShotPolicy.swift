import Foundation

/// Contact-only pace change. The ordinary projection includes the real route,
/// receiving correction and speed growth; the soft shot keeps that direction.
internal enum DinkerShotPolicy {
    static func speed(ordinarySpeed: Double, ordinaryTravelTime: Double,
                      tuning: GameTuning) -> Double {
        let fallback = tuning.initialBallSpeed.isFinite ? max(0, tuning.initialBallSpeed) : 26
        let ordinary = ordinarySpeed.isFinite ? max(0, ordinarySpeed) : fallback
        let policy = tuning.rallyDinker
        guard ordinary > 0, ordinaryTravelTime.isFinite, ordinaryTravelTime >= 0,
              policy.softMaximumTravelDuration.isFinite,
              policy.softMaximumTravelDuration > 0,
              ordinaryTravelTime < policy.softMaximumTravelDuration else { return ordinary }

        let ratio = policy.softSpeedRatio.isFinite
            ? min(1, max(0, policy.softSpeedRatio)) : 0.70
        let floor = policy.softMinimumSpeed.isFinite ? max(0, policy.softMinimumSpeed) : 16
        // A nonnegative growth rate makes this conservative: the slower flight
        // gains speed for longer than the comparable ordinary flight does.
        let durationFloor = ordinary * (ordinaryTravelTime / policy.softMaximumTravelDuration)
        return min(ordinary, max(ordinary * ratio, max(floor, durationFloor)))
    }
}
