#if os(macOS)
import AppKit
import ImageIO
import PickleBlastCore
import PickleBlastRendering
import SpriteKit
import UniformTypeIdentifiers

/// Held-state art/feedback preview, deliberately separate from live gameplay
/// and performance measurements. Uses the shipping renderer and event types.
func captureArcadeFeedbackEvidence(at output: URL) throws {
    for (name, size, top, bottom) in [("large", CGSize(width: 211, height: 257), 56.5, 40.0),
                                       ("small", CGSize(width: 162, height: 197), 40.0, 19.0)] {
        for reduced in [false, true] {
            let scene = PickleBlastScene(size: size)
            scene.setViewport(size, safeTop: top, safeBottom: bottom)
            scene.reduceMotion = reduced
            let view = SKView(frame: CGRect(origin: .zero, size: size))
            view.presentScene(scene); scene.isPaused = true
            let url = output.appendingPathComponent("\(name)-arcade-\(reduced ? "reduced-motion" : "animated").gif")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 72, nil)!
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            var state = GameState()
            state.phase = .playing; state.stage = .wave(2)
            state.targets = AuthoredWaves.targets(for: 2)
            state.ball = BallState(position: .init(x: 12, y: 18), velocity: .init(x: 5, y: -25))
            for frame in 0..<72 {
                state.simulationTime = 1 + Double(frame) / 30
                var events: [GameEvent] = []
                if [10, 20, 30].contains(frame), let target = state.targets.first {
                    state.targetChain += 1; state.score += 100
                    events = [.targetHit(id: target.id, kind: target.kind, destroyed: false, score: 100)]
                }
                if frame == 48 {
                    state.targets = []; state.ball = nil; state.phase = .celebration
                    events = [.waveCleared(number: 2)]
                }
                if state.phase == .celebration { state.celebration.update(delta: 1.0 / 30) }
                scene.render(state: state, events: events, delta: 1.0 / 30)
                guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: size)) else { fatalError("Arcade preview capture failed") }
                let image = texture.cgImage()
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
                if [0, 12, 32, 50].contains(frame), !reduced {
                    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                    try data.write(to: output.appendingPathComponent("\(name)-arcade-frame-\(frame).png"))
                }
            }
            guard CGImageDestinationFinalize(destination) else { fatalError("Arcade GIF encoding failed") }
            view.presentScene(nil)
        }
    }
}
#endif
