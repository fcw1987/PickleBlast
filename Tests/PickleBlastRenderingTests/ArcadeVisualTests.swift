import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Arcade visual reach and durable targets")
@MainActor
struct ArcadeVisualTests {
    @Test("Arcade recoil is bounded, settles, freezes by scene time and respects Reduced Motion")
    func boundedTargetRecoil() throws {
        let target = try #require(AuthoredWaves.targets(for: 1).first)
        let node = TargetNode(target: target, textures: TextureLibrary())
        let sprite = try #require(node.children.first as? SKSpriteNode)
        let center = node.position
        node.flash(at: 2)
        node.update(time: 2.06)
        #expect(sprite.xScale != 1 || sprite.zRotation != 0)
        let scale = sprite.xScale, rotation = sprite.zRotation
        node.update(time: 2.06) // Frozen presentation clock, as during pause.
        #expect(sprite.xScale == scale && sprite.zRotation == rotation)
        for tick in 0...36 {
            node.update(time: 2 + Double(tick) / 120)
            #expect(abs(sprite.xScale - 1) <= 0.055 && abs(sprite.zRotation) <= 0.045)
            #expect(node.position == center && node.children.count == 1)
            #expect(!node.hasActions() && !sprite.hasActions())
        }
        node.update(time: 3)
        #expect(sprite.xScale == 1 && sprite.zRotation == 0)
        node.flash(at: 4)
        node.update(time: 4.06, reduceMotion: true)
        #expect(sprite.xScale == 1 && sprite.zRotation == 0)
        near(sprite.colorBlendFactor, 0.65)
        node.resetFeedback()
        node.update(time: 4.06)
        #expect(sprite.xScale == 1 && sprite.zRotation == 0)
    }

    private func near(_ value: Double, _ expected: Double, tolerance: Double = 0.00005) {
        #expect(abs(value - expected) < tolerance)
    }

    @Test("Player alone grows twelve percent and every valid contact stays within the bounded registration",
          arguments: [(211.0, 257.0), (162.0, 197.0)])
    func widerContactAlignment(size: (Double, Double)) throws {
        let textures = TextureLibrary()
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1)
        let tuning = GameTuning()
        let player = CharacterNode(frontFacing: false, textures: textures)
        let plane = tuning.playerY + tuning.ballRadius
        for playerX in [tuning.playerMargin, 10, 20 - tuning.playerMargin] {
            for fraction in [-1.0, -0.5, 0, 0.5, 1.0] {
                let requestedX = playerX + fraction * (tuning.playerHalfWidth + tuning.ballRadius)
                let ballX = max(tuning.ballRadius, min(20 - tuning.ballRadius, requestedX))
                let offset = ballX - playerX
                let clipName = abs(offset) <= tuning.playerHalfWidth * tuning.centeredContactFraction
                    ? "block" : (offset > 0 ? "forehand" : "backhand")
                player.advance(x: playerX, planeY: plane, delta: 0, frozen: false,
                               prediction: nil, projection: projection)
                player.contact(clip: clipName, offset: offset)
                let sprite = try #require(player.children.first as? SKSpriteNode)
                let visibleHeight = sprite.size.height * 82 / 128
                near(visibleHeight, 42 * 1.12 * sqrt(size.0 / 211))
                #expect(abs(sprite.position.x) <= visibleHeight * tuning.playerVisualReachHorizontalFraction + 0.00005)
                #expect(abs(sprite.position.y) <= visibleHeight * 0.30 + 0.00005)
                let clip = try #require(player.art.clips[clipName])
                let frame = clip.frames[try #require(clip.contactIndex)]
                let paddle = CGPoint(x: (frame.paddleCenter[0] / 512 - sprite.anchorPoint.x) * sprite.size.width,
                                     y: (1 - frame.paddleCenter[1] / 512 - sprite.anchorPoint.y) * sprite.size.height)
                let expected = projection.screenPoint(for: .init(x: ballX, y: plane))
                near(player.position.x + sprite.position.x + paddle.x, expected.x)
                near(player.position.y + sprite.position.y + paddle.y, expected.y)
                #expect(player.children.count == 1)
                near(sprite.xScale, 1); near(sprite.yScale, 1)
            }
        }
        let boss = CharacterNode(frontFacing: true, textures: textures)
        boss.advance(x: 10, planeY: tuning.boss.y, delta: 0, frozen: false,
                     prediction: nil, projection: projection)
        let bossSprite = try #require(boss.children.first as? SKSpriteNode)
        near(bossSprite.size.height * 74 / 128, 33 * sqrt(size.0 / 211))
    }

