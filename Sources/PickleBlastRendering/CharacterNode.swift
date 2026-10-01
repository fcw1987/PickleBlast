import Foundation
import SpriteKit
import PickleBlastCore

/// Approved complete frames are upright billboards; only their ground position
/// is projected. The connected hand/paddle and frame padding are never warped.
final class CharacterNode: SKNode {
    static let canvasWidth = 7.2
    // Arcade revision 1: 42pt baseline × 1.12. This never changes the catch region.
    static let playerVisibleHeight = 47.04
    private let sprite = SKSpriteNode()
    private(set) var identity: String
    private let textures: TextureLibrary
    private let tuning: GameTuning
    private(set) var motion = MotionPlayback()
    private var lastContactLift = 0.0
    private var logicalPosition = Vector2.zero
    private var projection: CourtProjection?
    private var lastFrameName: String?
    var art: CharacterArt { textures.character(identity) }

    init(frontFacing: Bool, textures: TextureLibrary, tuning: GameTuning = GameTuning()) {
        identity = frontFacing ? "wall" : "player"
        self.textures = textures
        self.tuning = tuning
        super.init()
        sprite.size = CGSize(width: Self.canvasWidth, height: Self.canvasWidth)
        sprite.anchorPoint = CGPoint(x: art.anchor[0], y: art.anchor[1])
        addChild(sprite)
        if !frontFacing { updateSprite() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frontFacing:textures:)") }
    func reset() { motion = MotionPlayback(); lastContactLift = 0; lastFrameName = nil; sprite.position = .zero }
    func release() {
        sprite.texture = nil
        if identity != "player" { textures.releaseCharacter(identity) }
        reset()
    }
    func selectBoss(_ requested: String) {
        let selected = textures.resolvedCharacterName(requested)
        guard selected != identity else { return }
        release()
        identity = selected
        sprite.anchorPoint = CGPoint(x: art.anchor[0], y: art.anchor[1])
    }
    func advance(x: Double, planeY: Double, delta: Double, frozen: Bool,
                 prediction: (clip: String, arrival: Double, offset: Double)?,
                 projection: CourtProjection? = nil) {
        self.projection = projection
        logicalPosition = Vector2(x: x, y: planeY)
        var logicalCanvas = Self.canvasWidth
        if let projection {
            let displayFactor = sqrt(projection.viewportWidth / 211)
            let visibleHeight = (identity == "player" ? Self.playerVisibleHeight : 33.0) * displayFactor
            // Fixed alpha unions of the supplied Runtime128 pack, never a
            // per-frame crop/recenter. Keep the complete square canvas.
            let visibleFraction = (identity == "player" ? 82.0 : 74.0) / 128
            let canvas = visibleHeight / visibleFraction
            sprite.size = CGSize(width: canvas, height: canvas)
            // Motion travel is in logical feet. Convert the billboard's point
            // size back to those same units so the approved stride stays grounded.
            logicalCanvas = canvas / projection.scale(atLogicalY: planeY)
        } else {
            sprite.size = CGSize(width: Self.canvasWidth, height: Self.canvasWidth)
        }
        motion.advance(x: x, delta: delta, frozen: frozen, art: art,
                       spriteWidth: logicalCanvas, prediction: prediction)
        let reference = art.clips["forehand"]!.frames[art.clips["forehand"]!.contactIndex!]
        let ground = projected(logicalPosition)
        position = CGPoint(x: ground.x, y: ground.y - local(reference.paddleCenter).y)
        updateSprite()
    }
    func contact(clip: String, offset: Double, lift: Double = 0) {
        motion.contact(clip: clip, offset: offset, art: art)
        lastContactLift = lift
        updateSprite()
    }
    private func projected(_ point: Vector2) -> Vector2 {
        projection?.screenPoint(for: point) ?? point
    }
    private func local(_ point: [Double]) -> CGPoint {
        CGPoint(x: (point[0] / art.canvasSize[0] - art.anchor[0]) * sprite.size.width,
                y: (1 - point[1] / art.canvasSize[1] - art.anchor[1]) * sprite.size.height)
    }
    private func updateSprite() {
        let clip = art.clips[motion.clip]!
        let frameName = clip.frames[clip.frameIndex(at: motion.elapsed)].name
        if lastFrameName != frameName || sprite.texture == nil {
            sprite.texture = textures.texture(atlas: art.atlas, name: frameName)
            lastFrameName = frameName
        }
        let progress = motion.registrationWeight(art: art)
        // Ease the existing contact registration, without retiming approved frames.
        let weight = identity == "player" ? progress * progress * (3 - 2 * progress) : progress
        if let index = clip.contactIndex {
            let contact = local(clip.frames[index].paddleCenter)
            let reference = local(art.clips["forehand"]!.frames[art.clips["forehand"]!.contactIndex!].paddleCenter)
            let ground = projected(logicalPosition)
            let destination = projected(Vector2(x: logicalPosition.x + motion.contactOffset,
                                               y: logicalPosition.y + (motion.confirmed ? lastContactLift : 0)))
            // At actual contact, the one embedded paddle meets the independently
            // projected authoritative ball. Neither physics nor the ball is moved.
            var correction = CGPoint(x: destination.x - ground.x - contact.x,
                                     y: reference.y - contact.y + destination.y - ground.y)
            if identity == "player" {
                // Whole-frame reach remains bounded: no detached paddle, arm warp,
                // or unbounded correction if an event is consumed after ball travel.
                let visibleHeight = sprite.size.height * 82 / 128
                let horizontalLimit = visibleHeight * tuning.playerVisualReachHorizontalFraction
                let verticalLimit = visibleHeight * tuning.playerVisualReachVerticalFraction
                correction.x = min(horizontalLimit, max(-horizontalLimit, correction.x))
                correction.y = min(verticalLimit, max(-verticalLimit, correction.y))
            }
            sprite.position = CGPoint(x: correction.x * weight, y: correction.y * weight)
        } else { sprite.position = .zero }
    }
}
