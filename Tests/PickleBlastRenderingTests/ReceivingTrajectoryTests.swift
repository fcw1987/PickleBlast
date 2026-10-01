import Foundation
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Receiving trajectories against actual Watch court projection")
struct ReceivingTrajectoryTests {
    private let factor = 2.434
    private let incoming = 35.0 * Double.pi / 180
    private let outgoing = 45.0 * Double.pi / 180
    private var projections: [CourtProjection] {
        [CourtProjection(viewportWidth: 211, viewportHeight: 257,
                         safeTop: 56.5, safeBottom: 40, safeLeading: 2, safeTrailing: 2),
         CourtProjection(viewportWidth: 162, viewportHeight: 197,
                         safeTop: 40, safeBottom: 19, safeLeading: 2, safeTrailing: 2)]
    }
    private func measuredAngle(_ velocity: Vector2, at p: Vector2, projection: CourtProjection,
                               duration: Double = 1.0 / 120) -> Double {
        let first = projection.screenPoint(for: p)
        let second = projection.screenPoint(for: p + velocity * duration)
        return atan2(abs(second.x - first.x), abs(second.y - first.y))
    }

    @Test("Incoming bound covers lateral positions, depths, speeds and every reflected direction")
    func incomingGrid() {
        for x in [0.3, 1.1, 5, 10, 15, 18.9, 19.7] {
            for y in [2.5, 10, 15, 22] {
                let p = Vector2(x: x, y: y)
                for degrees in stride(from: -89.0, through: 89, by: 1) {
                    for speed in [10.0, 26, 46] {
                        let angle = degrees * .pi / 180
                        let v = Vector2(x: sin(angle) * speed, y: -cos(angle) * speed)
                        let corrected = ReceivingTrajectory.constrained(v, at: p,
                            maximumApparentAngle: incoming, projectionSlopeFactor: factor)
                        #expect(abs(corrected.length - speed) < 1e-10)
                        #expect(corrected.y < 0)
                        for projection in projections {
                            #expect(measuredAngle(corrected, at: p, projection: projection) <= incoming + 1e-10)
                        }
                        // A second entry check must not introduce a visible zigzag.
                        let repeated = ReceivingTrajectory.constrained(corrected, at: p,
                            maximumApparentAngle: incoming, projectionSlopeFactor: factor)
                        #expect((repeated - corrected).length < 1e-10)
                    }
                }
            }
        }
    }

    @Test("Outgoing left center and right placement remain bounded over the full receiving segment")
    func outgoingGrid() {
        for x in [0.3, 1.1, 5, 10, 15, 18.9, 19.7] {
            let start = Vector2(x: x, y: 2.5)
            for fraction in stride(from: -1.0, through: 1, by: 0.1) {
                let v = ReceivingTrajectory.outgoing(apparentAngle: fraction * outgoing,
                    at: start, speed: 26, projectionSlopeFactor: factor)
                #expect(abs(v.length - 26) < 1e-10)
                #expect(v.y > 0)
                for projection in projections {
                    #expect(measuredAngle(v, at: start, projection: projection) <= outgoing + 1e-10)
                    let end = start + v * ((22 - start.y) / v.y)
                    #expect(abs(measuredAngle(v, at: start, projection: projection)
                                - measuredAngle(v, at: end, projection: projection)) < 1e-10)
                }
            }
        }
    }

    @Test("One entry correction stays straight until a wall; both reflected legs obey their caps")
    func entryThenWall() {
        for direction in [-1.0, 1.0] {
            let start = Vector2(x: direction < 0 ? 1 : 19, y: 22)
            let velocity = Vector2(x: direction * 45, y: -sqrt(46 * 46 - 45 * 45))
            let leg = ReceivingTrajectory.constrained(velocity, at: start,
                maximumApparentAngle: incoming, projectionSlopeFactor: factor)
            let wallX = direction < 0 ? 0.3 : 19.7
            let wall = start + leg * ((wallX - start.x) / leg.x)
            #expect(wall.y > 2.5)
            let reflected = Vector2(x: -leg.x, y: leg.y)
            let after = ReceivingTrajectory.constrained(reflected, at: wall,
                maximumApparentAngle: incoming, projectionSlopeFactor: factor)
            #expect(after.x * direction < 0)
            #expect(abs(after.length - 46) < 1e-10)
            for projection in projections {
                #expect(measuredAngle(leg, at: start, projection: projection) <= incoming + 1e-10)
                #expect(measuredAngle(leg, at: wall, projection: projection) <= incoming + 1e-10)
                #expect(measuredAngle(after, at: wall, projection: projection) <= incoming + 1e-10)
            }
        }
    }

    @Test("Maximum outgoing placement can reach both authored side lanes from ordinary receiving positions")
    func sideLaneAccess() {
        for side in [-1.0, 1.0] {
            let start = Vector2(x: 10 + side * 3.25, y: 2.5)
            // A moderate angle aims directly into the lane; limiting does not
            // force every return into the central target face.
            let destination = Vector2(x: side < 0 ? 1 : 19, y: 22)
            let direction = destination - start
            let v = direction * (26 / direction.length)
            let corrected = ReceivingTrajectory.constrained(v, at: start,
                maximumApparentAngle: outgoing, projectionSlopeFactor: factor)
            #expect((corrected - v).length < 1e-10)
            let entry = start + corrected * ((22 - start.y) / corrected.y)
            #expect(abs(entry.x - destination.x) < 1e-10)
        }
    }

    @Test("Projection diagnosis records old logical cap and revised screen-space mapping")
    func mappingReport() {
        for (index, projection) in projections.enumerated() {
            let actualFactor = projection.nearWidth * 44 / (20 * (projection.farY - projection.nearY) * 1.5625)
            var oldMaximum = 0.0
            for x in [0.3, 10, 19.7] {
                for direction in [-1.0, 1.0] {
                    let angle = direction * 51 * Double.pi / 180
                    oldMaximum = max(oldMaximum, measuredAngle(.init(x: sin(angle) * 26, y: cos(angle) * 26),
                        at: .init(x: x, y: 2.5), projection: projection))
                }
            }
            print("TRAJECTORY_MAPPING watch=\(index == 0 ? "Ultra49" : "SE40") factor=\(actualFactor) old51logical_maxScreenDegrees=\(oldMaximum * 180 / .pi)")
        }
    }

    @Test("Stall redirect preserves speed and sign and does not modify adequate vertical travel")
    func stall() {
        for xSign in [-1.0, 1.0] {
            for ySign in [-1.0, 1.0] {
                let v = Vector2(x: xSign * sqrt(26 * 26 - 6.24 * 6.24), y: ySign * 6.24)
                let redirected = ReceivingTrajectory.stallRedirect(v, minimumVerticalFraction: 0.45)
                #expect(abs(redirected.length - 26) < 1e-10)
                #expect(abs(redirected.y / 26 - ySign * 0.45) < 1e-10)
                #expect(redirected.x * xSign > 0)
                #expect(ReceivingTrajectory.stallRedirect(redirected, minimumVerticalFraction: 0.45) == redirected)
            }
        }
    }
}
