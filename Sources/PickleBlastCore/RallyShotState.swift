import Foundation

/// One authoritative flight identity. Rendering never advances these clocks.
public enum RallyShotKind: String, Equatable, Sendable {
    case normal, power, soft, lob
}

public struct LobFlightState: Equatable, Sendable {
    public let origin: Vector2
    public let destination: Vector2
    public let duration: Double
    public var elapsed: Double
    public let peakHeight: Double
    public init(origin: Vector2, destination: Vector2, duration: Double,
                elapsed: Double = 0, peakHeight: Double) {
        self.origin = origin; self.destination = destination
        self.duration = max(0.001, duration.isFinite ? duration : 0.001)
        self.elapsed = min(self.duration, max(0, elapsed.isFinite ? elapsed : 0))
        self.peakHeight = max(0, peakHeight.isFinite ? peakHeight : 0)
    }
    public var fraction: Double { min(1, max(0, elapsed / duration)) }
    public var groundPosition: Vector2 { origin + (destination - origin) * fraction }
    public var height: Double {
        guard fraction > 0, fraction < 1 else { return 0 }
        return peakHeight * sin(.pi * fraction)
    }
    public var heightFraction: Double { peakHeight > 0 ? min(1, max(0, height / peakHeight)) : 0 }
    public var remainingDuration: Double { max(0, duration - elapsed) }
    public var receivingX: Double { destination.x }
    public var velocity: Vector2 { (destination - origin) * (1 / duration) }
}

public struct RallyShotState: Equatable, Sendable {
    public let rallyID: UInt64
    public let shotID: UInt64
    public let kind: RallyShotKind
    public let requestedSpeed: Double
    public let realizedSpeed: Double
    public let ordinaryReturnSpeed: Double?
    public var lobFlight: LobFlightState?
    public init(rallyID: UInt64, shotID: UInt64, kind: RallyShotKind,
                requestedSpeed: Double, realizedSpeed: Double, ordinaryReturnSpeed: Double? = nil, lobFlight: LobFlightState? = nil) {
        self.rallyID = rallyID; self.shotID = shotID; self.kind = kind
        self.requestedSpeed = requestedSpeed; self.realizedSpeed = realizedSpeed
        self.ordinaryReturnSpeed = ordinaryReturnSpeed
        self.lobFlight = lobFlight
    }
}
