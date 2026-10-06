import SpriteKit

/// Six reusable lamps on the arena's far rail. No plates, score labels or textures.
final class ArenaScorelights: SKNode {
    private var lamps: [[SKShapeNode]] = []
    private var rails: [SKShapeNode] = []
    private var lastPoints: [Int?] = [nil, nil]
    private var illuminatedAt = Array(repeating: Array(repeating: -Double.infinity, count: 3), count: 2)
    private(set) var playerFrame = CGRect.zero
    private(set) var opponentFrame = CGRect.zero

    override init() {
        super.init()
        name = "arenaScorelights"
        for side in 0..<2 {
            let rail = SKShapeNode()
            rail.name = side == 0 ? "playerScoreRail" : "opponentScoreRail"
            rail.lineWidth = 0.6
            rail.strokeColor = (side == 0 ? Neon.lime : Neon.magenta).withAlphaComponent(0.55)
            addChild(rail); rails.append(rail)
            var row: [SKShapeNode] = []
            for index in 0..<3 {
                let lamp = SKShapeNode(circleOfRadius: 3.5)
                lamp.name = "scorelight.\(side == 0 ? "player" : "opponent").\(index)"
                lamp.lineWidth = 0.7
                addChild(lamp); row.append(lamp)
            }
            lamps.append(row)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func layout(width: CGFloat, leading: CGFloat, trailing: CGFloat, y: CGFloat) {
        let left = leading + 12
        let right = width - trailing - 12
        for side in 0..<2 {
            for index in 0..<3 {
                lamps[side][index].position = CGPoint(x: side == 0 ? left + CGFloat(index) * 11 : right - CGFloat(2 - index) * 11, y: y + 2)
            }
            let row = lamps[side]
            let path = CGMutablePath()
            path.move(to: CGPoint(x: row[0].position.x - 4, y: y - 4))
            path.addLine(to: CGPoint(x: row[2].position.x + 4, y: y - 4))
            rails[side].path = path
        }
        playerFrame = CGRect(x: left - 3.5, y: y - 1.5, width: 29, height: 7)
        opponentFrame = CGRect(x: right - 25.5, y: y - 1.5, width: 29, height: 7)
    }

    func render(playerPoints: Int, opponentPoints: Int, time: Double, reduceMotion: Bool) {
        for (side, raw) in [playerPoints, opponentPoints].enumerated() {
            let points = min(3, max(0, raw))
            if lastPoints[side] != points {
                for index in 0..<3 {
                    let lit = index < points
                    let lamp = lamps[side][index]
                    lamp.fillColor = lit ? (side == 0 ? Neon.lime : Neon.magenta) : SKColor(red: 0.12, green: 0.18, blue: 0.24, alpha: 1)
                    lamp.strokeColor = lit ? Neon.white.withAlphaComponent(0.65) : SKColor(red: 0.55, green: 0.65, blue: 0.75, alpha: 0.8)
                    illuminatedAt[side][index] = lit && lastPoints[side] != nil && index >= lastPoints[side]! ? time : -.infinity
                }
                lastPoints[side] = points
            }
            for index in 0..<3 {
                // A gentle, one-time settle, never a pulse or a growing dot.
                let age = time - illuminatedAt[side][index]
                lamps[side][index].alpha = reduceMotion ? 1 : min(1, 0.72 + max(0, age) / 0.18 * 0.28)
            }
        }
    }
}
