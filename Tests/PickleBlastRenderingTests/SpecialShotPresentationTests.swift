import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Committed special shot presentation")
@MainActor
struct SpecialShotPresentationTests {
    private func state(kind: RallyShotKind, flight: LobFlightState? = nil) -> GameState {
        var state = GameState()
        state.mode = .bossRally(kind == .soft ? .dinker : (kind == .lob ? .lobber : .banger))
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: state.bossID)
        state.ball = BallState(position: flight?.groundPosition ?? Vector2(x: 10, y: 22),
                               velocity: flight?.velocity ?? Vector2(x: 0, y: -26))
        state.rallyShot = RallyShotState(rallyID: 1, shotID: 2, kind: kind,
            requestedSpeed: 26, realizedSpeed: 26, lobFlight: flight)
        return state
    }

    private func shape(_ scene: PickleBlastScene, _ name: String) throws -> SKShapeNode {
        try #require(scene.childNode(withName: "//" + name) as? SKShapeNode)
    }

    @Test("Power and soft use different bounded strokes and retain one lime gameplay ball")
    func compactTrails() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        let trail = try shape(scene, "shotTrail")
        let rim = try shape(scene, "shotRim")
        let world = try #require(scene.children.first)
        let allocated = world.children.count
        scene.render(state: state(kind: .power), events: [], delta: 0)
        #expect(!trail.isHidden && !rim.isHidden)
        let powerLength = trail.frame.height
        #expect(powerLength > 7 && powerLength < 15)
        let powerColor = trail.strokeColor.cgColor.components
        scene.render(state: state(kind: .soft), events: [], delta: 0)
        #expect(!trail.isHidden && !rim.isHidden)
        #expect(trail.frame.height < powerLength / 2)
        #expect(trail.strokeColor.cgColor.components != powerColor)
        #expect(try shape(scene, "lobGroundShadow").isHidden)
        #expect(try shape(scene, "lobLandingCue").isHidden)
        #expect(world.children.filter { $0.name == "gameplayBall" }.count == 1)
        #expect(world.children.allSatisfy { $0.physicsBody == nil && !$0.hasActions() })
        for index in 0..<200 {
            var next = state(kind: index.isMultiple(of: 2) ? .power : .soft)
            next.simulationTime = Double(index) / 30
            scene.render(state: next, events: [], delta: 1.0 / 30)
        }
        #expect(world.children.count == allocated)
    }

    @Test("Lob height stays on court and readable through continuous rise and descent on both displays",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func boundedHeight(display: (Double, Double, Double, Double)) {
        let projection = CourtProjection(viewportWidth: display.0, viewportHeight: display.1,
            safeTop: display.2, safeBottom: display.3)
        for originX in [1.75, 10, 18.25] {
            for originY in [39.7, 40.4] {
                for receivingX in [1.2, 10, 18.8] {
                    var flight = LobFlightState(origin: .init(x: originX, y: originY),
                        destination: .init(x: receivingX, y: 2.5), duration: 1.8, peakHeight: 5)
                    var previous: Vector2?
                    var previousOffset = 0.0
                    var maximumOffset = 0.0
                    for index in 0...360 {
                        flight.elapsed = Double(index) / 200
                        let ground = projection.screenPoint(for: flight.groundPosition)
                        let radius = LobScreenProjection.ballRadius(at: flight.groundPosition, projection: projection)
                        let visible = LobScreenProjection.ballPoint(ground: ground, flight: flight,
                            projection: projection, radius: radius)
                        #expect(visible.x == ground.x)
                        #expect(visible.y >= ground.y)
                        #expect(visible.y + radius <= projection.farY - 0.5 + 1e-8)
                        #expect(visible.y + radius < projection.hudY - 10)
                        #expect(visible.x >= radius && visible.x + radius <= display.0)
                        let offset = visible.y - ground.y
                        maximumOffset = max(maximumOffset, offset)
                        if let previous { #expect((visible - previous).length < 2) }
                        if index <= 180 { #expect(offset + 1e-8 >= previousOffset) }
                        else { #expect(offset <= previousOffset + 1e-8) }
                        previousOffset = offset
                        previous = visible
                        if index == 0 || index == 360 { #expect(visible == ground) }
                    }
                    #expect(maximumOffset > 14, "The elevated ball remains visibly separate from its ground reference")
                }
            }
        }
    }

    @Test("Lob arrival meets approved player contact and successful ordinary return clears all elevated cues")
    func contactAndReset() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        let flight = LobFlightState(origin: .init(x: 10, y: 39.7),
            destination: .init(x: 10, y: 2.5), duration: 1.8, elapsed: 1.8, peakHeight: 5)
        let arrived = state(kind: .lob, flight: flight)
        scene.render(state: arrived, events: [.paddleContact(x: 10, side: .block, centered: true)], delta: 0)
        let ball = try #require(scene.childNode(withName: "//gameplayBall") as? SKSpriteNode)
        let projected = scene.courtProjection.screenPoint(for: flight.destination)
        #expect(abs(Double(ball.position.x) - projected.x) < 0.001)
        #expect(abs(Double(ball.position.y) - projected.y) < 0.001)
        let world = try #require(scene.children.first)
        let player = try #require(world.children.compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let sprite = try #require(player.children.first as? SKSpriteNode)
        let clip = try #require(player.art.clips["block"])
        let frame = clip.frames[try #require(clip.contactIndex)]
        let paddleY = player.position.y + sprite.position.y
            + (1 - frame.paddleCenter[1] / player.art.canvasSize[1] - sprite.anchorPoint.y) * sprite.size.height
        #expect(abs(Double(paddleY) - projected.y) < 0.001)
        var returned = state(kind: .normal)
        returned.simulationTime = 0.1
        scene.render(state: returned, events: [], delta: 0.1)
        for name in ["lobGroundShadow", "lobLandingCue", "shotRim", "shotTrail"] {
            #expect(try shape(scene, name).isHidden)
        }
        returned.phase = .ready
        returned.rallyShot = arrived.rallyShot
        scene.render(state: returned, events: [], delta: 0)
        #expect(try shape(scene, "lobGroundShadow").isHidden)
    }

    @Test("Pause freezes cues; reduced motion retains flight information; opponent changes clear effects")
    func lifecycleAndReducedMotion() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var power = state(kind: .power)
        power.boss?.specialPhase = .powerWindup
        power.simulationTime = 1
        scene.render(state: power, events: [], delta: 1)
        let cue = try shape(scene, "bossSpecialCue")
        let trail = try shape(scene, "shotTrail")
        let ball = try #require(scene.childNode(withName: "//gameplayBall") as? SKSpriteNode)
        let cueAlpha = cue.alpha
        let rotation = ball.zRotation
        let path = trail.path
        power.isPaused = true
        scene.render(state: power, events: [], delta: 200)
        #expect(cue.alpha == cueAlpha && ball.zRotation == rotation)
        #expect(trail.path == path)
        scene.reduceMotion = true
        scene.render(state: power, events: [], delta: 0)
        #expect(trail.isHidden)
        #expect(!(try shape(scene, "shotRim").isHidden))
        let flight = LobFlightState(origin: .init(x: 10, y: 39.7),
            destination: .init(x: 10, y: 2.5), duration: 1.8, elapsed: 0.9, peakHeight: 5)
        scene.render(state: state(kind: .lob, flight: flight), events: [], delta: 0)
        #expect(!(try shape(scene, "lobGroundShadow").isHidden))
        #expect(Double(ball.position.y) > scene.courtProjection.screenPoint(for: flight.groundPosition).y + 14)
        scene.render(state: GameState(), events: [], delta: 0)
        #expect(cue.isHidden && trail.isHidden)
        #expect(try shape(scene, "lobGroundShadow").isHidden)
    }

    @Test("Poacher direction comes from the actual committed side, and no special text covers contact")
    func honestCommitment() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var committed = state(kind: .normal)
        committed.mode = .bossRally(.poacher)
        committed.boss = BossState(id: .poacher, specialPhase: .poachCommitment, committedSide: .left)
        scene.render(state: committed, events: [.bossPoachCommitment(side: .left, targetX: 4)], delta: 0)
        let cue = try shape(scene, "bossSpecialCue")
        let leftPath = cue.path
        committed.playerX = 18
        scene.render(state: committed, events: [], delta: 0)
        #expect(cue.path == leftPath)
        committed.boss?.committedSide = .right
        scene.render(state: committed, events: [], delta: 0)
        #expect(cue.path != leftPath)
        #expect(!scene.children.compactMap { $0 as? SKLabelNode }.contains { $0.text == "POACH LEFT" })
    }

    @Test("New opponents have their own registered contact metadata rather than copied Wall centers",
          arguments: [BossID.dinker, .lobber])
    func ownContactMetadata(id: BossID) throws {
        let manifest = TextureLibrary().manifest
        let selected = try #require(manifest.characters[id.rawValue])
        let wall = try #require(manifest.characters["wall"])
        var different = false
        for name in ["forehand", "backhand", "block"] {
            let clip = try #require(selected.clips[name])
            let reference = try #require(wall.clips[name])
            let index = try #require(clip.contactIndex)
            let contact = clip.frames[index]
            #expect(contact.name.hasPrefix("boss_" + id.rawValue + "_"))
            #expect(contact.paddleCenter.count == 2 && contact.bounds.count == 4)
            #expect(contact.paddleCenter[0] > 0 && contact.paddleCenter[0] < selected.canvasSize[0])
            #expect(contact.paddleCenter[1] > 0 && contact.paddleCenter[1] < selected.canvasSize[1])
            if contact.paddleCenter != reference.frames[try #require(reference.contactIndex)].paddleCenter {
                different = true
            }
        }
        #expect(different)
    }

    @Test("Approved selection thumbnails retain only one frame image, without motion atlas cache",
          arguments: BossID.allCases)
    func thumbnailRelease(id: BossID) {
        let textures = TextureLibrary()
        let image = textures.opponentThumbnail(id.rawValue)
        #expect(image.width == 128)
        #expect(image.height == 128)
        #expect(!textures.debugCachedTextureKeys.contains { $0.hasPrefix("Boss" + id.rawValue.capitalized + "/") })
        #expect(textures.debugLoadedAtlasCount == 0)
    }
}
