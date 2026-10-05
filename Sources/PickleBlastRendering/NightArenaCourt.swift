import CoreGraphics
import PickleBlastCore
import SpriteKit

/// Static presentation geometry. The court itself remains opaque OLED black;
/// point feedback only fades its markings, never the playing surface.
final class NightArenaCourt: SKNode {
    private let surface = SKShapeNode()
    private let markings = SKNode()
    private let perimeterHalo = SKShapeNode()
    private let perimeter = SKShapeNode()
    private let interior = SKShapeNode()
    private let sidelineRails = SKShapeNode()
    private let netMesh = SKShapeNode()
    private let netTape = SKShapeNode()
    private let netPosts = SKShapeNode()

    var markingAlpha: CGFloat {
        get { markings.alpha }
        set { markings.alpha = newValue }
    }

    override init() {
        super.init()
        name = "nightArenaCourt"
        surface.name = "opaqueCourtSurface"
        surface.fillColor = Neon.black
        surface.strokeColor = .clear
        surface.lineWidth = 0
        surface.zPosition = -2
        // The unscaled polygon is a solid fill, so it needs no supersampling.
        addChild(surface)
        markings.name = "courtMarkings"
        addChild(markings)
        configure(perimeterHalo, name: "courtPerimeterHalo", color: Neon.cyan.withAlphaComponent(0.13), width: 3.8)
        configure(perimeter, name: "courtPerimeter", color: SKColor(red: 0.48, green: 0.94, blue: 1, alpha: 1), width: 1.05)
        configure(interior, name: "courtInteriorLines", color: Neon.cyan.withAlphaComponent(0.66), width: 0.7)
        configure(sidelineRails, name: "courtOuterRails", color: Neon.cyan.withAlphaComponent(0.25), width: 0.6)
        configure(netMesh, name: "courtNetMesh", color: Neon.cyan.withAlphaComponent(0.24), width: 0.4)
        configure(netTape, name: "courtNetTape", color: SKColor(red: 0.73, green: 0.96, blue: 1, alpha: 0.94), width: 1.0)
        configure(netPosts, name: "courtNetPosts", color: Neon.cyan.withAlphaComponent(0.8), width: 1.2)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func configure(_ node: SKShapeNode, name: String, color: SKColor, width: CGFloat) {
        node.name = name
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        CrispVector.prepare(node)
        markings.addChild(node)
    }

    /// Called only when layout changes. All paths share the authoritative court
    /// projector; no decoration participates in collision or input conversion.
    func layout(projection: CourtProjection) {
        func point(_ logical: Vector2) -> CGPoint {
            let value = projection.screenPoint(for: logical)
            return CGPoint(x: value.x, y: value.y)
        }
        func path(_ lines: [CourtLine]) -> CGPath {
            let result = CGMutablePath()
            for line in lines {
                result.move(to: point(line.start))
                result.addLine(to: point(line.end))
            }
            return result
        }

        let fill = CGMutablePath()
        fill.move(to: point(.init(x: 0, y: 0)))
        for corner in [Vector2(x: CourtGeometry.width, y: 0),
                       Vector2(x: CourtGeometry.width, y: CourtGeometry.length),
                       Vector2(x: 0, y: CourtGeometry.length)] {
            fill.addLine(to: point(corner))
        }
        fill.closeSubpath()
        surface.path = fill
        let boundary = path(CourtGeometry.boundaryLines)
        CrispVector.replacePath(of: perimeterHalo, with: boundary)
        CrispVector.replacePath(of: perimeter, with: boundary)
        CrispVector.replacePath(of: interior, with: path(CourtGeometry.nonVolleyLines + CourtGeometry.serviceLines))

        let rails = [-0.65, CourtGeometry.width + 0.65].map { x in
            CourtLine(.init(x: x, y: 1), .init(x: x, y: CourtGeometry.length - 1))
        }
        CrispVector.replacePath(of: sidelineRails, with: path(rails))

        // Tape stays on the real net plane. Sparse mesh hangs toward the viewer
        // and the short posts sit outside regulation sidelines.
        let left = point(CourtGeometry.net.start)
        let right = point(CourtGeometry.net.end)
        let drop = 3.0 * sqrt(projection.viewportWidth / 211)
        let mesh = CGMutablePath()
        mesh.move(to: CGPoint(x: left.x, y: left.y - drop))
        mesh.addLine(to: CGPoint(x: right.x, y: right.y - drop))
        let cells = 28
        for column in 0...cells {
            let x = left.x + (right.x - left.x) * Double(column) / Double(cells)
            mesh.move(to: CGPoint(x: x, y: left.y - drop))
            mesh.addLine(to: CGPoint(x: x, y: left.y))
        }
        CrispVector.replacePath(of: netMesh, with: mesh)
        CrispVector.replacePath(of: netTape, with: path([CourtGeometry.net]))
        let posts = CGMutablePath()
        for x in [left.x - 1.8, right.x + 1.8] {
            posts.move(to: CGPoint(x: x, y: left.y - drop - 1.5))
            posts.addLine(to: CGPoint(x: x, y: left.y + 1.5))
        }
        CrispVector.replacePath(of: netPosts, with: posts)
    }
}
