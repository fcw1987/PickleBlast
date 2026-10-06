import Foundation
import Testing
import SpriteKit
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Arena scorelights")
@MainActor struct ArenaScoreboardTests {
    @Test("Six lamps show every point count and reset without reallocating; no Boss Rally numbers or plaques",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func points(size: (Double, Double, Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        scene.setViewport(scene.size, safeTop: size.2, safeBottom: size.3)
        var state = GameState(); state.mode = .bossRally(.poacher); state.phase = .playing
        state.stage = .boss; state.boss = BossState(id: .poacher); state.recoveriesRemaining = 0
        scene.render(state: state, events: [], delta: 0)
        let root = try #require(scene.childNode(withName: "//arenaScorelights"))
        let allocated = root.children.map(ObjectIdentifier.init)
        let clock = try #require(scene.childNode(withName: "//systemClockBacking"))
        #expect(scene.childNode(withName: "//hudScorePanels") == nil)
        for side in ["player", "opponent"] {
            for points in [0, 1, 2, 3, 0] {
                if side == "player" { state.boss?.points = points } else { state.boss?.opponentPoints = points }
                state.simulationTime += 0.3
                scene.render(state: state, events: [], delta: 0.3)
                for index in 0..<3 {
                    let lamp = try #require(scene.childNode(withName: "//scorelight.\(side).\(index)") as? SKShapeNode)
                    let color = side == "player" ? Neon.lime : Neon.magenta
                    #expect((lamp.fillColor == color) == (index < points))
                    #expect(!lamp.frame.intersects(clock.frame))
                    #expect(lamp.frame.maxY < clock.frame.minY)
                    #expect(side == "player" ? lamp.frame.maxX < size.0 / 2 - 22 : lamp.frame.minX > size.0 / 2 + 22)
                }
                #expect((try #require(scene.childNode(withName: "//hudPlayerScore"))).isHidden)
                #expect((try #require(scene.childNode(withName: "//hudOpponentScore"))).isHidden)
            }
        }
        #expect(root.children.map(ObjectIdentifier.init) == allocated)
        state.recoveriesRemaining = 1; state.consecutivePlayerReturns = 20
        scene.render(state: state, events: [.rallyMilestone(returns: 20), .recoveryEarned], delta: 0)
        #expect(!root.isHidden)
        for side in ["player", "opponent"] { for index in 0..<3 {
            #expect(!(try #require(scene.childNode(withName: "//scorelight.\(side).\(index)"))).isHidden)
        } }
        state.mode = .arcade
        scene.render(state: state, events: [], delta: 0)
        #expect(root.isHidden)
    }

    @Test("A new point settles once; paused clocks and Reduce Motion never animate the lamps")
    func settle() throws {
        let lights = ArenaScorelights()
        lights.render(playerPoints: 0, opponentPoints: 0, time: 1, reduceMotion: false)
        lights.render(playerPoints: 1, opponentPoints: 0, time: 2, reduceMotion: false)
        let lamp = try #require(lights.childNode(withName: "scorelight.player.0"))
        #expect(abs(lamp.alpha - 0.72) < 1e-6)
        lights.render(playerPoints: 1, opponentPoints: 0, time: 2, reduceMotion: false)
        #expect(abs(lamp.alpha - 0.72) < 1e-6)
        lights.render(playerPoints: 1, opponentPoints: 0, time: 2.19, reduceMotion: false)
        #expect(lamp.alpha == 1 && lamp.xScale == 1)
        lights.render(playerPoints: 2, opponentPoints: 0, time: 3, reduceMotion: true)
        #expect((try #require(lights.childNode(withName: "scorelight.player.1"))).alpha == 1)
    }

    @Test("Transient tiny viewports remain valid and Arcade still fits large scores",
          arguments: [(1.0, 1.0), (162.0, 197.0), (211.0, 257.0)])
    func arcade(size: (Double, Double)) throws {
        let scene = PickleBlastScene(size: .zero)
        scene.setViewport(CGSize(width: size.0, height: size.1), safeTop: 0, safeBottom: 0)
        var state = GameState(); state.phase = .playing; state.score = 60_225
        scene.render(state: state, events: [], delta: 0)
        let score = try #require(scene.childNode(withName: "//hudPlayerScore") as? SKLabelNode)
        #expect(score.text == "60225" && !score.isHidden)
        if size.0 > 1 { #expect(score.frame.maxX < size.0 / 2 - 27 + 0.5) }
    }
}
