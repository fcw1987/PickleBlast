import PickleBlastCore

/// Presentation-only perspective. Coordinates use SpriteKit's lower-left origin;
/// gameplay remains in the regulation 20 × 44-foot logical court.
public struct CourtProjection: Equatable, Sendable {
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let centerX: Double
    public let nearY: Double
    public let farY: Double
    public let nearWidth: Double
    public let farWidth: Double
    public let hudY: Double

    private static let farWidthRatio = 0.64
    private static let perspective = 1 / farWidthRatio - 1
    private static let minimumDenominator = 0.0000000001
    private var depth: Double { farY - nearY }
    private var nearScale: Double { nearWidth / CourtGeometry.width }

    public init(viewportWidth: Double, viewportHeight: Double,
                safeTop: Double = 28, safeBottom: Double = 8,
                safeLeading: Double = 0, safeTrailing: Double = 0) {
        let width = Self.dimension(viewportWidth)
        let height = Self.dimension(viewportHeight)
        self.viewportWidth = width
        self.viewportHeight = height

        let leading = Self.inset(safeLeading)
        let trailing = Self.inset(safeTrailing)
        let sideClearance = 8.0
        // An impossible inset configuration compresses its margins, leaving a
        // finite, positive projection for transient zero/tiny layout proposals.
        let horizontalFactor = min(1, width / (leading + trailing + 2 * sideClearance + 1))
        let left = (leading + sideClearance) * horizontalFactor
        let right = width - (trailing + sideClearance) * horizontalFactor
        centerX = left + (right - left) / 2
        nearWidth = right - left
        farWidth = nearWidth * Self.farWidthRatio

        let top = Self.inset(safeTop)
        let bottom = Self.inset(safeBottom)
        let hudHeight = 20.0
        let hudGap = 8.0
        let playerRoom = 22.0
        let verticalFactor = min(1, height / (top + bottom + hudHeight + hudGap + playerRoom + 1))
        nearY = (bottom + playerRoom) * verticalFactor
        hudY = height - (top + hudHeight / 2) * verticalFactor
        farY = height - (top + hudHeight + hudGap) * verticalFactor
    }

    public func screenPoint(for point: Vector2) -> Vector2 {
        let x = point.x.isFinite ? point.x : CourtGeometry.centerX
        let y = point.y.isFinite ? point.y : 0
        let t = y / CourtGeometry.length
        let denominator = Self.denominator(1 + Self.perspective * t)
        return Vector2(
            x: Self.finite(centerX + (x - CourtGeometry.centerX) * (nearScale / denominator), fallback: centerX),
            y: Self.finite(nearY + depth * ((1 + Self.perspective) * t / denominator), fallback: nearY))
    }

    /// Exact inverse away from the projective horizon. No court-edge clamping is
    /// applied here: the core retains ownership of the player's movement limits.
    public func courtPoint(for point: Vector2) -> Vector2 {
        let x = point.x.isFinite ? point.x : centerX
        let y = point.y.isFinite ? point.y : nearY
        let projectedY = (y - nearY) / depth
        let denominator = Self.denominator(1 + Self.perspective - Self.perspective * projectedY)
        let t = projectedY / denominator
        let inversePerspective = (1 + Self.perspective) / denominator
        return Vector2(
            x: Self.finite(CourtGeometry.centerX + ((x - centerX) / nearScale) * inversePerspective,
                           fallback: CourtGeometry.centerX),
            y: Self.finite(t * CourtGeometry.length, fallback: 0))
    }

    public func width(atLogicalY y: Double) -> Double {
        Self.finite(scale(atLogicalY: y) * CourtGeometry.width, fallback: nearWidth)
    }

    /// Horizontal points per logical foot at this depth. This is positive over
    /// the visible court; geometry beyond the projective horizon may be mirrored.
    public func scale(atLogicalY y: Double) -> Double {
        let logicalY = y.isFinite ? y : 0
        let denominator = Self.denominator(1 + Self.perspective * logicalY / CourtGeometry.length)
        return Self.finite(nearScale / denominator, fallback: nearScale)
    }

    /// Touch uses the player's fixed logical depth, not the finger's screen Y.
    public func courtX(forScreenX x: Double, atLogicalY y: Double) -> Double {
        let screenX = x.isFinite ? x : centerX
        return Self.finite(CourtGeometry.centerX + (screenX - centerX) / scale(atLogicalY: y),
                           fallback: CourtGeometry.centerX)
    }

    private static func dimension(_ value: Double) -> Double {
        value.isFinite ? max(1, value) : 1
    }

    private static func inset(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func denominator(_ value: Double) -> Double {
        if abs(value) >= minimumDenominator { return value }
        return value < 0 ? -minimumDenominator : minimumDenominator
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        if value.isFinite { return value }
        if value.isNaN { return fallback }
        return value < 0 ? -Double.greatestFiniteMagnitude : Double.greatestFiniteMagnitude
    }
}
