import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Dense presentation resource bounds")
@MainActor
struct DensePerformanceTests {
    private func descendants(_ node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + descendants($0) }
    }

    @Test("Rapid target feedback reuses nodes and labels through full cascade and replay")
    func boundedRapidFeedback() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.phase = .playing
        // Deliberately synthetic event load: stronger than normal hit delivery,
        // and not evidence of reachability or a naturally earned combo.
        state.targets = (0..<58).map { index in
            TargetState(id: index, kind: .paddle,
                        position: .init(x: 1.5 + Double(index % 10) * 1.85,
                                        y: 28 + Double(index / 10) * 2.4), radius: 0.45)
        }
        state.ball = BallState(position: .init(x: 10, y: 25), velocity: .init(x: 0, y: 26))
        scene.render(state: state, events: [], delta: 0)
        let initialNodes = descendants(scene)
        let initialIDs = Set(initialNodes.map(ObjectIdentifier.init))
        let targetIDs = Set(initialNodes.filter { $0 is TargetNode }.map(ObjectIdentifier.init))
        let labels = initialNodes.filter { $0 is SKLabelNode }.count
        #expect(targetIDs.count == 58)
        var samples: [Double] = []
        for frame in 0..<600 {
            state.simulationTime += 1.0 / 30
            state.targetChain = frame + 1
            state.score += 500
            let events: [GameEvent] = (0..<8).map { offset in
                .targetHit(id: (frame + offset) % 58, kind: .paddle, destroyed: false, score: 500)
            } + [.comboChanged(chain: frame + 1, multiplier: 5)]
            let start = ProcessInfo.processInfo.systemUptime
            scene.render(state: state, events: events, delta: 1.0 / 30)
            samples.append(ProcessInfo.processInfo.systemUptime - start)
            if frame % 60 == 0 {
                let nodes = descendants(scene)
                #expect(Set(nodes.map(ObjectIdentifier.init)) == initialIDs)
                #expect(nodes.filter { $0 is SKLabelNode }.count == labels)
            }
        }
        state.phase = .celebration
        state.targets.removeAll()
        state.ball = nil
        for _ in 0..<150 {
            state.simulationTime += 1.0 / 30
            state.celebration.update(delta: 1.0 / 30)
            scene.render(state: state, events: [], delta: 1.0 / 30)
        }
        #expect(state.celebration.activeCount == 128)
        let cascadeNodes = descendants(scene)
        #expect(cascadeNodes.filter { $0 is TargetNode }.isEmpty)
        #expect(cascadeNodes.filter { $0 is SKLabelNode }.count == labels)
        #expect(cascadeNodes.count == initialNodes.count - 58 * 2)
        let cascadeLayer = try #require(scene.children.first { $0.zPosition == 30 })
        #expect(cascadeLayer.children.count == 128)
        #expect(cascadeLayer.children.filter { !$0.isHidden }.count == 128)

        scene.render(state: GameState(), events: [], delta: 0)
        #expect(cascadeLayer.children.count == 128)
        #expect(cascadeLayer.isHidden)
        #expect(Set(descendants(scene).map(ObjectIdentifier.init)).isSubset(of: initialIDs))
        samples.sort()
        let mean = samples.reduce(0, +) / Double(samples.count)
        print("DENSE_RENDER_PERFORMANCE synthetic_frames=600 events_per_frame=9 targets=58 scene_nodes=\(initialNodes.count) labels=\(labels) cascade_nodes=128 host_mean_ms=\(mean * 1_000) host_p95_ms=\(samples[Int(Double(samples.count - 1) * 0.95)] * 1_000) host_max_ms=\(samples.last! * 1_000) native_gpu_fps=unmeasured")
    }
}
