import SpriteKit
import Testing
import PickleBlastCore
@testable import PickleBlastRendering

@Suite("Slate competition presentation invariants")
@MainActor
struct NightArenaTests {
    private func descendants(_ node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + descendants($0) }
    }

    @Test("Point flashes and pause never expose scenery through the regulation playing surface",
          arguments: [(162.0, 197.0, 40.0, 19.0), (211.0, 257.0, 56.5, 40.0)])
    func opaqueCourtDuringFeedback(size: (Double, Double, Double, Double)) throws {
        let scene = PickleBlastScene(size: CGSize(width: size.0, height: size.1))
        scene.setViewport(scene.size, safeTop: size.2, safeBottom: size.3)
        var state = GameState()
        state.mode = .bossRally(.lobber)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .lobber)
        state.simulationTime = 1
        scene.render(state: state, events: [.bossPoint(points: 1)], delta: 0)
        let surface = try #require(scene.childNode(withName: "//opaqueCourtSurface") as? SKShapeNode)
        let court = try #require(scene.childNode(withName: "//nightArenaCourt") as? NightArenaCourt)
        let path = try #require(surface.path)
        // Deep samples cover both service courts and both non-volley zones.
        for x in [2.0, 7, 13, 18] {
            for y in [2.0, 12, 18, 26, 33, 42] {
                let projected = scene.courtProjection.screenPoint(for: .init(x: x, y: y))
                #expect(path.contains(CGPoint(x: projected.x, y: projected.y)))
            }
        }
        #expect(surface.fillTexture != nil, "The approved blue acrylic material fills the regulation court")
        #expect(surface.fillTexture?.filteringMode == .linear)
        #expect(surface.fillColor.cgColor.alpha == 1)
        #expect(surface.alpha == 1 && court.alpha == 1)
        #expect(court.markingAlpha < 1)

        state.isPaused = true
        let frozen = court.markingAlpha
        scene.render(state: state, events: [], delta: 20)
        #expect(court.markingAlpha == frozen)
        #expect(surface.alpha == 1 && court.alpha == 1)
        state.phase = .blackout
        scene.render(state: state, events: [], delta: 0)
        #expect(scene.children.first?.isHidden == true)
    }

    @Test("New court details retain regulation line endpoints and net plane after resizing")
    func regulationProjection() throws {
        let court = NightArenaCourt()
        let initial = Set(descendants(court).map(ObjectIdentifier.init))
        for (width, height) in [(162.0, 197.0), (211.0, 257.0)] {
            let projection = CourtProjection(viewportWidth: width, viewportHeight: height)
            court.layout(projection: projection)
            for (name, lines) in [
                ("courtPerimeter", CourtGeometry.boundaryLines),
                ("courtInteriorLines", CourtGeometry.nonVolleyLines + CourtGeometry.serviceLines),
                ("courtNetTape", [CourtGeometry.net])
            ] {
                let shape = try #require(court.childNode(withName: "//" + name) as? SKShapeNode)
                let path = try #require(shape.path)
                var points: [CGPoint] = []
                path.applyWithBlock { element in
                    if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                        points.append(element.pointee.points[0])
                    }
                }
                #expect(points.count == lines.count * 2)
                for (actual, logical) in zip(points, lines.flatMap { [$0.start, $0.end] }) {
                    let expected = projection.screenPoint(for: logical)
                    #expect(abs(actual.x * shape.xScale - expected.x) < 0.00005)
                    #expect(abs(actual.y * shape.yScale - expected.y) < 0.00005)
                }
            }
            #expect(Set(descendants(court).map(ObjectIdentifier.init)) == initial)
        }
    }

    @Test("Slate paint separates the regulation kitchens without texture copies or collision geometry")
    func kitchenMaterialAndNet() throws {
        let textures = TextureLibrary()
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197), textureLibrary: textures)
        let surface = try #require(scene.childNode(withName: "//opaqueCourtSurface") as? SKShapeNode)
        let kitchen = try #require(scene.childNode(withName: "//courtNonVolleyMaterial") as? SKShapeNode)
        let tape = try #require(scene.childNode(withName: "//courtNetTape") as? SKShapeNode)
        let material = try #require(surface.fillTexture)
        #expect(material === textures.supporting("courtSlateB3"), "One cached texture covers the whole surface")
        #expect(kitchen.fillTexture == nil, "Kitchen paint reuses material beneath it without another texture")
        #expect(kitchen.zPosition > surface.zPosition && kitchen.zPosition < tape.parent!.zPosition)
        for size in [CGSize(width: 162, height: 197), CGSize(width: 211, height: 257)] {
            scene.setViewport(size, safeTop: 40, safeBottom: 19)
            let path = try #require(kitchen.path)
            for (y, inside) in [(14.9, false), (15.1, true), (21.9, true), (22.1, true), (28.9, true), (29.1, false)] {
                let point = scene.courtProjection.screenPoint(for: .init(x: 10, y: y))
                #expect(path.contains(CGPoint(x: point.x, y: point.y)) == inside)
            }
            #expect(surface.fillTexture === material, "Resizing does not generate another material")
        }
        #expect(descendants(try #require(surface.parent)).allSatisfy { $0.physicsBody == nil && !$0.hasActions() })
    }

    @Test("Rally redraws reuse decoration without adding actions, physics or character children")
    func decorationLifetime() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.mode = .bossRally(.dinker)
        state.stage = .boss
        state.phase = .playing
        state.boss = BossState(id: .dinker)
        scene.render(state: state, events: [], delta: 0)
        let initial = Set(descendants(scene).map(ObjectIdentifier.init))
        let court = try #require(scene.childNode(withName: "//nightArenaCourt"))
        let perimeter = try #require(court.childNode(withName: "//courtPerimeter") as? SKShapeNode)
        let path = perimeter.path
        for frame in 1...120 {
            state.simulationTime = Double(frame) / 30
            state.playerX = 10 + sin(Double(frame) / 10)
            scene.render(state: state, events: [], delta: 1.0 / 30)
        }
        #expect(Set(descendants(scene).map(ObjectIdentifier.init)) == initial)
        #expect(perimeter.path === path, "Static court geometry is not rebuilt for animation frames")
        #expect(descendants(scene).allSatisfy { $0.physicsBody == nil && !$0.hasActions() })
        let characters = descendants(scene).compactMap { $0 as? CharacterNode }
        #expect(characters.count == 2 && characters.allSatisfy { $0.children.count == 1 })
    }

    @Test("Grounding remains beneath a visibly translated contact pose")
    func groundingFollowsContact() throws {
        let scene = PickleBlastScene(size: CGSize(width: 162, height: 197))
        var state = GameState()
        state.phase = .playing
        state.playerX = 10
        scene.render(state: state, events: [.paddleContact(x: 11.2, side: .forehand, centered: false)], delta: 0)
        let player = try #require(descendants(scene).compactMap { $0 as? CharacterNode }.first { $0.identity == "player" })
        let sprite = try #require(player.children.first)
        let grounding = try #require(scene.childNode(withName: "//playerGrounding"))
        #expect(abs(sprite.position.x) > 0.1, "Fixture must exercise whole-frame contact translation")
        #expect(abs(grounding.position.x - player.position.x - sprite.position.x) < 0.00005)
        #expect(abs(grounding.position.y - player.position.y - sprite.position.y + 1.2) < 0.00005)
    }
}