    @Test("Canceled prediction smoothly releases bounded translation while paused contact remains frozen")
    func registrationEnvelope() throws {
        let player = CharacterNode(frontFacing: false, textures: TextureLibrary())
        let projection = CourtProjection(viewportWidth: 211, viewportHeight: 257)
        let tuning = GameTuning()
        let plane = tuning.playerY + tuning.ballRadius
        player.advance(x: 10, planeY: plane, delta: 0, frozen: false,
                       prediction: nil, projection: projection)
        player.contact(clip: "backhand", offset: -2.775)
        let sprite = try #require(player.children.first as? SKSpriteNode)
        let atContact = sprite.position
        player.advance(x: 10, planeY: plane, delta: 50, frozen: true,
                       prediction: nil, projection: projection)
        #expect(sprite.position == atContact)
        var previous = abs(sprite.position.x)
        var largestStep = 0.0
        for _ in 0..<60 {
            player.advance(x: 10, planeY: plane, delta: 1.0 / 120, frozen: false,
                           prediction: nil, projection: projection)
            let current = abs(sprite.position.x)
            #expect(current <= previous + 0.00005)
            largestStep = max(largestStep, abs(current - previous))
            previous = current
        }
        #expect(largestStep < 1.5)
        near(sprite.position.x, 0)
    }

    @Test("Approved paddle head sits on its collider and durable damage remains visible after flash")
    func durableTargetPresentation() throws {
        let projection = CourtProjection(viewportWidth: 162, viewportHeight: 197)
        let textures = TextureLibrary()
        let tuning = GameTuning()
        var previousWidth = 0.0
        for (size, paletteID) in TargetSize.allCases.flatMap({ size in (0..<3).map { (size, $0) } }) {
            let radius = size == .small ? tuning.smallTargetRadius : (size == .medium ? tuning.mediumTargetRadius : tuning.largeTargetRadius)
            var target = TargetState(id: paletteID, kind: .paddle, position: .init(x: 10, y: 35), radius: radius, size: size)
            let node = TargetNode(target: target, textures: textures)
            node.apply(target, projection: projection)
            let sprite = try #require(node.children.first as? SKSpriteNode)
            near(sprite.anchorPoint.x, 0.5)
            near(sprite.anchorPoint.y, 1 - 50.0 / 128)
            near(sprite.size.width * 56 / 128, radius * 2 * projection.scale(atLogicalY: 35))
            #expect(paletteID != 0 || sprite.size.width > previousWidth)
            previousWidth = sprite.size.width
            node.update(time: 1)
            var previousBlend = sprite.colorBlendFactor
            var previousOpacity = sprite.alpha
            while target.health > 1 {
                target.health -= 1
                node.apply(target, projection: projection)
                node.flash(at: 1)
                node.update(time: 1.01)
                near(sprite.colorBlendFactor, 0.65)
                node.update(time: 2)
                #expect(sprite.colorBlendFactor > previousBlend)
                #expect(sprite.alpha < previousOpacity)
                previousBlend = sprite.colorBlendFactor
                previousOpacity = sprite.alpha
            }
            #expect(node.children.count == 1)
            #expect(node.physicsBody == nil && sprite.physicsBody == nil)
        }
    }
}
