import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Projected billboards, contacts and court presentation")
@MainActor
struct PresentationSceneTests {
    // SKNode position storage and coordinate conversion round at Float precision.
    // The observed maximum discrepancy was 7.621489e-6 pt (under half a Float
    // ULP near 200 pt). Allow a few such storage/conversion steps, still far
    // below a visible pixel. Pure Double projection and stride checks stay strict.
    private let spriteKitPointTolerance = 0.00005

    private func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.000001) {
        #expect(abs(actual - expected) <= tolerance,
                "Actual \(actual), expected \(expected), absolute error \(abs(actual - expected)), tolerance \(tolerance)")
    }

    private func spriteKitNear(_ actual: Double, _ expected: Double) {
        near(actual, expected, tolerance: spriteKitPointTolerance)
    }

    private func sprite(in node: CharacterNode) throws -> SKSpriteNode {
        try #require(node.children.first as? SKSpriteNode)
    }

    private func paddlePoint(in node: CharacterNode, clip name: String) throws -> Vector2 {
        let image = try sprite(in: node)
        let clip = try #require(node.art.clips[name])
        let frame = clip.frames[try #require(clip.contactIndex)]
        let local = CGPoint(
            x: (frame.paddleCenter[0] / node.art.canvasSize[0] - image.anchorPoint.x) * image.size.width,
            y: (1 - frame.paddleCenter[1] / node.art.canvasSize[1] - image.anchorPoint.y) * image.size.height)
        return Vector2(x: node.position.x + image.position.x + local.x,
                       y: node.position.y + image.position.y + local.y)
    }

    @Test("Complete player and Wall contact frames meet the projected ball at center and both edges", arguments: [(211.0, 257.0), (162.0, 197.0)])
    func projectedContacts(size: (Double, Double)) throws {
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1,
                                         safeTop: 28, safeBottom: 8, safeLeading: 2, safeTrailing: 4)
        let textures = TextureLibrary()
        let tuning = GameTuning()
        for front in [false, true] {
            let node = CharacterNode(frontFacing: front, textures: textures)
            let margin = front ? tuning.boss.halfWidth : tuning.playerMargin
            let plane = front ? tuning.boss.y - tuning.ballRadius : tuning.playerY + tuning.ballRadius
            let lift = front ? -0.65 : 0.65
            for x in [margin, CourtGeometry.centerX, CourtGeometry.width - margin] {
                for (name, localOffset) in [("forehand", 1.2), ("backhand", -1.2), ("block", 0.0)] {
                    let facingOffset = front ? -localOffset : localOffset
                    let ballX = min(CourtGeometry.width - tuning.ballRadius, max(tuning.ballRadius, x + facingOffset))
                    node.advance(x: x, planeY: plane, delta: 0, frozen: false,
                                 prediction: nil, projection: projection)
                    node.contact(clip: name, offset: ballX - x, lift: lift)
                    let actual = try paddlePoint(in: node, clip: name)
                    let expected = projection.screenPoint(for: .init(x: ballX, y: plane + lift))
                    spriteKitNear(actual.x, expected.x)
                    spriteKitNear(actual.y, expected.y)
                    #expect(node.children.count == 1, "Complete frames must not acquire a second paddle rig")
                    #expect(node.motion.confirmed)
                    #expect(node.physicsBody == nil)
                }
            }
        }
    }

    @Test("Projected characters retain a square canvas, approved anchor and readable artwork bounds", arguments: [(211.0, 257.0), (162.0, 197.0)])
    func readableUprightBillboards(size: (Double, Double)) throws {
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1)
        let textures = TextureLibrary()
        let tuning = GameTuning()
        for front in [false, true] {
            let node = CharacterNode(frontFacing: front, textures: textures)
            let plane = front ? tuning.boss.y - tuning.ballRadius : tuning.playerY + tuning.ballRadius
            node.advance(x: 10, planeY: plane, delta: 0, frozen: false, prediction: nil, projection: projection)
            let image = try sprite(in: node)
            let canvasSize = image.size
            for name in ["forehand", "backhand", "block"] {
                node.contact(clip: name, offset: 0)
                let clip = try #require(node.art.clips[name])
                let frame = clip.frames[try #require(clip.contactIndex)]
                let visibleHeight = (frame.bounds[3] - frame.bounds[1]) / node.art.canvasSize[1] * image.size.height
                // This checks the source-art bounds in points, not a claim about
                // physical readability or a screenshot acceptance threshold.
                #expect(visibleHeight >= (front ? 24 : 32))
                #expect(visibleHeight <= 50)
                #expect(image.size == canvasSize, "Contact frames must not be independently cropped or resized")
                near(image.size.width, image.size.height)
                near(image.anchorPoint.x, node.art.anchor[0])
                near(image.anchorPoint.y, node.art.anchor[1])
                near(image.xScale, 1)
                near(image.yScale, 1)
                near(image.zRotation, 0)
                #expect(image.texture?.filteringMode == .linear)
                #expect(image.physicsBody == nil)
            }
        }
    }

    @Test("Billboard point sizes convert back to logical stride units before distance drives shuffle", arguments: [(211.0, 257.0), (162.0, 197.0)])
    func logicalStrideFromProjectedSize(size: (Double, Double)) throws {
        let projection = CourtProjection(viewportWidth: size.0, viewportHeight: size.1)
        let textures = TextureLibrary()
        let tuning = GameTuning()
        for front in [false, true] {
            let node = CharacterNode(frontFacing: front, textures: textures)
            let plane = front ? tuning.boss.y - tuning.ballRadius : tuning.playerY + tuning.ballRadius
            node.advance(x: 10, planeY: plane, delta: 0, frozen: false, prediction: nil, projection: projection)
            let image = try sprite(in: node)
            let right = try #require(node.art.clips["move_right"])
            let logicalCanvas = image.size.width / projection.scale(atLogicalY: plane)
            let logicalStride = abs(try #require(right.strideSourcePixels)) / node.art.canvasSize[0] * logicalCanvas
            node.advance(x: 10 + logicalStride * 0.375, planeY: plane, delta: 0,
                         frozen: false, prediction: nil, projection: projection)
            #expect(node.motion.clip == "move_right")
            near(node.motion.distance, logicalStride * 0.375)
            near(node.motion.elapsed, right.duration * 0.375)
            let left = try #require(node.art.clips["move_left"])
            node.advance(x: 10 + logicalStride * 0.25, planeY: plane, delta: 0,
                         frozen: false, prediction: nil, projection: projection)
            #expect(node.motion.clip == "move_left")
            near(node.motion.distance, logicalStride * 0.5)
            near(node.motion.elapsed, left.duration * 0.5)
            let elapsed = node.motion.elapsed
            let resized = CourtProjection(viewportWidth: size.0 + 20, viewportHeight: size.1 + 20)
            node.advance(x: 10 + logicalStride * 0.25, planeY: plane, delta: 0,
                         frozen: false, prediction: nil, projection: resized)
            near(node.motion.elapsed, elapsed)
            near(node.motion.distance, logicalStride * 0.5)
        }
    }

    @Test("Scene resize projects ball and targets while preserving the complete authoritative engine state")
    func scenePositionsAndStatePreservation() throws {
        let engine = GameEngine(seed: 7)
        for _ in 0..<145 { engine.update(delta: 1.0 / 120) }
        engine.setPlayerX(6.5)
        let authoritative = engine.state
        let ballState = try #require(authoritative.ball)
        #expect(!authoritative.targets.isEmpty)
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257), tuning: engine.tuning)
        for size in [CGSize(width: 211, height: 257), CGSize(width: 162, height: 197)] {
            scene.setViewport(size, safeTop: 30, safeBottom: 10, safeLeading: 3, safeTrailing: 7)
            scene.render(state: engine.state, events: [], delta: 0)
            #expect(engine.state == authoritative)
            let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
            let world = try #require(player.parent)
            near(world.xScale, 1)
            near(world.yScale, 1)
            let ball = try #require(world.children.compactMap { $0 as? SKSpriteNode }.first { $0.zPosition == 10 })
            let expectedBall = scene.courtProjection.screenPoint(for: ballState.position)
            spriteKitNear(ball.position.x, expectedBall.x)
            spriteKitNear(ball.position.y, expectedBall.y)
            #expect(!ball.isHidden)
            #expect(ball.physicsBody == nil)
            let targets = world.children.compactMap { $0 as? TargetNode }
            #expect(targets.count == authoritative.targets.count)
            let actualCenters = targets.map { Vector2(x: $0.position.x, y: $0.position.y) }
            for target in authoritative.targets {
                let expected = scene.courtProjection.screenPoint(for: target.position)
                #expect(actualCenters.contains { abs($0.x - expected.x) <= spriteKitPointTolerance && abs($0.y - expected.y) <= spriteKitPointTolerance },
                        "Target \(target.id): expected \(expected), actual centers \(actualCenters), SpriteKit point tolerance \(spriteKitPointTolerance)")
            }
            let playerScreen = scene.courtProjection.screenPoint(for: .init(x: authoritative.playerX,
                                                                           y: engine.tuning.playerY + engine.tuning.ballRadius))
            near(scene.courtX(forViewX: playerScreen.x), authoritative.playerX)
        }
    }

    @Test("Paused impact keeps its logical origin and remaining lifetime across viewport and safe-inset changes")
    func pausedImpactReprojectsWithoutRestartingAge() throws {
        let tuning = GameTuning()
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257), tuning: tuning)
        let origin = Vector2(x: 14, y: tuning.playerY + tuning.ballRadius)
        var state = GameState()
        state.phase = .playing
        scene.render(state: state, events: [.paddleContact(x: origin.x, side: .forehand, centered: false)], delta: 0)
        let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let world = try #require(player.parent)
        let effect = try #require(world.children.compactMap { $0 as? SKSpriteNode }.first { $0.zPosition == 6 && !$0.isHidden })
        let originalPosition = effect.position
        state.simulationTime += 0.10
        scene.render(state: state, events: [], delta: 0.10)
        let agedTexture = try #require(effect.texture)

        state.isPaused = true
        state.simulationTime += 3_600
        scene.render(state: state, events: [], delta: 3_600)
        scene.setViewport(CGSize(width: 162, height: 197), safeTop: 30, safeBottom: 10,
                          safeLeading: 3, safeTrailing: 7)
        scene.render(state: state, events: [], delta: 0)
        let expected = scene.courtProjection.screenPoint(for: origin)
        #expect(effect.position != originalPosition, "The fixture must actually move the projected impact")
        spriteKitNear(effect.position.x, expected.x)
        spriteKitNear(effect.position.y, expected.y)
        #expect(!effect.isHidden && effect.texture === agedTexture,
                "Resizing a paused impact must preserve its visible animation frame")

        state.isPaused = false
        state.resumeCountdown = 0.5
        state.simulationTime += 0.5
        scene.render(state: state, events: [], delta: 0.5)
        #expect(!effect.isHidden && effect.texture === agedTexture)
        spriteKitNear(effect.position.x, expected.x)
        spriteKitNear(effect.position.y, expected.y)

        // The 0.22-second effect already used 0.10 seconds before pausing.
        // Check both sides of its remaining lifetime so resizing cannot silently
        // restart its age while preserving only its current texture.
        state.resumeCountdown = 0
        state.simulationTime += 0.11
        scene.render(state: state, events: [], delta: 0.11)
        #expect(!effect.isHidden)
        state.simulationTime += 0.02
        scene.render(state: state, events: [], delta: 0.02)
        #expect(effect.isHidden)
    }

    @Test("Rendered court paths contain exactly the projected regulation lines and net after resize")
    func projectedRegulationPaths() throws {
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257))
        for size in [CGSize(width: 211, height: 257), CGSize(width: 162, height: 197)] {
            scene.setViewport(size, safeTop: 28, safeBottom: 8)
            scene.render(state: GameState(), events: [], delta: 0)
            let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
            let world = try #require(player.parent)
            let court = try #require(world.children.first { $0.children.filter { $0 is SKShapeNode }.count == 3 })
            let shapes = court.children.compactMap { $0 as? SKShapeNode }
            var boundaryCopies = 0
            var netCopies = 0
            for shape in shapes {
                let vertices = try pathVertices(shape, relativeTo: world)
                let lines: [CourtLine]
                if vertices.count == CourtGeometry.lines.count * 2 {
                    lines = CourtGeometry.lines
                    boundaryCopies += 1
                } else {
                    #expect(vertices.count == 2)
                    lines = [CourtGeometry.net]
                    netCopies += 1
                }
                let expected = lines.flatMap { [scene.courtProjection.screenPoint(for: $0.start),
                                                scene.courtProjection.screenPoint(for: $0.end)] }
                #expect(vertices.count == expected.count)
                for (actual, desired) in zip(vertices, expected) {
                    spriteKitNear(actual.x, desired.x)
                    spriteKitNear(actual.y, desired.y)
                }
            }
            #expect(boundaryCopies == 2 && netCopies == 1)
        }
    }

    @Test("Atmosphere aspect-fills below the authoritative court and disappears during blackout",
          arguments: [(211.0, 257.0, 56.5, 40.0), (162.0, 197.0, 40.0, 19.0)])
    func decorativeBackground(size: (Double, Double, Double, Double)) throws {
        let engine = GameEngine(seed: 19)
        let authoritative = engine.state
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1), tuning: engine.tuning)
        scene.setViewport(CGSize(width: size.0, height: size.1), safeTop: size.2, safeBottom: size.3,
                          safeLeading: 2, safeTrailing: 2)
        scene.render(state: engine.state, events: [], delta: 0)
        #expect(engine.state == authoritative, "Decorative layout must not mutate gameplay")

        let background = try #require(scene.childNode(withName: "//decorativeBackground") as? SKSpriteNode)
        let world = try #require(background.parent)
        #expect(background.zPosition == -10)
        #expect(background.alpha == 0.5)
        #expect(background.physicsBody == nil)
        #expect(background.texture?.filteringMode == .linear)
        spriteKitNear(background.position.x, scene.courtProjection.centerX)
        spriteKitNear(background.position.y, size.1 / 2)
        #expect(background.size.width >= size.0 && background.size.height >= size.1)
        near(background.size.width / background.size.height, 1)

        let court = try #require(world.children.first { $0.children.filter { $0 is SKShapeNode }.count == 3 })
        let player = try #require(world.children.compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let ball = try #require(world.children.compactMap { $0 as? SKSpriteNode }.first { $0.zPosition == 10 })
        #expect(background.zPosition < court.zPosition)
        #expect(court.zPosition < player.zPosition && player.zPosition < ball.zPosition)

        var blackout = engine.state
        blackout.phase = .blackout
        scene.render(state: blackout, events: [], delta: 0)
        #expect(world.isHidden, "True-black transition must hide the decorative arena with gameplay")
    }

    private func pathVertices(_ shape: SKShapeNode, relativeTo world: SKNode) throws -> [Vector2] {
        let path = try #require(shape.path)
        var vertices: [Vector2] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                let point = shape.convert(element.pointee.points[0], to: world)
                vertices.append(.init(x: point.x, y: point.y))
            default:
                Issue.record("Regulation court lines must contain only straight path segments")
            }
        }
        return vertices
    }
}
