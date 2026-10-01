import Testing
import SpriteKit
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Compact combo presentation")
@MainActor
struct ComboPresentationTests {
    @Test func restartDoesNotCarryOldTargetFlashDeadline() throws {
        let scene = PickleBlastScene(size: CGSize(width: 211, height: 257))
        var state = GameState()
        state.targets = AuthoredWaves.targets(for: 1)
        scene.render(state: state, events: [], delta: 0)
        state.simulationTime = 60
        scene.render(state: state, events: [.targetHit(id: 100, kind: .paddle, destroyed: false, score: 100)], delta: 60)
        let nodes = scene.children.flatMap(\.children).compactMap { $0 as? TargetNode }
        #expect(nodes.compactMap { $0.children.first as? SKSpriteNode }.contains { $0.colorBlendFactor > 0.64 })
        state.simulationTime = 0
        scene.render(state: state, events: [], delta: 0)
        #expect(nodes.compactMap { $0.children.first as? SKSpriteNode }.allSatisfy { $0.colorBlendFactor == 0 })
    }
    @Test func aggregateFreezeExpireAndReset() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.phase = .playing
        state.targets = AuthoredWaves.targets(for: 3)
        scene.render(state: state, events: [], delta: 0)
        let label = try #require(scene.childNode(withName: "//comboIndicator") as? SKLabelNode)
        state.targetChain = 3
        state.simulationTime = 0.1
        scene.render(state: state, events: [
            .targetHit(id: 300, kind: .paddle, destroyed: true, score: 100),
            .targetHit(id: 301, kind: .paddle, destroyed: true, score: 200),
            .targetHit(id: 302, kind: .paddle, destroyed: true, score: 300)
        ], delta: 0.1)
        #expect(label.text == "×3  +600")
        #expect(!label.isHidden)
        state.isPaused = true
        state.simulationTime += 3600
        scene.render(state: state, events: [], delta: 3600)
        #expect(!label.isHidden)
        state.isPaused = false
        state.simulationTime += 0.71
        scene.render(state: state, events: [], delta: 0.71)
        #expect(label.isHidden)
        state.targetChain = 5
        scene.render(state: state, events: [.targetHit(id: 303, kind: .paddle, destroyed: true, score: 500)], delta: 0)
        #expect(label.text == "×5  +500")
        state.targetChain = 0
        scene.render(state: state, events: [.comboChanged(chain: 0, multiplier: 1)], delta: 0)
        #expect(label.isHidden)
        #expect(scene.childNode(withName: "//comboIndicator") === label)
    }
}
