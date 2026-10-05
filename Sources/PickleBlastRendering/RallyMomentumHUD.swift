import Foundation
import PickleBlastCore
import SpriteKit

/// A fixed set of small HUD nodes. Milestones replace the score row briefly;
/// nothing is emitted over the court, ball or character contact poses.
final class RallyMomentumHUD: SKNode {
    private let track = SKShapeNode(circleOfRadius: 4.5)
    private let progress = SKShapeNode()
    private let save = SKShapeNode()
    private let savePlus = SKShapeNode()
    private let milestone = SKNode()
    private let count = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let caption = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let sparks = SKShapeNode()
    private var began = -Double.infinity
    private var lastMilestone = 0
    private var lastReturns = 0
    private var displayedProgress: Int?
    private var displayedSave: Bool?
    private var leftWidth: CGFloat = 50
    private var rightWidth: CGFloat = 50
    private var countAnchor = CGPoint.zero
    private var previousPlayerFrame: CGRect?
    private var previousOpponentFrame: CGRect?
    private var previousCenter: CGFloat?
    private let duration = 1.3

    override init() {
        super.init()
        name = "rallyMomentumHUD"
        track.name = "hudRallyProgressTrack"
        progress.name = "hudRallyProgress"
        save.name = "hudRallySave"
        savePlus.name = "hudRallySavePlus"
        milestone.name = "rallyMilestone"
        count.name = "rallyMilestoneCount"
        caption.name = "rallyMilestoneCaption"
        sparks.name = "rallyMilestoneSparks"
        for shape in [track, progress, save, savePlus, sparks] {
            shape.fillColor = .clear
            shape.lineWidth = 1
            CrispVector.prepare(shape)
        }
        track.strokeColor = Neon.white.withAlphaComponent(0.22)
        progress.strokeColor = Neon.lime
        progress.lineWidth = 1.6 * CrispVector.resolution
        let shield = CGMutablePath()
        shield.move(to: CGPoint(x: -4.4, y: 4.4))
        shield.addLine(to: CGPoint(x: 4.4, y: 4.4))
        shield.addLine(to: CGPoint(x: 4, y: -1.3))
        shield.addQuadCurve(to: CGPoint(x: 0, y: -5.1), control: CGPoint(x: 3, y: -3.8))
        shield.addQuadCurve(to: CGPoint(x: -4, y: -1.3), control: CGPoint(x: -3, y: -3.8))
        shield.closeSubpath()
        CrispVector.replacePath(of: save, with: shield)
        let plus = CGMutablePath()
        plus.move(to: CGPoint(x: -2, y: 0.3)); plus.addLine(to: CGPoint(x: 2, y: 0.3))
        plus.move(to: CGPoint(x: 0, y: -1.7)); plus.addLine(to: CGPoint(x: 0, y: 2.3))
        CrispVector.replacePath(of: savePlus, with: plus)
        savePlus.strokeColor = Neon.black
        for node in [track, progress, save, savePlus] { addChild(node) }
        addChild(milestone)
        for label in [count, caption] {
            label.verticalAlignmentMode = .center
            milestone.addChild(label)
        }
        count.horizontalAlignmentMode = .left
        count.fontColor = Neon.white
        count.fontSize = 18
        caption.horizontalAlignmentMode = .right
        caption.fontSize = 9
        caption.fontColor = Neon.lime
        sparks.strokeColor = Neon.lime
        milestone.addChild(sparks)
        milestone.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func layout(playerScore: CGRect, opponentScore: CGRect, y: CGFloat, centerX: CGFloat) {
        guard previousPlayerFrame != playerScore || previousOpponentFrame != opponentScore || previousCenter != centerX else { return }
        previousPlayerFrame = playerScore
        previousOpponentFrame = opponentScore
        previousCenter = centerX
        track.position = CGPoint(x: playerScore.maxX + 9, y: y + 1)
        progress.position = track.position
        save.position = CGPoint(x: opponentScore.minX - 9, y: y + 1)
        savePlus.position = save.position
        countAnchor = CGPoint(x: playerScore.minX + 2, y: y + 1.5)
        count.position = countAnchor
        caption.position = CGPoint(x: opponentScore.maxX, y: y)
        leftWidth = max(12, centerX - 18 - countAnchor.x)
        rightWidth = max(12, opponentScore.maxX - centerX - 18)
        fitCount()
        // Two crisp accents stay inside the same safe 20-point row as the text.
        let path = CGMutablePath()
        let edge = min(centerX - 19, countAnchor.x + count.frame.width + 5)
        for direction in [-1.0, 1.0] {
            path.move(to: CGPoint(x: edge, y: y + direction * 3.5))
            path.addLine(to: CGPoint(x: edge + 3, y: y + direction * 6.5))
        }
        CrispVector.replacePath(of: sparks, with: path)
    }

    /// Called before consuming events so a fresh rally can celebrate 20 again.
    func prepare(returns: Int) {
        if returns < lastReturns { reset() }
        lastReturns = returns
    }

    func celebrate(returns: Int, earnedSave: Bool, time: Double) {
        guard returns > 0, returns > lastMilestone else { return }
        lastMilestone = returns
        began = time
        count.text = "\(returns)!"
        caption.text = earnedSave ? "SAVE READY" : (returns >= 60 ? "INCREDIBLE" : "ON FIRE")
        previousPlayerFrame = nil
        fitCount()
    }

    private func fitCount() {
        count.setScale(1)
        count.fontSize = 18
        if count.frame.width > leftWidth - 6 {
            count.fontSize *= (leftWidth - 6) / count.frame.width
        }
        caption.fontSize = 9
        if caption.frame.width > rightWidth { caption.fontSize *= rightWidth / caption.frame.width }
    }

    func reset() {
        began = -.infinity
        lastMilestone = 0
        lastReturns = 0
        milestone.isHidden = true
    }

    /// Returns whether the milestone currently replaces the ordinary score text.
    func render(state: GameState, time: Double, reduceMotion: Bool) -> Bool {
        isHidden = !state.mode.isBossRally || state.phase == .blackout || state.phase == .results
        let amount = max(0, state.consecutivePlayerReturns) % GameTuning.earnedRecoveryReturnInterval
        if displayedProgress != amount {
            let path = CGMutablePath()
            if amount > 0 {
                path.addArc(center: .zero, radius: 4.5, startAngle: .pi / 2,
                            endAngle: .pi / 2 - CGFloat(amount) / CGFloat(GameTuning.earnedRecoveryReturnInterval) * 2 * .pi,
                            clockwise: true)
            }
            CrispVector.replacePath(of: progress, with: path)
            displayedProgress = amount
        }
        let hasSave = state.recoveriesRemaining > 0
        if displayedSave != hasSave {
            save.strokeColor = hasSave ? Neon.lime : Neon.white.withAlphaComponent(0.28)
            save.fillColor = hasSave ? Neon.lime : .clear
            displayedSave = hasSave
        }
        let age = time - began
        let active = !isHidden && state.phase == .playing && !state.isPaused && state.resumeCountdown <= 0
            && age >= 0 && age < duration
        milestone.isHidden = !active
        track.isHidden = active
        progress.isHidden = active || amount == 0
        save.isHidden = active
        savePlus.isHidden = active || !hasSave
        guard active else { return false }
        if reduceMotion {
            // Same information and duration, without motion, flashes or spark accents.
            count.setScale(1)
            count.position = countAnchor
            milestone.alpha = 1
            sparks.isHidden = true
        } else {
            // A single modest overshoot settles in 0.22s; no SKActions, emitter,
            // shader or additional allocation is needed when another milestone fires.
            let scale: Double
            if age < 0.10 { scale = 0.82 + 0.28 * age / 0.10 }
            else if age < 0.22 { scale = 1.10 - 0.10 * (age - 0.10) / 0.12 }
            else { scale = 1 }
            count.setScale(scale)
            milestone.alpha = age < 1.08 ? 1 : max(0, (duration - age) / 0.22)
            sparks.isHidden = age >= 0.42
            sparks.alpha = max(0, 1 - age / 0.42)
        }
        return true
    }
}
