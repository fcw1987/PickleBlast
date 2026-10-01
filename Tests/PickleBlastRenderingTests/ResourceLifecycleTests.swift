import Foundation
import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Renderer resource lifecycle")
@MainActor
struct ResourceLifecycleTests {
    @Test("Repeated input redraws retain the same scene resources")
    func repeatedInputRedraws() throws {
        let textures = TextureLibrary()
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197), textureLibrary: textures)
        var state = GameState()
        state.phase = .playing
        scene.render(state: state, events: [], delta: 0)

        let initialChildren = scene.children.count
        let initialCached = textures.debugCachedTextureCount
        let initialRequests = textures.debugTextureRequests
        let initialMisses = textures.debugTextureMisses
        var samples: [Double] = []
        samples.reserveCapacity(600)
        // Crown and drag input may request several redraws before the next
        // simulation tick. The visual clock and approved animation frame stay
        // fixed in this workload, so only positions could need updating.
        for _ in 0..<600 {
            let start = ProcessInfo.processInfo.systemUptime
            scene.render(state: state, events: [], delta: 0)
            samples.append(ProcessInfo.processInfo.systemUptime - start)
        }
        let requests = textures.debugTextureRequests - initialRequests
        let misses = textures.debugTextureMisses - initialMisses
        #expect(scene.children.count == initialChildren)
        #expect(textures.debugCachedTextureCount == initialCached)
        #expect(misses == 0)
        #expect(requests == 0, "An unchanged approved frame and unchanged hearts need no texture lookup")

        samples.sort()
        let mean = samples.reduce(0, +) / Double(samples.count)
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        print("REPEATED_RENDER_RESOURCES renders=600 texture_requests=\(requests) cache_misses=\(misses) cached_textures=\(textures.debugCachedTextureCount) host_mean_ms=\(mean * 1_000) host_p95_ms=\(p95 * 1_000) watch_fps=unmeasured")

        state.lives -= 1
        scene.render(state: state, events: [], delta: 0)
        let hud = try #require(scene.children.first { $0.zPosition == 20 })
        let heartSprites = hud.children.compactMap { $0 as? SKSpriteNode }
        #expect(heartSprites.count == 3)
        let empty = textures.supporting("uiHeartEmpty")
        #expect(heartSprites.filter { $0.texture === empty }.count == 1)

        let world = try #require(scene.children.first)
        let player = try #require(world.children.compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let image = try #require(player.children.first as? SKSpriteNode)
        let previousFrame = try #require(image.texture)
        // The existing idle-settle policy waits 0.10 s before advancing its
        // idle clip; move past that interval to verify a real frame change.
        state.simulationTime += 0.2
        scene.render(state: state, events: [], delta: 0.2)
        #expect(image.texture !== previousFrame, "An advancing approved clip must still display its next frame")
    }

    @Test("Discarded scenes release their node trees across repeated creation")
    func sceneRelease() {
        let textures = TextureLibrary()
        var weakScenes: [WeakScene] = []
        for _ in 0..<20 {
            var scene: PickleBlastScene? = PickleBlastScene(
                size: CGSize(width: 162, height: 197), textureLibrary: textures)
            weakScenes.append(WeakScene(scene))
            scene?.render(state: GameState(), events: [], delta: 0)
            scene = nil
        }
        #expect(weakScenes.allSatisfy { $0.value == nil })
        print("SCENE_RELEASE iterations=20 surviving_scenes=\(weakScenes.filter { $0.value != nil }.count) cached_textures=\(textures.debugCachedTextureCount) loaded_atlases=\(textures.debugLoadedAtlasCount)")
    }
}

private final class WeakScene {
    weak var value: PickleBlastScene?
    init(_ value: PickleBlastScene?) { self.value = value }
}
