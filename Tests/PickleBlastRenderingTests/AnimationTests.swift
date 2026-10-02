import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Approved animation contract and presentation timing")
@MainActor
struct AnimationTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func manifest() throws -> RuntimeArtManifest {
        try JSONDecoder().decode(RuntimeArtManifest.self,
                                 from: Data(contentsOf: root.appendingPathComponent("WatchApp/Art/runtime_manifest.json")))
    }

    private func playerArt() throws -> CharacterArt {
        try #require(manifest().characters["player"])
    }

    private func near(_ actual: Double, _ expected: Double, tolerance: Double = 0.000001) {
        #expect(abs(actual - expected) <= tolerance)
    }

    @Test("Runtime clips preserve source filenames, timestamps, contacts, anchors and attachment metadata")
    func sourceContract() throws {
        let runtime = try manifest()
        #expect(runtime.schemaVersion == 1)
        #expect(Set(runtime.characters.keys) == Set(["player", "wall", "banger", "poacher", "dinker", "lobber"]))
        // Canonical original metadata is tracked independently of the optional
        // private master pack, so this source/runtime regression runs in a ZIP.
        let docs = root.appendingPathComponent("scripts/fixtures/art_import/Docs")
        let decoder = JSONDecoder()
        let sourcePlayer = try decoder.decode(SourceManifest.self,
            from: Data(contentsOf: docs.appendingPathComponent("player_animation_manifest.json")))
        let sourceBoss = try decoder.decode(SourceManifest.self,
            from: Data(contentsOf: docs.appendingPathComponent("boss_animation_manifest.json")))
        let sources = ["player": try #require(sourcePlayer.animations),
                       "wall": try #require(sourceBoss.bosses?["wall"]?.animations)]
        for identity in ["player", "wall"] {
            let art = try #require(runtime.characters[identity])
            let original = try #require(sources[identity])
            #expect(art.atlas == (identity == "player" ? "Player" : "BossWall"))
            #expect(art.canvasSize == [512, 512])
            #expect(art.anchor == [0.5, 0.12109375])
            #expect(Set(art.clips.keys) == Set(original.keys))
            #expect(Set(art.clips.keys) == Set(["idle", "move_left", "move_right", "forehand", "backhand", "block"]))
            for (name, clip) in art.clips {
                let source = try #require(original[name])
                let metadataName = identity == "player" ? "player_\(name)_frames.json" : "boss_\(name).json"
                let metadata = try decoder.decode([SourceFrame].self,
                    from: Data(contentsOf: docs.appendingPathComponent(metadataName)))
                #expect(clip.duration == source.duration_seconds)
                #expect(clip.loop == source.loop)
                #expect(clip.contactIndex == source.contact_index_zero_based)
                #expect(clip.frames.count == source.files.count)
                #expect(clip.frames.count == source.timestamps_seconds.count)
                #expect(clip.frames.count == metadata.count)
                if name.hasPrefix("move_") { #expect(abs(try #require(clip.strideSourcePixels)) == 26) }
                for index in clip.frames.indices {
                    let frame = clip.frames[index]
                    #expect(frame.name + ".png" == source.files[index])
                    #expect(frame.timestamp == source.timestamps_seconds[index])
                    #expect(metadata[index].filename == source.files[index])
                    #expect(metadata[index].index == index)
                    #expect(metadata[index].clip == name)
                    if identity == "wall" { #expect(metadata[index].character == "wall") }
                    #expect(frame.paddleCenter == metadata[index].paddle_center_px)
                    #expect(frame.wrist == metadata[index].wrist_px)
                    #expect(frame.bounds == metadata[index].bounds512)
                    let path = root.appendingPathComponent("WatchApp/Art/\(art.atlas).atlas/\(frame.name).png").path
                    #expect(FileManager.default.fileExists(atPath: path), "Missing approved runtime frame: \(path)")
                }
            }
        }
        let wall = try #require(runtime.characters["wall"])
        for identity in ["banger", "poacher"] {
            let art = try #require(runtime.characters[identity])
            let original = try #require(sourceBoss.bosses?[identity]?.animations)
            #expect(art.atlas == "Boss\(identity.capitalized)")
            #expect(art.canvasSize == wall.canvasSize)
            #expect(art.anchor == wall.anchor)
            #expect(Set(art.clips.keys) == Set(original.keys))
            #expect(Set(art.clips.keys) == Set(["idle", "move_left", "move_right", "forehand", "backhand", "block"]))
            for (name, clip) in art.clips {
                let source = try #require(original[name])
                #expect(clip.duration == source.duration_seconds)
                #expect(clip.loop == source.loop)
                #expect(clip.contactIndex == source.contact_index_zero_based)
                #expect(clip.frames.count == source.files.count)
                #expect(clip.frames.count == source.timestamps_seconds.count)
                if name.hasPrefix("move_") { #expect(abs(try #require(clip.strideSourcePixels)) == 26) }
                for index in clip.frames.indices {
                    let frame = clip.frames[index]
                    #expect(frame.name + ".png" == source.files[index])
                    #expect(frame.timestamp == source.timestamps_seconds[index])
                    let path = root.appendingPathComponent("WatchApp/Art/\(art.atlas).atlas/\(frame.name).png").path
                    #expect(FileManager.default.fileExists(atPath: path), "Missing approved runtime frame: \(path)")
                }
            }
            // These contact attachments come from each approved boss's paddle pixels.
            // Reusing Wall's metadata would leave the connected paddle visibly detached.
            for name in ["forehand", "backhand", "block"] {
                let clip = try #require(art.clips[name])
                let wallClip = try #require(wall.clips[name])
                let index = try #require(clip.contactIndex)
                #expect(index == wallClip.contactIndex)
                let frame = clip.frames[index]
                let wallFrame = wallClip.frames[index]
                let dx = frame.paddleCenter[0] - wallFrame.paddleCenter[0]
                let dy = frame.paddleCenter[1] - wallFrame.paddleCenter[1]
                let displacement = hypot(dx, dy)
                #expect(displacement > 4 && displacement < 24)
                #expect(frame.bounds != wallFrame.bounds)
            }
        }
    }

    @Test("Every actual timestamp selects its frame and contacts use zero-based source indices")
    func timestampSelection() throws {
        for art in try manifest().characters.values {
            for clip in art.clips.values {
                #expect(clip.frameIndex(at: -10) == 0)
                for index in clip.frames.indices {
                    let timestamp = clip.frames[index].timestamp
                    #expect(clip.frameIndex(at: timestamp) == index)
                    if index > 0 {
                        #expect(clip.frameIndex(at: timestamp - 0.000001) == index - 1)
                    }
                    if index + 1 < clip.frames.count {
                        let next = clip.frames[index + 1].timestamp
                        #expect(clip.frameIndex(at: (timestamp + next) / 2) == index)
                    }
                }
                if let contactIndex = clip.contactIndex {
                    #expect(clip.frameIndex(at: try #require(clip.contactTime)) == contactIndex)
                    #expect(clip.frames[contactIndex].name.hasSuffix(String(format: "_%03d", contactIndex + 1)))
                }
                if clip.loop {
                    #expect(clip.frameIndex(at: clip.duration) == 0)
                    let probe = clip.frames[5].timestamp + 0.000001
                    #expect(clip.frameIndex(at: clip.duration * 4 + probe) == 5)
                } else {
                    #expect(clip.frameIndex(at: clip.duration) == clip.frames.count - 1)
                    #expect(clip.frameIndex(at: clip.duration + 1_000) == clip.frames.count - 1)
                }
            }
        }
        let art = try playerArt()
        #expect(art.clips["forehand"]?.duration == 0.64)
        #expect(art.clips["backhand"]?.duration == 0.68)
        #expect(art.clips["block"]?.duration == 0.45)
    }

    @Test("Shuffle phase depends on actual travel and is independent of input event partitioning")
    func travelDrivenShuffle() throws {
        let art = try playerArt()
        let right = try #require(art.clips["move_right"])
        let stride = abs(try #require(right.strideSourcePixels)) * CharacterNode.canvasWidth / art.canvasSize[0]
        var single = MotionPlayback()
        var divided = MotionPlayback()
        single.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        divided.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        single.advance(x: 10 + stride * 0.57, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        for fraction in [0.13, 0.31, 0.57] {
            divided.advance(x: 10 + stride * fraction, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        }
        #expect(single.clip == "move_right" && divided.clip == "move_right")
        near(single.elapsed, divided.elapsed)
        near(single.elapsed, right.duration * 0.57)
        near(single.distance, stride * 0.57)
        let traveled = single.distance
        single.advance(x: 10 + stride * 0.57, delta: 0.5, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        #expect(single.clip == "idle")
        near(single.distance, traveled)
        single.advance(x: 10 + stride * 0.47, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        #expect(single.clip == "move_left")
        near(single.distance, stride * 0.67)
    }

    @Test("Shuffle holds between input events, then settles only after active time without travel")
    func shuffleSettlesBetweenInputs() throws {
        let art = try playerArt()
        var motion = MotionPlayback()
        motion.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        motion.advance(x: 10.1, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        let firstPhase = motion.elapsed
        for _ in 0..<3 {
            motion.advance(x: 10.1, delta: 0.03, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
            #expect(motion.clip == "move_right")
            near(motion.elapsed, firstPhase)
        }
        // Another Crown event continues travel instead of restarting the clip.
        motion.advance(x: 10.2, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        #expect(motion.clip == "move_right")
        #expect(motion.elapsed > firstPhase)
        let continuedPhase = motion.elapsed
        motion.advance(x: 10.2, delta: 3_600, frozen: true, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        for _ in 0..<3 {
            motion.advance(x: 10.2, delta: 0.03, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
            #expect(motion.clip == "move_right")
            near(motion.elapsed, continuedPhase)
        }
        motion.advance(x: 10.2, delta: 0.02, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        #expect(motion.clip == "idle")
        near(motion.distance, 0.2)
    }

    @Test("Prediction follows time to arrival without confirming a hit or restarting on lateral input")
    func continuousPrediction() throws {
        let art = try playerArt()
        let contact = try #require(art.clips["forehand"]?.contactTime)
        var motion = MotionPlayback()
        motion.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth,
                       prediction: ("forehand", 0.2, 1))
        near(motion.elapsed, contact - 0.2)
        motion.advance(x: 10.25, delta: 0.05, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth,
                       prediction: ("forehand", 0.15, 0.75))
        near(motion.elapsed, contact - 0.15)
        near(motion.contactOffset, 0.75)
        #expect(!motion.confirmed && motion.contactCount == 0)
        #expect(motion.elapsed < contact)
    }

    @Test("Canceled anticipation returns through approved frames without producing a contact")
    func canceledPrediction() throws {
        let art = try playerArt()
        var motion = MotionPlayback()
        motion.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth,
                       prediction: ("forehand", 0.15, 1))
        for _ in 0..<90 {
            motion.advance(x: 10, delta: 1.0 / 120, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
            #expect(!motion.confirmed && motion.contactCount == 0)
        }
        #expect(motion.clip == "idle")
        near(motion.registrationWeight(art: art), 0)
    }

    @Test("Actual contact overrides a prediction and consecutive contacts restart at each approved contact frame")
    func actualAndConsecutiveContacts() throws {
        let art = try playerArt()
        var motion = MotionPlayback()
        motion.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth,
                       prediction: ("forehand", 0.1, 1))
        for (index, name) in ["backhand", "forehand", "block"].enumerated() {
            let clip = try #require(art.clips[name])
            motion.contact(clip: name, offset: Double(index) - 1, art: art)
            #expect(motion.clip == name && motion.confirmed)
            #expect(motion.contactCount == index + 1)
            #expect(clip.frameIndex(at: motion.elapsed) == clip.contactIndex)
            near(motion.registrationWeight(art: art), 1)
            motion.advance(x: 10, delta: 0.01, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth,
                           prediction: ("forehand", 0.1, 1))
            #expect(motion.clip == name && motion.contactCount == index + 1)
            near(motion.elapsed, try #require(clip.contactTime) + 0.01)
        }
        motion.advance(x: 10, delta: 1, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        #expect(motion.clip == "idle" && !motion.confirmed && motion.contactCount == 3)
    }

    @Test("Frozen playback preserves contact time and rebases displacement before resuming")
    func frozenPlayback() throws {
        let art = try playerArt()
        var motion = MotionPlayback()
        motion.advance(x: 10, delta: 0, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        motion.contact(clip: "backhand", offset: -1, art: art)
        let elapsed = motion.elapsed
        motion.advance(x: 12, delta: 3_600, frozen: true, art: art, spriteWidth: CharacterNode.canvasWidth,
                       prediction: ("forehand", 0, 1))
        near(motion.elapsed, elapsed)
        near(motion.distance, 0)
        near(motion.contactOffset, -1)
        #expect(motion.clip == "backhand" && motion.confirmed && motion.contactCount == 1)
        motion.advance(x: 12.1, delta: 0.01, frozen: false, art: art, spriteWidth: CharacterNode.canvasWidth, prediction: nil)
        near(motion.distance, 0.1)
        near(motion.elapsed, elapsed + 0.01)
    }

    @Test("Both complete character sprites use the approved anchor and place their single paddle on contact")
    func attachmentRegistration() throws {
        let textures = TextureLibrary()
        for front in [false, true] {
            let node = CharacterNode(frontFacing: front, textures: textures)
            let art = node.art
            #expect(node.children.count == 1)
            let sprite = try #require(node.children.first as? SKSpriteNode)
            near(sprite.anchorPoint.x, art.anchor[0])
            near(sprite.anchorPoint.y, art.anchor[1])
            let plane = front ? 41.7 : 2.5
            node.advance(x: 10, planeY: plane, delta: 0, frozen: false, prediction: nil)
            for (name, offset) in [("forehand", 1.2), ("backhand", -1.2), ("block", 0.0)] {
                let clip = try #require(art.clips[name])
                let frame = clip.frames[try #require(clip.contactIndex)]
                node.contact(clip: name, offset: offset, lift: 0.15)
                let localX = (frame.paddleCenter[0] / art.canvasSize[0] - art.anchor[0]) * sprite.size.width
                let localY = (1 - frame.paddleCenter[1] / art.canvasSize[1] - art.anchor[1]) * sprite.size.height
                near(node.position.x + sprite.position.x + localX, 10 + offset)
                near(node.position.y + sprite.position.y + localY, plane + 0.15)
                #expect(sprite.texture?.size() == CGSize(width: 128, height: 128))
                #expect(sprite.texture?.filteringMode == .linear)
            }
        }
    }

    @Test("Scene contact is consumed once, pauses through countdown, and resets presentation on replay")
    func sceneContactPauseAndReplay() throws {
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257))
        let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        var state = GameState()
        state.phase = .playing
        state.ball = BallState(position: .init(x: 11, y: 3), velocity: .init(x: 0, y: 26))
        scene.render(state: state, events: [], delta: 0)
        state.simulationTime = 0.1
        scene.render(state: state, events: [.paddleContact(x: 11, side: .forehand, centered: false)], delta: 0.1)
        #expect(player.motion.confirmed && player.motion.contactCount == 1)
        let contactElapsed = player.motion.elapsed
        state.isPaused = true
        state.simulationTime += 3_600
        scene.render(state: state, events: [], delta: 3_600)
        near(player.motion.elapsed, contactElapsed)
        state.isPaused = false
        state.resumeCountdown = 0.5
        state.simulationTime += 0.5
        scene.render(state: state, events: [], delta: 0.5)
        near(player.motion.elapsed, contactElapsed)
        #expect(player.motion.contactCount == 1)
        state.resumeCountdown = 0
        state.simulationTime += 1.0 / 120
        scene.render(state: state, events: [], delta: 1.0 / 120)
        near(player.motion.elapsed, contactElapsed + 1.0 / 120)
        scene.render(state: GameState(), events: [], delta: 0)
        #expect(player.motion.clip == "idle" && player.motion.contactCount == 0)
        #expect(!player.motion.confirmed)
        near(player.motion.elapsed, 0)
        near(player.motion.distance, 0)
    }

    @Test("Court pulse, clear effect and transient message survive pause and resume countdown")
    func sceneEffectsUseFrozenVisualTime() throws {
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257))
        let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let world = try #require(player.parent)
        let court = try #require(world.children.first { $0.children.filter { $0 is SKShapeNode }.count == 3 })
        let clear = try #require(scene.children.compactMap { $0 as? SKSpriteNode }.first)
        let labels = scene.children.compactMap { $0 as? SKLabelNode }
        var state = GameState()
        state.phase = .impact
        scene.render(state: state, events: [.waveCleared(number: 1)], delta: 0)
        let pulseAlpha = court.alpha
        let clearTexture = try #require(clear.texture)
        #expect(!clear.isHidden)
        #expect(labels.contains { $0.text == "WAVE CLEAR" })

        state.isPaused = true
        state.simulationTime += 3_600
        scene.render(state: state, events: [], delta: 3_600)
        near(court.alpha, pulseAlpha)
        #expect(!clear.isHidden && clear.texture === clearTexture)
        state.isPaused = false
        state.resumeCountdown = 0.5
        state.simulationTime += 0.5
        scene.render(state: state, events: [], delta: 0.5)
        near(court.alpha, pulseAlpha)
        #expect(!clear.isHidden && clear.texture === clearTexture)
        #expect(labels.contains { $0.text == "READY" })

        state.resumeCountdown = 0
        scene.render(state: state, events: [], delta: 0)
        #expect(labels.contains { $0.text == "WAVE CLEAR" })
        state.simulationTime += 0.9
        scene.render(state: state, events: [], delta: 0.9)
        near(court.alpha, 1)
        #expect(clear.isHidden)
        #expect(!labels.contains { $0.text == "WAVE CLEAR" })
    }

    @Test("Player anticipation uses the same centered-contact threshold as authoritative returns", arguments: [-1.0, 1.0])
    func predictionMatchesCenteredContact(side: Double) throws {
        var tuning = GameTuning()
        tuning.centeredContactFraction = 0.35
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257), tuning: tuning)
        let player = try #require(scene.children.flatMap(\.children).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        var state = GameState()
        state.phase = .playing
        let offset = side * tuning.playerHalfWidth * tuning.centeredContactFraction * 0.95
        state.ball = BallState(position: .init(x: state.playerX + offset,
                                              y: tuning.playerY + tuning.ballRadius + 2.6),
                               velocity: .init(x: 0, y: -26), radius: tuning.ballRadius)
        scene.render(state: state, events: [], delta: 0)
        #expect(player.motion.clip == "block")
        #expect(!player.motion.confirmed && player.motion.contactCount == 0)
    }
}

private struct SourceManifest: Decodable {
    let animations: [String: SourceClip]?
    let bosses: [String: SourceBoss]?
}
private struct SourceBoss: Decodable { let animations: [String: SourceClip] }
private struct SourceClip: Decodable {
    let files: [String]
    let duration_seconds: Double
    let loop: Bool
    let timestamps_seconds: [Double]
    let contact_index_zero_based: Int?
}
private struct SourceFrame: Decodable {
    let character: String?
    let clip: String
    let filename: String
    let index: Int
    let paddle_center_px: [Double]
    let wrist_px: [Double]
    let bounds512: [Double]
}
