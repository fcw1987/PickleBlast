import Foundation

/// Intent is chosen from delayed, observable information. The resulting ball
/// remains governed by the ordinary core collision and receiving rules.
public enum RallyShotPurpose: String, Equatable, Sendable {
    case control, placement, changeOfPace, attack
}

struct RallyShotPlan: Equatable, Sendable {
    let velocity: Vector2
    /// Forecast at the player's real contact plane, after the existing
    /// receiving-angle correction and side reflections.
    let landingX: Double
    let laneSide: Int
    let purpose: RallyShotPurpose
}

enum RallyShotPlanner {
    static func choose(contact: BallState, bossY: Double, bossID: BossID,
                       observedPlayerX: Double, observedPlayerVelocity: Double = 0,
                       previousLandingSide: Int,
                       variation: Double, powered: Bool, balanced: Bool = true,
                       tuning: GameTuning) -> RallyShotPlan {
        let opponent = tuning.rallyOpponentConfiguration(for: bossID)
        let unit = variation.isFinite ? min(1, max(0, variation)) : 0.5
        let playerX = observedPlayerX.isFinite
            ? min(CourtGeometry.width - tuning.playerMargin, max(tuning.playerMargin, observedPlayerX))
            : CourtGeometry.centerX
        let drive = powered && balanced
        let purpose = chosenPurpose(bossID: bossID, unit: unit,
                                    powered: drive, balanced: balanced)
        let side: Double
        if playerX < CourtGeometry.centerX - 1 { side = 1 }
        else if playerX > CourtGeometry.centerX + 1 { side = -1 }
        else if previousLandingSide != 0 { side = previousLandingSide < 0 ? 1 : -1 }
        else { side = unit < 0.5 ? -1 : 1 }

        let offset: Double
        switch purpose {
        case .control: offset = 0.9
        case .changeOfPace: offset = 2.4
        case .placement: offset = 3.8
        case .attack: offset = drive ? 4.2 : 5.0
        }
        // Two delayed position samples can reveal travel direction, not the
        // player's next input. A small behind-motion adjustment only shapes
        // purposeful placements; the neutral control ball remains predictable.
        let observedMotion = observedPlayerVelocity.isFinite
            ? min(10, max(-10, observedPlayerVelocity)) : 0
        let trailing = purpose == .placement || purpose == .attack
            ? -0.12 * observedMotion : 0
        let target = min(CourtGeometry.width - tuning.playerMargin,
                         max(tuning.playerMargin, playerX + side * offset + trailing))
        let sourceSpeed = contact.speed.isFinite && contact.speed > 0
            ? contact.speed : tuning.initialBallSpeed
        let speed: Double
        if drive {
            speed = min(tuning.maximumBallSpeed,
                        max(0, sourceSpeed * max(1, opponent.powerSpeedMultiplier)))
        } else if purpose == .changeOfPace {
            // One slower return must not compound indefinitely. The next
            // ordinary contact restores the base pace below.
            speed = min(tuning.maximumBallSpeed,
                        max(tuning.initialBallSpeed * 0.85, sourceSpeed * 0.90))
        } else {
            speed = min(tuning.maximumBallSpeed, max(tuning.initialBallSpeed, sourceSpeed))
        }
        let startY = bossY - contact.radius - tuning.collisionEpsilon
        let contactX = contact.position.x.isFinite ? contact.position.x : CourtGeometry.centerX
        let start = Vector2(x: contactX, y: startY)
        let limit = min(.pi / 3, max(0, tuning.bossConfiguration(for: bossID).maximumReturnAngle))
        let directAngle = atan2(target - contactX,
                                max(0.1, startY - tuning.playerY - contact.radius))
        // A few direct-angle refinements plus broad alternatives discover the
        // effective landing after assistance, including legal wall banks.
        let degree = Double.pi / 180
        var angles: [Double] = []
        angles.reserveCapacity(18)
        for correction in [0.0, -2, 2, -4, 4, -8, 8] {
            angles.append(min(limit, max(-limit, directAngle + correction * degree)))
        }
        for angle in stride(from: -60.0, through: 60.0, by: 12.0) {
            angles.append(min(limit, max(-limit, angle * degree)))
        }
        var best: RallyShotPlan?
        var bestCost = Double.infinity
        for angle in angles {
            let velocity = Vector2(x: sin(angle) * speed, y: -cos(angle) * speed)
            let observed = BallState(position: start, velocity: velocity, radius: contact.radius)
            guard let arrival = RallyBallProjection.arrival(of: observed,
                atY: tuning.playerY + contact.radius, tuning: tuning,
                speedGrowth: max(0, opponent.speedGrowthPerSecond)) else { continue }
            let cost = abs(arrival.position.x - target)
                + abs(angle) * 0.35 + Double(arrival.sideReflections) * 0.16
            if cost < bestCost {
                bestCost = cost
                best = RallyShotPlan(velocity: velocity,
                                    landingX: arrival.position.x,
                                    laneSide: lane(for: arrival.position.x), purpose: purpose)
            }
        }
        if let best { return best }
        // Degenerate injected states take a safe, bounded vertical return.
        return RallyShotPlan(velocity: Vector2(x: 0, y: -speed), landingX: contactX,
                             laneSide: lane(for: contactX), purpose: .control)
    }

    private static func chosenPurpose(bossID: BossID, unit: Double,
                                      powered: Bool, balanced: Bool) -> RallyShotPurpose {
        if !balanced { return .control }
        if powered { return .attack }
        let thresholds: (Double, Double, Double)
        switch bossID {
        case .wall: thresholds = (0.40, 0.55, 0.90)
        case .banger: thresholds = (0.25, 0.40, 0.80)
        case .poacher: thresholds = (0.25, 0.40, 0.85)
        }
        if unit < thresholds.0 { return .control }
        if unit < thresholds.1 { return .changeOfPace }
        if unit < thresholds.2 { return .placement }
        return .attack
    }

    private static func lane(for x: Double) -> Int {
        if x < CourtGeometry.centerX - 2 { return -1 }
        if x > CourtGeometry.centerX + 2 { return 1 }
        return 0
    }
}
