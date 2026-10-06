import Foundation
import Testing
import SpriteKit
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Arena scoreboard layout and contextual information")
@MainActor struct ArenaScoreboardTests {
    @Test("Separate plaques leave Pause and clock clear; every boss name fits",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func plaques(size: (Double, Double, Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        scene.setViewport(scene.size, safeTop: size.2, safeBottom: size.3)
        for id in BossID.allCases {
            var state = GameState()
            state.mode = .bossRally(id); state.stage = .boss; state.phase = .playing
            state.boss = BossState(id: id); state.recoveriesRemaining = 0
            scene.render(state: state, events: [], delta: 0)
            let plates = try #require(scene.childNode(withName: "//hudScorePanels") as? SKShapeNode)
            let path = try #require(plates.path)
            let center = CGFloat(scene.courtProjection.centerX)
            let y = CGFloat(scene.courtProjection.hudY)
            for x in [center - 22, center, center + 22] {
                #expect(!path.contains(CGPoint(x: x, y: y)))
            }
            let clock = try #require(scene.childNode(withName: "//systemClockBacking"))
            #expect(plates.frame.maxY < clock.frame.minY, "Plaque top \(plates.frame.maxY), clock bottom \(clock.frame.minY)")
            let name = try #require(scene.childNode(withName: "//hudOpponentIdentity") as? SKLabelNode)
            #expect(name.text == id.rawValue.uppercased())
            #expect(name.frame.minX > center + 27 && name.frame.maxX < size.0 - 6)
            #expect(name.frame.maxY < clock.frame.minY)
            #expect((try #require(scene.childNode(withName: "//hudRallySave"))).isHidden)
            state.recoveriesRemaining = 1
            scene.render(state: state, events: [], delta: 0)
            let save = try #require(scene.childNode(withName: "//hudRallySave"))
            #expect(!save.isHidden && save.frame.maxX < center - 27)
            #expect((try #require(scene.childNode(withName: "//hudRallyProgress"))).isHidden)
        }
    }

    @Test("Transient tiny SpriteKit viewports keep valid plaque paths")
    func tinyViewport() throws {
        let scene = PickleBlastScene(size: .zero)
        scene.setViewport(CGSize(width: 1, height: 1), safeTop: 0, safeBottom: 0)
        #expect((try #require(scene.childNode(withName: "//hudScorePanels") as? SKShapeNode)).path != nil)
    }

    @Test("Arcade keeps full score, three life slots and mode identity inside the plaques",
          arguments: [(162.0, 197.0), (211.0, 257.0)])
    func arcade(size: (Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        var state = GameState(); state.phase = .playing; state.score = 60_225
        scene.render(state: state, events: [], delta: 0)
        let score = try #require(scene.childNode(withName: "//hudPlayerScore") as? SKLabelNode)
        #expect(score.text == "60225")
        #expect(score.frame.maxX < size.0 / 2 - 27)
        #expect((scene.childNode(withName: "//hudPlayerIdentity") as? SKLabelNode)?.text == "POINTS")
        #expect((scene.childNode(withName: "//hudOpponentIdentity") as? SKLabelNode)?.text == "LIVES")
        #expect((try #require(scene.childNode(withName: "//hudOpponentScore"))).isHidden)
    }
}
