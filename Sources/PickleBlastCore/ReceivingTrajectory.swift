import Foundation

/// Converts angle limits into logical velocities using the unchanged court
/// homography. The fixed reference factor in GameTuning covers the widest actual
/// supported Watch projection, keeping replay independent of a screen layout.
public enum ReceivingTrajectory {
    /// CourtProjection's far-to-near width is 0.64. This is geometry, not an
    /// alternate renderer or a second collision coordinate system.
    public static let perspective = 1.0 / 0.64 - 1

    /// Screen dx/dy for a straight logical trajectory. A projective transform
    /// maps a straight line to a straight line, so this slope remains constant
    /// until a collision changes its direction.
    public static func projectedSlope(of velocity: Vector2, at position: Vector2,
                                      projectionSlopeFactor: Double) -> Double {
        guard abs(velocity.y) > 1e-15 else {
            return velocity.x == 0 ? 0 : .infinity
        }
        let denominator = 1 + perspective * position.y / CourtGeometry.length
        let shear = perspective * (position.x - CourtGeometry.centerX) / CourtGeometry.length
        return projectionSlopeFactor * (denominator * velocity.x / velocity.y - shear)
    }

    /// Unsigned angle from screen vertical, for either travel direction.
    public static func apparentAngle(of velocity: Vector2, at position: Vector2,
                                     projectionSlopeFactor: Double) -> Double {
        atan(abs(projectedSlope(of: velocity, at: position,
                                projectionSlopeFactor: projectionSlopeFactor)))
    }

    /// Apply once on entry to the receiving region or after a wall reflection in
    /// that region. Already compliant trajectories are bit-for-bit unchanged.
    /// Position and speed are never changed; no player position is consulted.
    public static func constrained(_ velocity: Vector2, at position: Vector2,
                                   maximumApparentAngle: Double,
                                   projectionSlopeFactor: Double) -> Vector2 {
        guard valid(velocity, position: position, factor: projectionSlopeFactor),
              velocity.length > 0 else { return velocity }
        let cap = tan(min(.pi * 0.49, max(0, maximumApparentAngle)))
        let slope = projectedSlope(of: velocity, at: position,
                                   projectionSlopeFactor: projectionSlopeFactor)
        guard abs(slope) > cap else { return velocity }
        let denominator = 1 + perspective * position.y / CourtGeometry.length
        let shear = perspective * (position.x - CourtGeometry.centerX) / CourtGeometry.length
        // With a horizontal input, choose its existing horizontal direction and
        // an upward vertical direction. Production uses this only on nonzero vy.
        let verticalSign = velocity.y < 0 ? -1.0 : 1.0
        let slopeSign = velocity.y == 0 ? (velocity.x < 0 ? -1.0 : 1.0) : (slope < 0 ? -1.0 : 1.0)
        let ratio = (slopeSign * cap / projectionSlopeFactor + shear) / denominator
        let y = verticalSign * velocity.length / sqrt(1 + ratio * ratio)
        return Vector2(x: ratio * y, y: y)
    }

    /// `apparentAngle` is signed left/right from upward screen vertical. The
    /// caller normalizes the contact offset using the configured full hit zone.
    public static func outgoing(apparentAngle: Double, at position: Vector2,
                                speed: Double, projectionSlopeFactor: Double) -> Vector2 {
        guard speed.isFinite, speed >= 0, position.x.isFinite, position.y.isFinite,
              projectionSlopeFactor.isFinite, projectionSlopeFactor > 0 else { return .zero }
        let denominator = 1 + perspective * position.y / CourtGeometry.length
        guard denominator > 0 else { return .zero }
        let angle = min(.pi * 0.49, max(-.pi * 0.49, apparentAngle))
        let shear = perspective * (position.x - CourtGeometry.centerX) / CourtGeometry.length
        let ratio = (tan(angle) / projectionSlopeFactor + shear) / denominator
        let y = speed / sqrt(1 + ratio * ratio)
        return Vector2(x: ratio * y, y: y)
    }

    /// A one-off escape for genuinely stalled shallow travel; the engine owns
    /// the no-progress clock/latch so active backfield chains never invoke it.
    public static func stallRedirect(_ velocity: Vector2, minimumVerticalFraction: Double) -> Vector2 {
        let speed = velocity.length
        guard velocity.x.isFinite, velocity.y.isFinite, speed > 0,
              minimumVerticalFraction.isFinite else { return velocity }
        let fraction = min(1, max(0, minimumVerticalFraction))
        guard abs(velocity.y) < speed * fraction else { return velocity }
        let y = (velocity.y < 0 ? -1.0 : 1.0) * speed * fraction
        let x = (velocity.x < 0 ? -1.0 : 1.0) * sqrt(max(0, speed * speed - y * y))
        return .init(x: x, y: y)
    }

    private static func valid(_ velocity: Vector2, position: Vector2, factor: Double) -> Bool {
        velocity.x.isFinite && velocity.y.isFinite && position.x.isFinite && position.y.isFinite
            && factor.isFinite && factor > 0 && 1 + perspective * position.y / CourtGeometry.length > 0
    }
}
