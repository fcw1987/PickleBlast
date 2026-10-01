import Foundation
import PickleBlastCore
import SpriteKit

final class TargetNode: SKNode {
    private let sprite = SKSpriteNode()
    private let textures: TextureLibrary
    private var flashUntil = 0.0
    private var lastHealth: Int?
    private var damageBlend = 0.0
    private(set) var logicalPosition = Vector2.zero
    init(target: TargetState, textures: TextureLibrary) {
        self.textures = textures
        super.init()
        addChild(sprite)
        apply(target)
    }
    required init?(coder: NSCoder) { fatalError("Use init(target:textures:)") }
    func flash(at time: Double) { flashUntil = time + 0.10 }
    func resetFeedback() { flashUntil = 0 }
    func update(time: Double) {
        sprite.color = time < flashUntil ? .white : Neon.magenta
        sprite.colorBlendFactor = time < flashUntil ? 0.65 : damageBlend
    }
    func apply(_ target: TargetState, projection: CourtProjection? = nil) {
        logicalPosition = target.position
        let point = projection?.screenPoint(for: target.position) ?? target.position
        position = CGPoint(x: point.x, y: point.y)
        let key: String
        switch target.kind {
        case .paddle: key = ["targetPaddleCyan", "targetPaddleLime", "targetPaddleMagenta"][target.id % 3]
        case .cone: key = "targetCone"
        case .basket: key = target.isDamaged ? "targetBasketDamaged" : "targetBasket"
        }
        if lastHealth != target.health {
            lastHealth = target.health
            sprite.texture = textures.supporting(key)
        }
        // Durable paddles retain the approved silhouette and palette while each
        // lost health step adds a restrained persistent magenta damage tint.
        damageBlend = target.kind == .paddle && target.maximumHealth > 1
            ? Double(target.maximumHealth - target.health) / Double(target.maximumHealth) * 0.45 : 0
        // Opacity also distinguishes damage on the already-magenta approved art.
        sprite.alpha = target.kind == .paddle
            ? max(0.64, 1 - Double(target.maximumHealth - target.health) * 0.12) : 1
        let visible: Double
        if let projection {
            visible = target.radius * 2 * projection.scale(atLogicalY: target.position.y)
        } else { visible = target.radius * 2 }
        let side: Double
        if target.kind == .paddle {
            // Approved 128px paddle: opaque head spans x36...91, centered
            // near (64,50); the narrow handle is decorative. Register its head,
            // not the transparent canvas or the full handle-inclusive alpha union.
            side = visible / (56.0 / 128)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 1 - 50.0 / 128)
        } else {
            side = visible / textures.manifest.supporting[key]!.visibleFraction
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        }
        sprite.size = CGSize(width: side, height: side)
    }
}
