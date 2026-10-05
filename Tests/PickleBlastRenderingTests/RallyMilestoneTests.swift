import Testing
import SpriteKit
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Earned Rally HUD and milestone feedback")
@MainActor
struct RallyMilestoneTests {
    private func playing(returns: Int = 19) -> GameState {
        var state = GameState()
        state.mode = .bossRally(.lobber)
        state.phase = .playing
        state.stage = .boss
        state.boss = BossState(id: .lobber)
        state.consecutivePlayerReturns = returns
        state.recoveriesRemaining = 0
        state.simulationTime = 1
        state.ball = BallState(position: .init(x: 10, y: 15), velocity: .init(x: 2, y: 25))
        return state
    }

    @Test("A brief earned-save celebration replaces counters and always returns to the match score",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func milestoneGeometryAndDeadline(size: (Double, Double, Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        scene.setViewport(scene.size, safeTop: size.2, safeBottom: size.3)
        var state = playing()
        scene.render(state: state, events: [], delta: 0)
        let banner = try #require(scene.childNode(withName: "//rallyMilestone"))
        let count = try #require(scene.childNode(withName: "//rallyMilestoneCount") as? SKLabelNode)
        let caption = try #require(scene.childNode(withName: "//rallyMilestoneCaption") as? SKLabelNode)
        let playerScore = try #require(scene.childNode(withName: "//hudPlayerScore"))
        let bossScore = try #require(scene.childNode(withName: "//hudOpponentScore"))
        let ball = try #require(scene.childNode(withName: "//gameplayBall") as? SKSpriteNode)
        let ballBefore = ball.frame
        #expect(banner.isHidden && !playerScore.isHidden && !bossScore.isHidden)
        state.consecutivePlayerReturns = 20
        state.recoveriesRemaining = 1
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        #expect(!banner.isHidden && count.text == "20!" && caption.text == "SAVE READY")
        #expect(playerScore.isHidden && bossScore.isHidden)
        #expect(ball.frame == ballBefore, "The milestone cannot move or resize the ball")
        // Inspect the largest overshoot and the complete settled interval.
        for age in [0.10, 0.22, 0.60, 1.08, 1.15] {
            state.simulationTime = 1 + age
            scene.render(state: state, events: [], delta: 0.1)
            #expect(!banner.isHidden)
            #expect(count.frame.maxX < size.0 / 2 - 14)
            #expect(caption.frame.minX > size.0 / 2 + 14)
            for label in [count, caption] {
                #expect(label.frame.maxY <= size.1 - size.2 + 0.5)
                #expect(label.frame.minY > scene.courtProjection.farY + 6)
            }
        }
        // An accidentally repeated event does not extend the celebration.
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        state.simulationTime = 2.31
        scene.render(state: state, events: [], delta: 0.16)
        #expect(banner.isHidden && !playerScore.isHidden && !bossScore.isHidden)
        #expect(!(try #require(scene.childNode(withName: "//hudRallySavePlus"))).isHidden)
    }

    @Test("Pause and countdown freeze a celebration without replaying its award")
    func pauseAndCountdown() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = playing(returns: 20)
        state.recoveriesRemaining = 1
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        state.simulationTime += 0.10
        scene.render(state: state, events: [], delta: 0.1)
        let count = try #require(scene.childNode(withName: "//rallyMilestoneCount") as? SKLabelNode)
        let banner = try #require(scene.childNode(withName: "//rallyMilestone"))
        let scale = count.xScale
        state.isPaused = true
        scene.render(state: state, events: [], delta: 3_600)
        #expect(banner.isHidden)
        state.isPaused = false
        state.resumeCountdown = 0.5
        scene.render(state: state, events: [], delta: 3_600)
        #expect(banner.isHidden)
        state.resumeCountdown = 0
        scene.render(state: state, events: [], delta: 0)
        #expect(!banner.isHidden && abs(count.xScale - scale) < 0.00001)
        state.simulationTime += 1.21
        scene.render(state: state, events: [], delta: 1.21)
        #expect(banner.isHidden)
    }

    @Test("Milestone overshoot stays clear of every boss silhouette at legal court extremes",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func milestoneClearsBossArt(size: (Double, Double, Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        scene.setViewport(scene.size, safeTop: size.2, safeBottom: size.3)
        let tuning = GameTuning()
        for id in BossID.allCases {
            let margin = tuning.bossConfiguration(for: id).halfWidth
            for x in [margin, CourtGeometry.centerX, CourtGeometry.width - margin] {
                var state = playing(returns: 0)
                state.mode = .bossRally(id)
                state.boss = BossState(id: id, x: x)
                state.ball = nil
                scene.render(state: state, events: [], delta: 0)
                state.consecutivePlayerReturns = 20
                scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
                state.simulationTime += 0.1
                scene.render(state: state, events: [], delta: 0.1)
                let count = try #require(scene.childNode(withName: "//rallyMilestoneCount"))
                let caption = try #require(scene.childNode(withName: "//rallyMilestoneCaption"))
                let character = try #require(scene.children.first?.children.compactMap { $0 as? CharacterNode }
                    .first { $0.identity == id.rawValue })
                let sprite = try #require(character.children.first as? SKSpriteNode)
                let art = character.art
                let forehand = try #require(art.clips["forehand"])
                let reference = try #require(forehand.contactIndex.map { forehand.frames[$0] })
                for (clipName, clip) in art.clips {
                    for frame in clip.frames {
                        let weight: Double
                        if let contact = clip.contactTime {
                            weight = frame.timestamp <= contact ? min(1, frame.timestamp / contact)
                                : max(0, 1 - (frame.timestamp - contact) / (clip.duration - contact))
                        } else { weight = 0 }
                        let contact = clip.contactIndex.map { clip.frames[$0] }
                        let correctionX = -(contact.map { $0.paddleCenter[0] / art.canvasSize[0] - art.anchor[0] } ?? 0)
                            * sprite.size.width * weight
                        let correctionY = (contact.map { ($0.paddleCenter[1] - reference.paddleCenter[1]) / art.canvasSize[1] } ?? 0)
                            * sprite.size.height * weight
                        let baseVisible = CGRect(
                            x: character.position.x + correctionX + (frame.bounds[0] / art.canvasSize[0] - art.anchor[0]) * sprite.size.width,
                            y: character.position.y + correctionY + (1 - frame.bounds[3] / art.canvasSize[1] - art.anchor[1]) * sprite.size.height,
                            width: (frame.bounds[2] - frame.bounds[0]) / art.canvasSize[0] * sprite.size.width,
                            height: (frame.bounds[3] - frame.bounds[1]) / art.canvasSize[1] * sprite.size.height)
                        // Confirmed contact translates the whole approved frame
                        // toward the paddle. Cover both legal reach extremes.
                        for offset in [-margin - tuning.ballRadius, 0, margin + tuning.ballRadius] {
                            let reach = offset * scene.courtProjection.scale(atLogicalY: tuning.bossConfiguration(for: id).y - tuning.ballRadius) * weight
                            let visible = baseVisible.offsetBy(dx: reach, dy: 0)
                            for label in [count, caption] {
                                #expect(!label.frame.intersects(visible),
                                        "\(id.rawValue) \(clipName) x=\(x) reach=\(offset) frame=\(frame.name), HUD=\(label.frame), art=\(visible)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Points, consumed saves, retry and the next boss clear old feedback; a new rally can celebrate again")
    func resetAndRepeat() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = playing(returns: 20)
        state.recoveriesRemaining = 1
        let banner = try #require(scene.childNode(withName: "//rallyMilestone"))
        let caption = try #require(scene.childNode(withName: "//rallyMilestoneCaption") as? SKLabelNode)
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        state.consecutivePlayerReturns = 0
        state.recoveriesRemaining = 0
        state.phase = .ready
        scene.render(state: state, events: [.ballRecovered(remaining: 0)], delta: 0)
        #expect(banner.isHidden)
        state.phase = .playing
        state.consecutivePlayerReturns = 20
        state.recoveriesRemaining = 1
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        #expect(!banner.isHidden && caption.text == "SAVE READY")
        state.consecutivePlayerReturns = 40
        scene.render(state: state, events: [.rallyMilestone(returns: 40)], delta: 0)
        #expect(!banner.isHidden && caption.text == "ON FIRE")
        state.consecutivePlayerReturns = 0
        state.boss?.points = 1
        scene.render(state: state, events: [.bossPoint(points: 1)], delta: 0)
        #expect(banner.isHidden)
        state.consecutivePlayerReturns = 20
        scene.render(state: state, events: [.rallyMilestone(returns: 20)], delta: 0)
        #expect(!banner.isHidden)
        state.simulationTime = 0 // Same-mode Retry reuses the scene.
        scene.render(state: state, events: [], delta: 0)
        #expect(banner.isHidden)
        state.simulationTime = 1
        scene.render(state: state, events: [.rallyMilestone(returns: 20)], delta: 0)
        #expect(!banner.isHidden)
        state.mode = .bossRally(.dinker) // Play Next, even without a clock change.
        state.boss = BossState(id: .dinker)
        scene.render(state: state, events: [], delta: 0)
        #expect(banner.isHidden)
    }

    @Test("Reduced Motion conveys the same milestone with static text and bounded nodes")
    func reducedMotionAndReuse() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        scene.reduceMotion = true
        var state = playing()
        scene.render(state: state, events: [], delta: 0)
        func allNodes(_ node: SKNode) -> [SKNode] { [node] + node.children.flatMap(allNodes) }
        let allocated = allNodes(scene).count
        let count = try #require(scene.childNode(withName: "//rallyMilestoneCount") as? SKLabelNode)
        let sparks = try #require(scene.childNode(withName: "//rallyMilestoneSparks"))
        let banner = try #require(scene.childNode(withName: "//rallyMilestone"))
        for returns in stride(from: 20, through: 2_000, by: 20) {
            state.consecutivePlayerReturns = returns
            scene.render(state: state, events: [.rallyMilestone(returns: returns)], delta: 0)
            for age in [0.05, 0.1, 0.15] {
                state.simulationTime += age
                scene.render(state: state, events: [], delta: age)
                #expect(count.xScale == 1 && count.yScale == 1)
                #expect(sparks.isHidden && banner.alpha == 1)
            }
        }
        #expect(allNodes(scene).count == allocated)
        #expect(allNodes(scene).allSatisfy { !$0.hasActions() && $0.physicsBody == nil })
        state.mode = .arcade
        scene.render(state: state, events: [], delta: 0)
        #expect((try #require(scene.childNode(withName: "//rallyMomentumHUD"))).isHidden)
    }
}
