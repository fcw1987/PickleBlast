import Foundation

public struct CourtLine: Equatable, Sendable {
    public let start: Vector2
    public let end: Vector2
    public init(_ start: Vector2, _ end: Vector2) { self.start = start; self.end = end }
}

public enum CourtGeometry {
    public static let width: Double = 20
    public static let length: Double = 44
    public static let netY: Double = 22
    public static let nonVolleyDepth: Double = 7
    public static let nearNonVolleyY: Double = 15
    public static let farNonVolleyY: Double = 29
    public static let centerX: Double = 10
    public static let boundaryLines: [CourtLine] = [
        CourtLine(.init(x: 0, y: 0), .init(x: 20, y: 0)),
        CourtLine(.init(x: 20, y: 0), .init(x: 20, y: 44)),
        CourtLine(.init(x: 20, y: 44), .init(x: 0, y: 44)),
        CourtLine(.init(x: 0, y: 44), .init(x: 0, y: 0))
    ]
    public static let nonVolleyLines: [CourtLine] = [
        CourtLine(.init(x: 0, y: 15), .init(x: 20, y: 15)),
        CourtLine(.init(x: 0, y: 29), .init(x: 20, y: 29))
    ]
    public static let serviceLines: [CourtLine] = [
        CourtLine(.init(x: 10, y: 0), .init(x: 10, y: 15)),
        CourtLine(.init(x: 10, y: 29), .init(x: 10, y: 44))
    ]
    public static let net = CourtLine(.init(x: 0, y: 22), .init(x: 20, y: 22))
    public static var lines: [CourtLine] { boundaryLines + nonVolleyLines + serviceLines }
}

/// SpriteKit coordinates: origin at lower left, positive Y toward the far baseline.
public struct CourtTransform: Equatable, Sendable {
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let scale: Double
    public let origin: Vector2
    public var courtWidth: Double { CourtGeometry.width * scale }
    public var courtHeight: Double { CourtGeometry.length * scale }
    public init(viewportWidth: Double, viewportHeight: Double, topInset: Double = 28,
                bottomInset: Double = 12, horizontalInset: Double = 12) {
        self.viewportWidth = viewportWidth.isFinite ? max(1, viewportWidth) : 1
        self.viewportHeight = viewportHeight.isFinite ? max(1, viewportHeight) : 1
        let availableWidth = max(1, self.viewportWidth - max(0, horizontalInset) * 2)
        let availableHeight = max(1, self.viewportHeight - max(0, topInset) - max(0, bottomInset))
        self.scale = min(availableWidth / CourtGeometry.width, availableHeight / CourtGeometry.length)
        self.origin = .init(x: (self.viewportWidth - CourtGeometry.width * scale) / 2,
                            y: max(0, bottomInset) + (availableHeight - CourtGeometry.length * scale) / 2)
    }
    public func screenPoint(for point: Vector2) -> Vector2 { origin + point * scale }
    public func courtPoint(for point: Vector2) -> Vector2 {
        .init(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}

/// Authored, stable formations; coordinates and health never derive from artwork.
/// Alternating rows form a staggered field with two continuous side entrances.
/// Rear highlights leave a ball-sized corridor below the reflective far wall.
public enum AuthoredWaves {
    public static let count = 3

    public static func targets(for number: Int, tuning: GameTuning = GameTuning()) -> [TargetState] {
        guard (1...count).contains(number) else { return [] }
        var result: [TargetState] = []
        result.reserveCapacity([36, 48, 58][number - 1])
        func append(_ kind: TargetKind, _ size: TargetSize, _ x: Double, _ y: Double) {
            let radius: Double
            if kind == .basket { radius = tuning.basketTargetRadius }
            else {
                switch size {
                case .small: radius = tuning.smallTargetRadius
                case .medium: radius = tuning.mediumTargetRadius
                case .large: radius = tuning.largeTargetRadius
                }
            }
            result.append(TargetState(id: number * 100 + result.count, kind: kind,
                                      position: .init(x: x, y: y), radius: radius, health: 1,
                                      size: size, maximumHealth: 1))
        }
        let columns = [6, 7, 8][number - 1]
        let columnStep = [2.6, 2.15, 1.85][number - 1]
        let firstX = [3.5, 3.55, 3.525][number - 1]
        for row in 0..<6 {
            let stagger = (row.isMultiple(of: 2) ? -1.0 : 1.0) * columnStep / 4
            for column in 0..<columns {
                append(.paddle, .small, firstX + Double(column) * columnStep + stagger,
                       23 + Double(row) * 2)
            }
        }
        if number == 2 {
            for x in [4.0, 8, 12, 16] { append(.paddle, .medium, x, 37.5) }
            for x in [6.0, 14] { append(.basket, .medium, x, 41) }
        } else if number == 3 {
            for column in 0..<6 {
                append(.paddle, .medium, 3.2 + Double(column) * 2.72, 37.5)
            }
            for x in [4.56, 7.28, 12.72, 15.44] {
                append(.paddle, .large, x, 41)
            }
        }
        return result
    }

    /// Compatibility for existing isolated fixtures with an explicit base radius.
    /// Scale all tiers proportionally rather than making large targets small.
    public static func targets(for number: Int, radius: Double) -> [TargetState] {
        var tuning = GameTuning()
        let ratio = radius / tuning.smallTargetRadius
        tuning.smallTargetRadius = radius
        tuning.mediumTargetRadius *= ratio
        tuning.basketTargetRadius *= ratio
        tuning.largeTargetRadius *= ratio
        return targets(for: number, tuning: tuning)
    }
}
