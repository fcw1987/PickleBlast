import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Approved Boss Rally presentation")
@MainActor
struct BossArtTests {
    private func bossNode(in scene: PickleBlastScene) throws -> CharacterNode {
        let world = try #require(scene.children.first)
        return try #require(world.children.compactMap { $0 as? CharacterNode }.first { $0.identity != "player" })
    }

    private func paddlePoint(in boss: CharacterNode) throws -> Vector2 {
        let sprite = try #require(boss.children.first as? SKSpriteNode)
        let clip = try #require(boss.art.clips[boss.motion.clip])
        let frame = clip.frames[try #require(clip.contactIndex)]
        let localX = (frame.paddleCenter[0] / boss.art.canvasSize[0] - sprite.anchorPoint.x) * sprite.size.width
        let localY = (1 - frame.paddleCenter[1] / boss.art.canvasSize[1] - sprite.anchorPoint.y) * sprite.size.height
        return Vector2(x: boss.position.x + sprite.position.x + localX,
                       y: boss.position.y + sprite.position.y + localY)
    }

    @Test("Each selected opponent uses its own complete approved frames and projected contact", arguments: BossID.allCases)
    func selectedOpponentContact(id: BossID) throws {
        let textures = TextureLibrary()
        let tuning = GameTuning()
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197), tuning: tuning,
                                     textureLibrary: textures)
        let configuration = tuning.bossConfiguration(for: id)
        var state = GameState()
        state.mode = .bossRally(id)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: id, x: CourtGeometry.centerX)

        let art = try #require(textures.manifest.characters[id.rawValue])
        #expect(art.atlas == "Boss\(id.rawValue.capitalized)")
        #expect(art.clips.values.reduce(0) { $0 + $1.frames.count } == 271)
        #expect(art.anchor == [0.5, 0.12109375])
        for (offset, expectedClip) in [(-1.0, "forehand"), (0.0, "block"), (1.0, "backhand")] {
            let x = CourtGeometry.centerX + offset
            let logicalBall = Vector2(x: x, y: configuration.y - tuning.ballRadius)
            state.ball = BallState(position: logicalBall, velocity: Vector2(x: 0, y: -20))
            scene.render(state: state, events: [.bossContact(x: x)], delta: 0)
            let boss = try bossNode(in: scene)
            #expect(boss.identity == id.rawValue)
            #expect(boss.motion.clip == expectedClip)
            #expect(boss.children.count == 1, "Approved complete frame includes the connected paddle")
            #expect(boss.physicsBody == nil)
            let sprite = try #require(boss.children.first as? SKSpriteNode)
            if id == .dinker || id == .lobber {
                let frames = art.clips.values.flatMap(\.frames)
                let top = try #require(frames.map { $0.bounds[1] }.min())
                let bottom = try #require(frames.map { $0.bounds[3] }.max())
                let visibleHeight = Double(sprite.size.height) * (bottom - top) / art.canvasSize[1]
                #expect(abs(visibleHeight - 33.0 * sqrt(162.0 / 211.0)) < 0.001,
                        "New complete art retains the accepted visible boss height, including its hat")
            } else {
                let expectedBossCanvasHeight = 33.0 * sqrt(162.0 / 211.0) / (74.0 / 128.0)
                #expect(abs(Double(sprite.size.height) - expectedBossCanvasHeight) < 0.001,
                        "Existing opponents retain the accepted boss billboard canvas")
            }
            let selectedClip = try #require(boss.art.clips[expectedClip])
            let contactFrame = selectedClip.frames[try #require(selectedClip.contactIndex)]
            #expect(sprite.texture === textures.texture(atlas: art.atlas, name: contactFrame.name),
                    "The complete approved contact frame is the only rendered character sprite")
            let attachment = try paddlePoint(in: boss)
            let projectedBall = scene.courtProjection.screenPoint(for: logicalBall)
            #expect(abs(attachment.x - projectedBall.x) < 0.0001)
            #expect(abs(attachment.y - projectedBall.y) < 0.0001)
        }
        let otherAtlases = BossID.allCases.filter { $0 != id }.map { "Boss\($0.rawValue.capitalized)/" }
        #expect(textures.debugCachedTextureKeys.contains { $0.hasPrefix(art.atlas + "/") })
        #expect(!textures.debugCachedTextureKeys.contains { key in otherAtlases.contains { key.hasPrefix($0) } })
    }

    @Test("Switching or resetting a scene releases only its previous opponent textures")
    func selectedAtlasRelease() {
        let textures = TextureLibrary()
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197), textureLibrary: textures)
        var state = GameState()
        state.mode = .bossRally(.banger)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .banger)
        scene.render(state: state, events: [], delta: 0)
        #expect(textures.debugCachedTextureKeys.contains { $0.hasPrefix("BossBanger/") })
        #expect(!textures.debugCachedTextureKeys.contains { $0.hasPrefix("BossWall/") })

        state.mode = .bossRally(.poacher)
        state.boss = BossState(id: .poacher)
        state.simulationTime = 0.1
        scene.render(state: state, events: [], delta: 0.1)
        #expect(!textures.debugCachedTextureKeys.contains { $0.hasPrefix("BossBanger/") })
        #expect(textures.debugCachedTextureKeys.contains { $0.hasPrefix("BossPoacher/") })

        scene.render(state: GameState(), events: [], delta: 0)
        #expect(!textures.debugCachedTextureKeys.contains { $0.hasPrefix("BossPoacher/") })
        #expect(textures.debugCachedTextureKeys.contains { $0.hasPrefix("Player/") })
    }

    @Test("Boss special cue stays bounded around the projected opponent on both Watch widths",
          arguments: [162.0, 211.0])
    func specialCueBounds(width: Double) throws {
        let height = width == 162 ? 197.0 : 257.0
        let tuning = GameTuning()
        let scene = PickleBlastScene(size: CGSize(width: width, height: height), tuning: tuning)
        let world = try #require(scene.children.first)
        let cue = try #require(world.children.first { $0.name == "bossSpecialCue" } as? SKShapeNode)
        let cases: [(BossID, BossSpecialPhase)] = [(.banger, .powerWindup), (.poacher, .poachCommitment)]
        for (id, special) in cases {
            var state = GameState()
            state.mode = .bossRally(id)
            state.stage = .boss
            state.phase = .playing
            state.boss = BossState(id: id, x: 14, specialPhase: special)
            scene.render(state: state, events: [], delta: 0)

            let projected = scene.courtProjection.screenPoint(for: Vector2(
                x: 14, y: tuning.bossConfiguration(for: id).y - tuning.ballRadius))
            let scale = sqrt(width / 211)
            #expect(!cue.isHidden)
            #expect(abs(Double(cue.position.x) - projected.x) < 0.001)
            #expect(abs(Double(cue.position.y) - projected.y) < 0.001)
            #expect(abs(Double(cue.xScale) - scale / Double(CrispVector.resolution)) < 0.0001)
            #expect(Double(cue.frame.width) > 24 * scale)
            #expect(Double(cue.frame.width) < 36 * scale)
            #expect(Double(cue.frame.height) > 24 * scale)
            #expect(Double(cue.frame.height) < 36 * scale)
            #expect(abs(Double(cue.frame.midX) - projected.x) < 2)
            #expect(abs(Double(cue.frame.midY) - projected.y) < 2)
        }
    }

    @Test("Missing optional boss metadata or atlas resolves to approved Wall")
    func optionalArtFallback() throws {
        let manifest = TextureLibrary().manifest
        let missingMetadata = RuntimeArtManifest(schemaVersion: manifest.schemaVersion,
            characters: manifest.characters.filter { $0.key != "banger" },
            supporting: manifest.supporting)
        let emptyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickleBlastMissingOptionalBoss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let withoutMetadata = TextureLibrary(testManifest: missingMetadata, resourceDirectory: emptyDirectory)
        #expect(withoutMetadata.resolvedCharacterName("banger") == "wall")
        let withoutAtlas = TextureLibrary(testManifest: manifest, resourceDirectory: emptyDirectory)
        #expect(withoutAtlas.resolvedCharacterName("poacher") == "wall")
    }
}
