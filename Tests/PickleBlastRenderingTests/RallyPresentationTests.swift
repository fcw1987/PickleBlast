import Testing
import SpriteKit
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Boss Rally score presentation")
@MainActor
struct RallyPresentationTests {
    @Test("The safe HUD shows match points and quiet progress/save icons without growing counters",
          arguments: [(162.0, 197.0), (211.0, 257.0)])
    func rallyHUD(size: (Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        var state = GameState()
        state.mode = .bossRally(.banger)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .banger)
        state.boss?.points = 1
        state.boss?.opponentPoints = 2
        state.consecutivePlayerReturns = 7
        state.recoveriesRemaining = 1
        state.score = 1_500
        scene.render(state: state, events: [], delta: 0)

        let playerScore = try #require(scene.childNode(withName: "//hudPlayerScore") as? SKLabelNode)
        let opponentScore = try #require(scene.childNode(withName: "//hudOpponentScore") as? SKLabelNode)
        let rally = try #require(scene.childNode(withName: "//comboIndicator") as? SKLabelNode)
        let progress = try #require(scene.childNode(withName: "//hudRallyProgress") as? SKShapeNode)
        let save = try #require(scene.childNode(withName: "//hudRallySave") as? SKShapeNode)
        let savePlus = try #require(scene.childNode(withName: "//hudRallySavePlus") as? SKShapeNode)
        let hud = try #require(scene.children.first { $0.zPosition == 20 })
        let hearts = hud.children.compactMap { $0 as? SKSpriteNode }
        #expect(playerScore.text == "1")
        #expect(opponentScore.text == "2")
        #expect(!opponentScore.isHidden)
        #expect(rally.isHidden)
        #expect(progress.isHidden && !save.isHidden && !savePlus.isHidden)
        #expect(scene.childNode(withName: "//hudRallySaves") == nil)
        #expect(hearts.count == 3 && hearts.allSatisfy(\.isHidden))
        #expect(playerScore.frame.maxX < CGFloat(size.0) / 2 - 14,
                "Left points stay clear of the centered Pause control")
        #expect(opponentScore.frame.minX > CGFloat(size.0) / 2 + 14,
                "Right points stay clear of the centered Pause control")

        let nodeCount = scene.children.reduce(0) { $0 + 1 + $1.children.count }
        for value in 8...48 {
            state.consecutivePlayerReturns = value
            state.simulationTime += 1.0 / 30.0
            scene.render(state: state, events: [], delta: 1.0 / 30.0)
        }
        #expect(rally.isHidden && progress.isHidden && !save.isHidden)
        #expect(scene.children.reduce(0) { $0 + 1 + $1.children.count } == nodeCount,
                "Rally updates reuse the existing HUD nodes")
    }

    @Test("One Rally HUD row clears safe chrome, Pause and every approved boss pose",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func rallyHUDClearsBossAtLegalExtremes(size: (Double, Double, Double, Double)) throws {
        let viewport = CGSize(width: size.0, height: size.1)
        let scene = PickleBlastScene(size: viewport)
        scene.setViewport(viewport, safeTop: size.2, safeBottom: size.3)
        let center = CGFloat(size.0 / 2)
        for id in BossID.allCases {
            var state = GameState()
            state.mode = .bossRally(id)
            state.stage = .boss
            state.phase = .playing
            state.consecutivePlayerReturns = 137
            state.boss = BossState(id: id)
            let tuning = GameTuning()
            let margin = tuning.bossConfiguration(for: id).halfWidth
            for x in [margin, CourtGeometry.centerX, CourtGeometry.width - margin] {
                state.boss?.x = x
                scene.render(state: state, events: [], delta: 0)
                let points = try #require(scene.childNode(withName: "//hudPlayerScore") as? SKLabelNode)
                let bossPoints = try #require(scene.childNode(withName: "//hudOpponentScore") as? SKLabelNode)
                let progress = try #require(scene.childNode(withName: "//hudRallyProgress") as? SKShapeNode)
                let save = try #require(scene.childNode(withName: "//hudRallySave") as? SKShapeNode)
                let world = try #require(scene.children.first)
                let character = try #require(world.children.compactMap { $0 as? CharacterNode }
                    .first { $0.identity == id.rawValue })
                let sprite = try #require(character.children.compactMap { $0 as? SKSpriteNode }.first)
                let art = character.art
                let forehand = try #require(art.clips["forehand"])
                let referenceY = try #require(forehand.contactIndex.map { forehand.frames[$0].paddleCenter[1] })
                let highestPose = art.clips.values.flatMap(\.frames).map { frame in
                    max(referenceY, frame.paddleCenter[1]) - frame.bounds[1]
                }.max() ?? 0
                let groundY = scene.courtProjection.screenPoint(for: Vector2(
                    x: x, y: tuning.bossConfiguration(for: id).y - tuning.ballRadius)).y
                let highestVisibleY = groundY + highestPose / art.canvasSize[1] * Double(sprite.size.height)
                for label in [points, bossPoints, progress, save] as [SKNode] {
                    #expect(label.frame.maxY <= CGFloat(size.1 - size.2) + 0.5)
                    #expect(label.frame.minY > CGFloat(highestVisibleY + 1))
                }
                #expect(progress.frame.minX > points.frame.maxX + 1)
                #expect(bossPoints.frame.minX > save.frame.maxX + 1)
                #expect(points.frame.maxX < center - 22)
                #expect(progress.frame.maxX < center - 22)
                #expect(save.frame.maxX < center - 22)
                #expect(bossPoints.frame.minX > center + 22)
                #expect(points.frame.minX >= 6.5)
                #expect(bossPoints.frame.maxX <= CGFloat(size.0) - 6.5)
            }
        }
    }

    @Test("Points get brief feedback and switching back to Arcade restores its original HUD")
    func pointFeedbackAndArcadeIsolation() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.mode = .bossRally(.wall)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .wall)
        state.boss?.points = 1
        state.simulationTime = 0.1
        scene.render(state: state, events: [.bossPoint(points: 1)], delta: 0.1)
        #expect(scene.children.compactMap { $0 as? SKLabelNode }.contains { $0.text == "YOUR POINT" })

        state.boss?.opponentPoints = 1
        state.simulationTime += 0.1
        scene.render(state: state, events: [.opponentPoint(points: 1)], delta: 0.1)
        #expect(scene.children.compactMap { $0 as? SKLabelNode }.contains { $0.text == "BOSS POINT" })

        state = GameState()
        state.phase = .playing
        state.score = 450
        state.lives = 2
        scene.render(state: state, events: [], delta: 0)
        let playerScore = try #require(scene.childNode(withName: "//hudPlayerScore") as? SKLabelNode)
        let opponentScore = try #require(scene.childNode(withName: "//hudOpponentScore") as? SKLabelNode)
        let hud = try #require(scene.children.first { $0.zPosition == 20 })
        let hearts = hud.children.compactMap { $0 as? SKSpriteNode }
        #expect(playerScore.text == "450")
        #expect(opponentScore.isHidden)
        #expect(hearts.count == 3 && hearts.allSatisfy { !$0.isHidden })
    }

    @Test("Rally shot intent tints one reused boss-contact ring while Arcade keeps its original effect")
    func contactPurposeAccent() throws {
        let cases: [(RallyShotPurpose, SKColor)] = [
            (.control, Neon.magenta), (.placement, Neon.cyan),
            (.changeOfPace, Neon.lime), (.attack, Neon.orange)
        ]
        for (purpose, expectedColor) in cases {
            let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
            let world = try #require(scene.children.first)
            let allocated = world.children.count
            var state = GameState()
            state.mode = .bossRally(.wall)
            state.stage = .boss
            state.phase = .playing
            state.boss = BossState(id: .wall, lastShotPurpose: purpose)
            state.ball = BallState(position: .init(x: 10, y: 40.4),
                                   velocity: .init(x: 0, y: -26))
            scene.render(state: state, events: [.bossContact(x: 10)], delta: 0)
            let rings = world.children.compactMap { $0 as? SKSpriteNode }
                .filter { $0.zPosition == 6 && !$0.isHidden }
            let ring = try #require(rings.first)
            #expect(rings.count == 1)
            // SpriteKit normalizes the assigned color to device RGB on macOS;
            // object equality also compares color-space identity.
            let actualComponents = try #require(ring.color.cgColor.components)
            let expectedComponents = try #require(expectedColor.cgColor.components)
            #expect(actualComponents.count == expectedComponents.count)
            for (actual, expected) in zip(actualComponents, expectedComponents) {
                #expect(abs(actual - expected) < 1e-5)
            }
            #expect(abs(ring.colorBlendFactor - 0.55) < 1e-6)
            #expect(world.children.count == allocated)
        }

        let arcade = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .wall)
        arcade.render(state: state, events: [.bossContact(x: 10)], delta: 0)
        let world = try #require(arcade.children.first)
        let ring = try #require(world.children.compactMap { $0 as? SKSpriteNode }
            .first { $0.zPosition == 6 && !$0.isHidden })
        #expect(ring.colorBlendFactor == 0)
    }
}
