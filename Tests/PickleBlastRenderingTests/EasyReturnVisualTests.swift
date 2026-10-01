import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Easy return contact presentation")
@MainActor
struct EasyReturnVisualTests {
    private func near(_ value: Double, _ expected: Double, tolerance: Double = 0.0001) {
        #expect(abs(value - expected) < tolerance)
    }

    private func projection(small: Bool) -> CourtProjection {
        small
            ? CourtProjection(viewportWidth: 162, viewportHeight: 197,
                              safeTop: 40, safeBottom: 19, safeLeading: 2, safeTrailing: 2)
            : CourtProjection(viewportWidth: 211, viewportHeight: 257,
                              safeTop: 56.5, safeBottom: 40, safeLeading: 2, safeTrailing: 2)
    }

    private func paddleCenter(_ node: CharacterNode, sprite: SKSpriteNode) throws -> CGPoint {
        let clip = try #require(node.art.clips[node.motion.clip])
        let frame = clip.frames[try #require(clip.contactIndex)]
        return CGPoint(
            x: node.position.x + sprite.position.x
                + (frame.paddleCenter[0] / node.art.canvasSize[0] - sprite.anchorPoint.x) * sprite.size.width,
            y: node.position.y + sprite.position.y
                + (1 - frame.paddleCenter[1] / node.art.canvasSize[1] - sprite.anchorPoint.y) * sprite.size.height)
    }

    @Test("The full 6.5 foot reach and radius fringe meet the one approved paddle at actual Watch safe areas",
          arguments: [false, true])
    func expandedEdgeContacts(small: Bool) throws {
        let tuning = GameTuning()
        near(tuning.playerHalfWidth * 2, 6.5)
        let projection = projection(small: small)
        let node = CharacterNode(frontFacing: false, textures: TextureLibrary(), tuning: tuning)
        let plane = tuning.playerY + tuning.ballRadius
        let effectiveHalfWidth = tuning.playerHalfWidth + tuning.ballRadius
        let expectedHeight = 47.04 * sqrt(projection.viewportWidth / 211)
        for playerX in [tuning.playerMargin, 5, 10, 15, 20 - tuning.playerMargin] {
            for fraction in [-1.0, -0.8, -0.3, -0.17, 0, 0.17, 0.3, 0.8, 1.0] {
                let ballX = min(20 - tuning.ballRadius,
                                max(tuning.ballRadius, playerX + fraction * effectiveHalfWidth))
                let offset = ballX - playerX
                let clip = abs(offset) <= tuning.playerHalfWidth * tuning.centeredContactFraction
                    ? "block" : (offset < 0 ? "backhand" : "forehand")
                node.advance(x: playerX, planeY: plane, delta: 0, frozen: false,
                             prediction: nil, projection: projection)
                node.contact(clip: clip, offset: offset)
                let sprite = try #require(node.children.first as? SKSpriteNode)
                let paddle = try paddleCenter(node, sprite: sprite)
                let contact = projection.screenPoint(for: .init(x: ballX, y: plane))
                near(paddle.x, contact.x)
                near(paddle.y, contact.y)
                near(sprite.size.height * 82 / 128, expectedHeight)
                near(sprite.size.width, sprite.size.height)
                near(sprite.xScale, 1); near(sprite.yScale, 1)
                near(sprite.zRotation, 0)
                #expect(node.children.count == 1)
                #expect(abs(sprite.position.x) <= expectedHeight * tuning.playerVisualReachHorizontalFraction)
                #expect(abs(sprite.position.y) <= expectedHeight * tuning.playerVisualReachVerticalFraction)
                #expect(node.physicsBody == nil && sprite.physicsBody == nil)
                #expect(sprite.texture?.size() == CGSize(width: 128, height: 128))
            }
        }
    }

    @Test("Expanded reach eases continuously through the unchanged approved anticipation and recovery",
          arguments: [false, true])
    func boundedReachTimeline(small: Bool) throws {
        let tuning = GameTuning()
        let node = CharacterNode(frontFacing: false, textures: TextureLibrary(), tuning: tuning)
        let projection = projection(small: small)
        let plane = tuning.playerY + tuning.ballRadius
        let sprite = try #require(node.children.first as? SKSpriteNode)
        for (clip, direction) in [("backhand", -1.0), ("forehand", 1.0)] {
            node.reset()
            let animation = try #require(node.art.clips[clip])
            let contactTime = try #require(animation.contactTime)
            let offset = direction * (tuning.playerHalfWidth + tuning.ballRadius)
            var last = CGPoint.zero
            var largestStep = 0.0
            for step in 0...120 {
                let elapsed = contactTime * Double(step) / 120
                node.advance(x: 10, planeY: plane, delta: contactTime / 120, frozen: false,
                             prediction: (clip, contactTime - elapsed, offset), projection: projection)
                largestStep = max(largestStep, hypot(sprite.position.x - last.x, sprite.position.y - last.y))
                last = sprite.position
            }
            let anticipatedContact = sprite.position
            node.contact(clip: clip, offset: offset)
            near(sprite.position.x, anticipatedContact.x)
            near(sprite.position.y, anticipatedContact.y)
            #expect(node.motion.contactCount == 1)
            let frozenTime = node.motion.elapsed
            node.advance(x: 10, planeY: plane, delta: 100, frozen: true,
                         prediction: nil, projection: projection)
            #expect(sprite.position == anticipatedContact)
            near(node.motion.elapsed, frozenTime)
            for _ in 0..<90 {
                node.advance(x: 10, planeY: plane, delta: 1.0 / 120, frozen: false,
                             prediction: nil, projection: projection)
                largestStep = max(largestStep, hypot(sprite.position.x - last.x, sprite.position.y - last.y))
                last = sprite.position
            }
            #expect(largestStep < 1)
            near(sprite.position.x, 0); near(sprite.position.y, 0)
            #expect(node.motion.contactCount == 1)
        }
    }

    @Test("The visual assist limit is independently tunable without changing sprite size or authoritative state")
    func independentReachLimit() throws {
        var tuning = GameTuning()
        tuning.playerVisualReachHorizontalFraction = 0.10
        tuning.playerVisualReachVerticalFraction = 0.05
        let node = CharacterNode(frontFacing: false, textures: TextureLibrary(), tuning: tuning)
        node.advance(x: 10, planeY: tuning.playerY + tuning.ballRadius, delta: 0, frozen: false,
                     prediction: nil, projection: projection(small: false))
        node.contact(clip: "backhand", offset: -3.55, lift: 5)
        let sprite = try #require(node.children.first as? SKSpriteNode)
        let height = sprite.size.height * 82 / 128
        near(height, 47.04)
        near(abs(sprite.position.x), height * 0.10)
        near(abs(sprite.position.y), height * 0.05)
    }

    @Test("Centered contact registers at the authoritative plane while the ball separates above the complete character",
          arguments: [false, true])
    func centeredBallSeparates(small: Bool) throws {
        let tuning = GameTuning()
        let projection = projection(small: small)
        let size = CGSize(width: projection.viewportWidth, height: projection.viewportHeight)
        let scene = PickleBlastScene(size: size, tuning: tuning)
        scene.setViewport(size, safeTop: small ? 40 : 56.5, safeBottom: small ? 19 : 40,
                          safeLeading: 2, safeTrailing: 2)
        let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }
            .first { $0.identity == "player" })
        let sprite = try #require(player.children.first as? SKSpriteNode)
        let world = try #require(player.parent)
        let ballNode = try #require(world.children.compactMap { $0 as? SKSpriteNode }.first { $0.zPosition == 10 })
        var state = GameState()
        state.phase = .playing
        let plane = tuning.playerY + tuning.ballRadius
        state.ball = BallState(position: .init(x: 10, y: plane + 0.7), velocity: .init(x: 0, y: 26))
        scene.render(state: state, events: [.paddleContact(x: 10, side: .block, centered: true)], delta: 0)
        let paddle = try paddleCenter(player, sprite: sprite)
        let contact = projection.screenPoint(for: .init(x: 10, y: plane))
        near(paddle.x, contact.x); near(paddle.y, contact.y)
        #expect(ballNode.position.y > paddle.y)
        #expect(ballNode.zPosition > player.zPosition)
        var previousBallY = ballNode.position.y
        for step in 1...12 {
            state.simulationTime = Double(step) / 30
            state.ball!.position.y = plane + 0.7 + state.simulationTime * 26
            let unchanged = state
            scene.render(state: state, events: [], delta: 1.0 / 30)
            #expect(state == unchanged)
            let expected = projection.screenPoint(for: state.ball!.position)
            near(ballNode.position.x, expected.x, tolerance: 0.0002)
            near(ballNode.position.y, expected.y, tolerance: 0.0002)
            #expect(ballNode.position.y > previousBallY)
            #expect(ballNode.zPosition > player.zPosition && !ballNode.isHidden)
            #expect(player.motion.contactCount == 1)
            previousBallY = ballNode.position.y
        }
    }
}
