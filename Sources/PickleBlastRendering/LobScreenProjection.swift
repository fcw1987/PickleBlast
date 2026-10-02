import Foundation
import PickleBlastCore

/// The core's one ground ball receives a bounded screen-height offset. Height is
/// presentation only: neither this mapping nor the shadow is a collision source.
enum LobScreenProjection {
    static func ballRadius(at point: Vector2, projection: CourtProjection) -> Double {
        let depthScale = projection.width(atLogicalY: point.y) / projection.nearWidth
        return max(4, 5 * sqrt(projection.viewportWidth / 211) * depthScale)
    }

    static func ballPoint(ground: Vector2, flight: LobFlightState,
                          projection: CourtProjection, radius: Double) -> Vector2 {
        guard flight.heightFraction > 0 else { return ground }
        let ceiling = projection.farY - radius - 0.5
        // Use one peak for the whole committed path, avoiding a clipped flat
        // apex. Sample its known sinusoidal curve; the final bound covers even
        // unusual transient viewport sizes between the samples.
        var peak = max(0, (projection.farY - projection.nearY) * 0.22)
        peak = min(peak, flight.peakHeight * projection.scale(atLogicalY: 22))
        for index in 1..<32 {
            let fraction = Double(index) / 32
            let point = flight.origin + (flight.destination - flight.origin) * fraction
            let projected = projection.screenPoint(for: point)
            let height = sin(.pi * fraction)
            let sampleCeiling = projection.farY - ballRadius(at: point, projection: projection) - 0.5
            peak = min(peak, max(0, sampleCeiling - projected.y) / height)
        }
        let offset = min(max(0, ceiling - ground.y), peak * flight.heightFraction)
        return Vector2(x: ground.x, y: ground.y + offset)
    }
}
