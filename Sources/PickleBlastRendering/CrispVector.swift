import CoreGraphics
import SpriteKit

/// SpriteKit antialiases small shape paths in their local coordinate space. Court
/// feet are much smaller than display points, so rasterizing them directly and
/// scaling the world enlarges that antialiasing fringe. Author paths at 8× local
/// resolution and cancel that scale on the shape, preserving all court geometry.
enum CrispVector {
    static let resolution: CGFloat = 8

    /// Call once after setting a shape's logical path and line width.
    static func prepare(_ node: SKShapeNode) {
        if let path = node.path { replacePath(of: node, with: path) }
        node.lineWidth *= resolution
        node.setScale(1 / resolution)
    }

    /// For development-only dynamic collision paths; preserves the prepared scale.
    static func replacePath(of node: SKShapeNode, with path: CGPath) {
        var transform = CGAffineTransform(scaleX: resolution, y: resolution)
        node.path = path.copy(using: &transform)
    }

    static func setVisualScale(_ scale: CGFloat, on node: SKShapeNode) {
        node.setScale(scale / resolution)
    }
}
