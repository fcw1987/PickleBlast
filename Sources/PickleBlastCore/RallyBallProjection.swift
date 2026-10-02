import Foundation

/// A bounded, nonmutating forecast using the court's existing speed growth,
/// side reflections and receiving-angle correction. Opponents pass a delayed
/// observation, never the live future player input.
public enum RallyBallProjection {
    public struct Arrival: Equatable, Sendable {
        public let position: Vector2
        public let velocity: Vector2
        public let time: Double
        public let sideReflections: Int
        public let receivingCorrected: Bool
    }

    public static func arrival(of observed: BallState, atY planeY: Double,
                               tuning: GameTuning, speedGrowth: Double,
                               receivingAlreadyGuided: Bool = false,
                               horizon: Double = 4, lobFlight: LobFlightState? = nil) -> Arrival? {
        if let lob = lobFlight {
            let current = lob.groundPosition
            let velocity = lob.velocity
            guard planeY.isFinite, horizon.isFinite, horizon > 0, velocity.y < 0 else { return nil }
            let time = (planeY - current.y) / velocity.y
            guard time >= -tuning.collisionEpsilon, time <= min(horizon, lob.remainingDuration) + tuning.collisionEpsilon else { return nil }
            let atReceiving = planeY == lob.destination.y
            return Arrival(position: atReceiving ? lob.destination : current + velocity * max(0, time), velocity: velocity,
                time: atReceiving ? lob.remainingDuration : max(0, time), sideReflections: 0,
                receivingCorrected: planeY <= tuning.receivingBoundaryY)
        }
        guard observed.position.x.isFinite, observed.position.y.isFinite,
              observed.velocity.x.isFinite, observed.velocity.y.isFinite,
              planeY.isFinite, horizon.isFinite, horizon > 0,
              observed.velocity.y != 0 else { return nil }
        let direction = observed.velocity.y > 0 ? 1.0 : -1.0
        guard (planeY - observed.position.y) * direction >= 0 else { return nil }
        var position = observed.position
        var velocity = observed.velocity
        var time = 0.0
        var reflections = 0
        var guided = receivingAlreadyGuided
        let step = max(0.001, tuning.fixedStep)
        let epsilon = max(1e-8, tuning.collisionEpsilon)
        let wallLeft = observed.radius
        let wallRight = CourtGeometry.width - observed.radius
        let boundedHorizon = min(horizon, step * 1_000)
        let limit = min(1_000, Int(ceil(boundedHorizon / step)) + 1)
        for _ in 0..<limit {
            var dt = min(step, boundedHorizon - time)
            if dt <= 0 { break }
            velocity = limited(velocity, tuning: tuning)
            let speed = velocity.length
            if speed > 0, speedGrowth > 0 {
                let grown = min(tuning.maximumBallSpeed, speed + speedGrowth * dt)
                velocity = velocity * (grown / speed)
            }
            if direction < 0, !guided, position.y <= tuning.receivingBoundaryY {
                velocity = ReceivingTrajectory.constrained(velocity, at: position,
                    maximumApparentAngle: tuning.maximumIncomingApparentAngle,
                    projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
                guided = true
            }
            var contacts = 0
            while dt > 1e-10, contacts < max(1, tuning.maximumCollisionsPerStep) {
                let planeTime = (planeY - position.y) / velocity.y
                let wallTime: Double
                if velocity.x < -epsilon { wallTime = (wallLeft - position.x) / velocity.x }
                else if velocity.x > epsilon { wallTime = (wallRight - position.x) / velocity.x }
                else { wallTime = .infinity }
                let receivingTime = direction < 0 && !guided && position.y > tuning.receivingBoundaryY
                    ? (tuning.receivingBoundaryY - position.y) / velocity.y : .infinity
                if planeTime >= -epsilon, planeTime <= dt + epsilon,
                   planeTime <= wallTime + epsilon, planeTime <= receivingTime + epsilon {
                    position = position + velocity * max(0, planeTime)
                    return Arrival(position: position, velocity: velocity,
                                   time: time + max(0, planeTime), sideReflections: reflections,
                                   receivingCorrected: guided)
                }
                if wallTime >= -epsilon, wallTime <= dt + epsilon,
                   wallTime <= receivingTime + epsilon {
                    let travel = max(0, wallTime)
                    position = position + velocity * travel
                    dt -= travel; time += travel
                    velocity.x = -velocity.x
                    position.x = min(wallRight, max(wallLeft, position.x + (velocity.x > 0 ? epsilon : -epsilon)))
                    reflections += 1
                    contacts += 1
                    if position.y <= tuning.receivingBoundaryY {
                        velocity = ReceivingTrajectory.constrained(velocity, at: position,
                            maximumApparentAngle: direction < 0
                                ? tuning.maximumIncomingApparentAngle
                                : tuning.maximumOutgoingApparentAngle,
                            projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
                        if direction < 0 { guided = true }
                    }
                } else if receivingTime >= -epsilon, receivingTime <= dt + epsilon {
                    let travel = max(0, receivingTime)
                    position = position + velocity * travel
                    dt -= travel; time += travel
                    velocity = ReceivingTrajectory.constrained(velocity, at: position,
                        maximumApparentAngle: tuning.maximumIncomingApparentAngle,
                        projectionSlopeFactor: tuning.receivingProjectionSlopeFactor)
                    guided = true
                    contacts += 1
                } else {
                    position = position + velocity * dt
                    time += dt; dt = 0
                }
            }
        }
        return nil
    }

    private static func limited(_ velocity: Vector2, tuning: GameTuning) -> Vector2 {
        let length = velocity.length
        guard length.isFinite, length > 0 else { return velocity }
        let speed = min(length, tuning.maximumBallSpeed)
        var result = velocity * (speed / length)
        let minimum = speed * min(0.8, max(0, tuning.minimumVerticalFraction))
        if abs(result.y) < minimum {
            result.y = result.y < 0 ? -minimum : minimum
            result.x = (result.x < 0 ? -1.0 : 1.0) * sqrt(max(0, speed * speed - result.y * result.y))
        }
        return result
    }
}
