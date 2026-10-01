import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Perspective court presentation and inverse input")
struct ProjectionTests {
    private func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.000001) {
        #expect(abs(actual - expected) <= tolerance)
    }

    @Test("Perspective round trips dense court, edge and outside points", arguments: [(211.0, 257.0), (162.0, 197.0)])
    func denseRoundTrips(size: (Double, Double)) {
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1,
                                         safeLeading: 3, safeTrailing: 7)
        for row in -10...54 {
            for column in -5...25 {
                let court = Vector2(x: Double(column), y: Double(row))
                let recovered = projection.courtPoint(for: projection.screenPoint(for: court))
                near(recovered.x, court.x)
                near(recovered.y, court.y)
            }
        }
        // Points well outside the viewport remain invertible and unclamped.
        for screen in [Vector2(x: -40, y: -30), .init(x: size.0 + 40, y: size.1 + 20)] {
            let recovered = projection.screenPoint(for: projection.courtPoint(for: screen))
            near(recovered.x, screen.x)
            near(recovered.y, screen.y)
        }
    }

    @Test("Near baseline fills available width and far baseline uses the shallow trapezoid ratio")
    func baselineShape() {
        let projection = CourtProjection(viewportWidth: 211, viewportHeight: 257)
        let nearLeft = projection.screenPoint(for: .init(x: 0, y: 0))
        let nearRight = projection.screenPoint(for: .init(x: 20, y: 0))
        let farLeft = projection.screenPoint(for: .init(x: 0, y: 44))
        let farRight = projection.screenPoint(for: .init(x: 20, y: 44))
        near(nearRight.x - nearLeft.x, projection.nearWidth)
        near(farRight.x - farLeft.x, projection.farWidth)
        near(projection.farWidth / projection.nearWidth, 0.64)
        #expect(projection.nearWidth > 211 * 0.9)
        #expect(farLeft.x > nearLeft.x && farRight.x < nearRight.x)
        near(nearLeft.y, projection.nearY)
        near(nearRight.y, projection.nearY)
        near(farLeft.y, projection.farY)
        near(farRight.y, projection.farY)
        near(projection.scale(atLogicalY: 0), projection.nearWidth / 20)
        near(projection.scale(atLogicalY: 44), projection.farWidth / 20)
    }

    @Test("Kitchen lines and net remain ordered horizontal segments in logical regulation positions")
    func regulationLineOrder() {
        let projection = CourtProjection(viewportWidth: 211, viewportHeight: 257)
        let depths = [0.0, CourtGeometry.nearNonVolleyY, CourtGeometry.netY,
                      CourtGeometry.farNonVolleyY, CourtGeometry.length]
        var previousY = -Double.infinity
        var previousWidth = Double.infinity
        for y in depths {
            let left = projection.screenPoint(for: .init(x: 0, y: y))
            let right = projection.screenPoint(for: .init(x: 20, y: y))
            near(left.y, right.y)
            #expect(left.y > previousY)
            #expect(projection.width(atLogicalY: y) < previousWidth)
            near(right.x - left.x, projection.width(atLogicalY: y))
            previousY = left.y
            previousWidth = projection.width(atLogicalY: y)
        }
        #expect(CourtGeometry.serviceLines.count == 2)
        #expect(CourtGeometry.serviceLines[0].end.y == 15)
        #expect(CourtGeometry.serviceLines[1].start.y == 29)
        // Perspective expands the near half visually without changing the net's logical Y.
        let net = projection.screenPoint(for: .init(x: 10, y: 22))
        #expect(net.y > (projection.nearY + projection.farY) / 2)
        near(projection.courtPoint(for: net).y, 22)
    }

    @Test("HUD and baselines respect actual asymmetric safe insets on small and Ultra viewports", arguments: [(211.0, 257.0), (162.0, 197.0)])
    func safeLayout(size: (Double, Double)) {
        let top = 28.0, bottom = 8.0, leading = 5.0, trailing = 9.0
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1,
                                         safeTop: top, safeBottom: bottom,
                                         safeLeading: leading, safeTrailing: trailing)
        near(projection.hudY + 10, size.1 - top)
        near(projection.hudY - 10 - projection.farY, 8)
        near(projection.nearY - bottom, 22)
        #expect(projection.nearY < projection.farY)
        let left = projection.screenPoint(for: .init(x: 0, y: 0)).x
        let right = projection.screenPoint(for: .init(x: 20, y: 0)).x
        near(left - leading, 8)
        near(size.0 - trailing - right, 8)
        near(projection.centerX, (leading + size.0 - trailing) / 2)
    }

    @Test("Touch inversion at the player plane shares the authoritative logical coordinate")
    func playerPlaneTouch() {
        let projection = CourtProjection(viewportWidth: 162, viewportHeight: 197)
        let playerY = GameTuning().playerY
        for x in [-3.0, 0, 1.1, 5, 10, 16, 18.9, 20, 23] {
            let screenX = projection.screenPoint(for: .init(x: x, y: playerY)).x
            near(projection.courtX(forScreenX: screenX, atLogicalY: playerY), x)
        }
        #expect(projection.courtX(forScreenX: -100, atLogicalY: playerY) < 0)
        #expect(projection.courtX(forScreenX: 300, atLogicalY: playerY) > 20)
    }

    @Test("Invalid sizes, insets, coordinates and projective horizons remain finite")
    func finiteEdgeHandling() {
        for invalid in [0.0, -20, Double.nan, .infinity, -.infinity] {
            let projection = CourtProjection(viewportWidth: invalid, viewportHeight: invalid,
                                             safeTop: invalid, safeBottom: invalid,
                                             safeLeading: invalid, safeTrailing: invalid)
            #expect(projection.nearWidth.isFinite && projection.nearWidth > 0)
            #expect(projection.farWidth.isFinite && projection.farWidth > 0)
            #expect(projection.nearY.isFinite && projection.farY.isFinite)
            #expect(projection.farY > projection.nearY)
            #expect(projection.hudY.isFinite)
            let court = projection.courtPoint(for: projection.screenPoint(for: .init(x: 10, y: 22)))
            near(court.x, 10)
            near(court.y, 22)
        }
        let projection = CourtProjection(viewportWidth: 1, viewportHeight: 1,
                                         safeTop: 1_000, safeBottom: 1_000,
                                         safeLeading: 1_000, safeTrailing: 1_000)
        #expect(projection.nearWidth > 0 && projection.farY > projection.nearY)
        let normal = CourtProjection(viewportWidth: 211, viewportHeight: 257)
        let k = 1.0 / 0.64 - 1
        let logicalHorizon = -44 / k
        let screenHorizon = normal.nearY + (normal.farY - normal.nearY) * (1 + k) / k
        for point in [Vector2(x: .nan, y: .infinity), .init(x: 0, y: logicalHorizon),
                      .init(x: Double.greatestFiniteMagnitude, y: 0)] {
            let mapped = normal.screenPoint(for: point)
            #expect(mapped.x.isFinite && mapped.y.isFinite)
        }
        let inverse = normal.courtPoint(for: .init(x: 0, y: screenHorizon))
        #expect(inverse.x.isFinite && inverse.y.isFinite)
        #expect(normal.courtX(forScreenX: .infinity, atLogicalY: .nan).isFinite)
    }
}
