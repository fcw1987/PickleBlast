import CoreGraphics
import PickleBlastCore
import SpriteKit

/// Static B3 presentation geometry. The approved slate-blue surface is opaque;
/// point feedback fades its paint and net, never the material beneath them.
/// All paths are rebuilt only on layout, through the gameplay's projector.
final class NightArenaCourt: SKNode {
    private let apron = SKShapeNode()
    private let surface = SKShapeNode()
    private let kitchen = SKShapeNode()
    private let markings = SKNode()
    private let perimeterHalo = SKShapeNode()
    private let perimeter = SKShapeNode()
    private let interior = SKShapeNode()
    private let sidelineRails = SKShapeNode()
    private let netShadow = SKShapeNode()
    private let netBody = SKShapeNode()
    private let netMesh = SKShapeNode()
    private let netTape = SKShapeNode()
    private let netPosts = SKShapeNode()
    private let netPostHighlights = SKShapeNode()

    var markingAlpha: CGFloat {
        get { markings.alpha }
        set { markings.alpha = newValue }
    }

    init(material: SKTexture? = nil) {
        super.init()
        name = "nightArenaCourt"
        configureFill(apron, name: "courtDarkApron", color: SKColor(red: 0.022, green: 0.047, blue: 0.080, alpha: 1), z: -3)
        configureFill(surface, name: "opaqueCourtSurface",
                      color: material == nil ? SKColor(red: 0.07, green: 0.20, blue: 0.34, alpha: 1) : .white, z: -2)
        surface.fillTexture = material
        // The same material continues beneath this transparent paint layer, so
        // the two seven-foot kitchens read as one dark non-volley zone. There
        // is no texture seam or second perspective competing with regulation.
        configureFill(kitchen, name: "courtNonVolleyMaterial", color: SKColor(red: 0.008, green: 0.027, blue: 0.048, alpha: 0.62), z: -1)
        markings.name = "courtMarkings"
        addChild(markings)
        // A narrow dark paint edge replaces the old neon halo. Line endpoints
        // and the plane of the white net tape stay exactly where play expects.
        configure(perimeterHalo, name: "courtPerimeterHalo", color: SKColor(white: 0.02, alpha: 0.8), width: 2.0)
        configure(perimeter, name: "courtPerimeter", color: SKColor(red: 0.90, green: 0.95, blue: 0.98, alpha: 1), width: 1.05)
        configure(interior, name: "courtInteriorLines", color: SKColor(red: 0.84, green: 0.91, blue: 0.95, alpha: 0.94), width: 0.8)
        configure(sidelineRails, name: "courtOuterRails", color: SKColor(red: 0.13, green: 0.70, blue: 0.88, alpha: 0.52), width: 0.5)
        configure(netShadow, name: "courtNetShadow", color: .clear, width: 0)
        netShadow.fillColor = SKColor(white: 0, alpha: 0.28)
        configure(netBody, name: "courtNetBody", color: .clear, width: 0)
        netBody.fillColor = SKColor(red: 0.012, green: 0.025, blue: 0.035, alpha: 0.76)
        configure(netMesh, name: "courtNetMesh", color: SKColor(red: 0.44, green: 0.56, blue: 0.62, alpha: 0.82), width: 0.38)
        configure(netTape, name: "courtNetTape", color: SKColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1), width: 1.22)
        configure(netPosts, name: "courtNetPosts", color: SKColor(red: 0.025, green: 0.037, blue: 0.05, alpha: 1), width: 2.5)
        configure(netPostHighlights, name: "courtNetPostHighlights", color: SKColor(red: 0.66, green: 0.76, blue: 0.80, alpha: 0.92), width: 0.6)
    }

    required init?(coder: NSCoder) { fatalError("Use init(material:)") }

    private func configureFill(_ node: SKShapeNode, name: String, color: SKColor, z: CGFloat) {
        node.name = name
        node.fillColor = color
        node.strokeColor = .clear
        node.lineWidth = 0
        node.zPosition = z
        // Ordinary filled polygons need no supersampling or custom offscreen pass.
        addChild(node)
    }

    private func configure(_ node: SKShapeNode, name: String, color: SKColor, width: CGFloat) {
        node.name = name
        node.fillColor = .clear
        node.strokeColor = color
        node.lineWidth = width
        CrispVector.prepare(node)
        markings.addChild(node)
    }

    /// Called only when layout changes. No decoration participates in collision
    /// or input conversion, and the material contains no authored court lines.
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
        func polygon(_ corners: [CGPoint]) -> CGPath {
            let result = CGMutablePath()
            guard let first = corners.first else { return result }
            result.move(to: first)
            for corner in corners.dropFirst() { result.addLine(to: corner) }
            result.closeSubpath()
            return result
        }
        func rectangle(left: Double, right: Double, near: Double, far: Double) -> CGPath {
            polygon([point(.init(x: left, y: near)), point(.init(x: right, y: near)),
                     point(.init(x: right, y: far)), point(.init(x: left, y: far))])
        }

        apron.path = rectangle(left: -0.8, right: CourtGeometry.width + 0.8, near: -1.0, far: CourtGeometry.length + 1.0)
        surface.path = rectangle(left: 0, right: CourtGeometry.width, near: 0, far: CourtGeometry.length)
        kitchen.path = rectangle(left: 0, right: CourtGeometry.width,
                                 near: CourtGeometry.nearNonVolleyY, far: CourtGeometry.farNonVolleyY)
        let boundary = path(CourtGeometry.boundaryLines)
        CrispVector.replacePath(of: perimeterHalo, with: boundary)
        CrispVector.replacePath(of: perimeter, with: boundary)
        CrispVector.replacePath(of: interior, with: path(CourtGeometry.nonVolleyLines + CourtGeometry.serviceLines))

        let rails = [-0.65, CourtGeometry.width + 0.65].map { x in
            CourtLine(.init(x: x, y: 1), .init(x: x, y: CourtGeometry.length - 1))
        }
        CrispVector.replacePath(of: sidelineRails, with: path(rails))

        // The tape remains exactly on the authoritative net plane. Its mesh
        // hangs toward the viewer; it never displaces a ball, contact or cue.
        let left = point(CourtGeometry.net.start)
        let right = point(CourtGeometry.net.end)
        let scale = sqrt(projection.viewportWidth / 211)
        let drop = 7.0 * scale
        let body = polygon([left, right, CGPoint(x: right.x, y: right.y - drop), CGPoint(x: left.x, y: left.y - drop)])
        CrispVector.replacePath(of: netBody, with: body)
        let shadow = polygon([CGPoint(x: left.x, y: left.y - drop), CGPoint(x: right.x, y: right.y - drop),
                              CGPoint(x: right.x + 0.6 * scale, y: right.y - drop - 2.2 * scale),
                              CGPoint(x: left.x - 0.6 * scale, y: left.y - drop - 2.2 * scale)])
        CrispVector.replacePath(of: netShadow, with: shadow)
        let mesh = CGMutablePath()
        for row in 1...3 {
            let y = left.y - drop * Double(row) / 3
            mesh.move(to: CGPoint(x: left.x, y: y))
            mesh.addLine(to: CGPoint(x: right.x, y: y))
        }
        let cells = 38
        for column in 0...cells {
            let x = left.x + (right.x - left.x) * Double(column) / Double(cells)
            mesh.move(to: CGPoint(x: x, y: left.y - drop))
            mesh.addLine(to: CGPoint(x: x, y: left.y))
        }
        CrispVector.replacePath(of: netMesh, with: mesh)
        CrispVector.replacePath(of: netTape, with: path([CourtGeometry.net]))
        let posts = CGMutablePath()
        let highlights = CGMutablePath()
        for x in [left.x - 1.5 * scale, right.x + 1.5 * scale] {
            posts.move(to: CGPoint(x: x, y: left.y - drop - 1.3 * scale))
            posts.addLine(to: CGPoint(x: x, y: left.y + 1.4 * scale))
            highlights.move(to: CGPoint(x: x - 0.35 * scale, y: left.y - drop))
            highlights.addLine(to: CGPoint(x: x - 0.35 * scale, y: left.y + 1.1 * scale))
        }
        CrispVector.replacePath(of: netPosts, with: posts)
        CrispVector.replacePath(of: netPostHighlights, with: highlights)
    }
}
