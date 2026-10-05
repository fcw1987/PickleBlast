#if os(macOS)
import AppKit
import ImageIO
import PickleBlastCore
import PickleBlastRendering
import SpriteKit
import UniformTypeIdentifiers

/// Shared-engine presentation fixtures. Ball/poses are held deliberately so the
/// milestone can be inspected; these are not screenshots of live Watch play.
func captureRallyMilestoneEvidence(at output: URL) throws {
    let sizes: [(String, CGSize)] = [
        ("large", CGSize(width: 211, height: 257)),
        ("small", CGSize(width: 162, height: 197))
    ]
    for (name, size) in sizes {
        for returns in [0, 19, 20, 21, 40] {
            let scene = PickleBlastScene(size: size)
            scene.setViewport(size, safeTop: name == "large" ? 56.5 : 40,
                              safeBottom: name == "large" ? 40 : 19)
            let view = SKView(frame: CGRect(origin: .zero, size: size))
            view.presentScene(scene)
            scene.isPaused = true
            var state = milestoneState(returns: returns)
            state.simulationTime = 1
            scene.render(state: state, events: [], delta: 0)
            if returns == 20 || returns == 40 {
                let events: [GameEvent] = returns == 20
                    ? [.rallyMilestone(returns: 20), .recoveryEarned]
                    : [.rallyMilestone(returns: 40)]
                scene.render(state: state, events: events, delta: 0)
                state.simulationTime = 1.2
                scene.render(state: state, events: [], delta: 0.2)
            }
            try savePNG(snapshot(view: view, scene: scene, size: size),
                        to: output.appendingPathComponent("\(name)-returns-\(returns).png"))
            view.presentScene(nil)
        }
        for reducedMotion in [false, true] {
            let scene = PickleBlastScene(size: size)
            scene.setViewport(size, safeTop: name == "large" ? 56.5 : 40,
                              safeBottom: name == "large" ? 40 : 19)
            scene.reduceMotion = reducedMotion
            let view = SKView(frame: CGRect(origin: .zero, size: size))
            view.presentScene(scene)
            scene.isPaused = true
            let suffix = reducedMotion ? "reduced-motion" : "animated"
            let url = output.appendingPathComponent("\(name)-milestone-\(suffix).gif")
            let frameCount = 60
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                UTType.gif.identifier as CFString, frameCount, nil) else {
                fatalError("Could not create milestone GIF")
            }
            CGImageDestinationSetProperties(destination,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for frame in 0..<frameCount {
                var state = milestoneState(returns: frame < 10 ? 19 : 20)
                state.simulationTime = 1 + Double(frame) / 30
                let events: [GameEvent] = frame == 10
                    ? [.rallyMilestone(returns: 20), .recoveryEarned] : []
                scene.render(state: state, events: events, delta: 1.0 / 30)
                let cgImage = try snapshot(view: view, scene: scene, size: size)
                CGImageDestinationAddImage(destination, cgImage,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else {
                fatalError("Milestone GIF encoding failed")
            }
            view.presentScene(nil)
        }
    }
    let provenance = """
    Shared PickleBlast SpriteKit renderer, native macOS offscreen fixture capture.
    Logical viewports: large 211×257pt and small 162×197pt; PNG/GIF use the host's actual backing scale.
    Player, Lobber, ball and score state are held to isolate HUD feedback. These are not live Watch screenshots.
    Safe insets match measured Watch layouts; the SwiftUI system clock and Pause overlay are not part of this renderer-only capture.
    GIFs sample 60 render states at 30Hz; GIF encoding/playback is not a frame-timing measurement.
    At frame10, the core milestone/recovery events are provided once. Reduced Motion uses the same event timeline.
    Run: swift run RenderEvidence <output-directory> --rally-milestones
    """
    try provenance.write(to: output.appendingPathComponent("CAPTURE.txt"), atomically: true, encoding: .utf8)
}

private func milestoneState(returns: Int) -> GameState {
    var state = GameState()
    state.mode = .bossRally(.lobber)
    state.stage = .boss
    state.phase = .playing
    state.boss = BossState(id: .lobber, x: 13, movementTarget: 13, points: 1)
    state.playerX = 10
    state.ball = BallState(position: .init(x: 12, y: 18), velocity: .init(x: 5, y: -25))
    state.currentRallyReturns = returns * 2
    state.consecutivePlayerReturns = returns
    state.recoveriesRemaining = returns >= 20 ? 1 : 0
    return state
}

private func snapshot(view: SKView, scene: SKScene, size: CGSize) throws -> CGImage {
    guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: size)) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return texture.cgImage()
}

private func savePNG(_ image: CGImage, to url: URL) throws {
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}
#endif
