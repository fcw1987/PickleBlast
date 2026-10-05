// Native macOS offscreen snapshots of the shared SpriteKit renderer.
// These are fixture renders, NOT Watch simulator or device screenshots.
#if os(macOS)
import AppKit
import Foundation
import PickleBlastCore
import PickleBlastRendering
import SpriteKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/evidence/host-renderer", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let tuning = GameTuning()
var basic = GameState()
basic.phase = .playing
basic.targets = AuthoredWaves.targets(for: 1)
basic.ball = BallState(position: .init(x: 12, y: 18), velocity: .init(x: 5, y: -25))
basic.score = 250
var basket = basic
basket.stage = .wave(2)
basket.targets = AuthoredWaves.targets(for: 2)
if let i = basket.targets.firstIndex(where: { $0.kind == .basket }) { basket.targets[i].health = 1 }
basket.playerAnimation = .backhandContact
basket.ball = BallState(position: .init(x: 8.8, y: tuning.playerY + tuning.ballRadius), velocity: .init(x: -12, y: 23))
var boss = basic
boss.stage = .boss
boss.targets = []
boss.boss = BossState(x: 13, movementTarget: 17, points: 1)
boss.score = 3650
var cascade = basic
cascade.phase = .celebration
cascade.ball = nil
cascade.targets = []
for _ in 0..<360 { cascade.celebration.update(delta: 1.0 / 120) }
let fixtures: [(String, GameState, [GameEvent])] = [
    ("wave1", basic, []), ("basket-contact", basket, [.paddleContact(x: 8.8, side: .backhand, centered: false)]),
    ("boss", boss, []), ("cascade", cascade, [.waveCleared(number: 1)])
]
for (device, size) in [("ultra-reference", CGSize(width: 211, height: 257)), ("small-reference", CGSize(width: 162, height: 197))] {
    for (name, state, events) in fixtures {
        let scene = PickleBlastScene(size: size)
        scene.render(state: state, events: events, delta: 1.0 / 30)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        scene.isPaused = true
        guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: size)) else {
            fatalError("SpriteKit could not render fixture \(name)")
        }
        let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        let path = output.appendingPathComponent("\(device)-\(name).png")
        try png.write(to: path)
        print("HOST RENDER \(path.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) pixels)")
        view.presentScene(nil)
    }
}
if CommandLine.arguments.contains("--rally-milestones") {
    try captureRallyMilestoneEvidence(at: output)
}
if CommandLine.arguments.contains("--arcade-feedback") {
    try captureArcadeFeedbackEvidence(at: output)
}
#else
import Foundation
print("RenderEvidence is a macOS-only development utility.")
#endif
