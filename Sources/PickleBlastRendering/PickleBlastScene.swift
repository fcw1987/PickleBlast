import Foundation
import PickleBlastCore
import SpriteKit

/// Presentation only: the frame callback belongs to the session, which advances the pure core.
public final class PickleBlastScene: SKScene {
    public var onFrame: ((TimeInterval) -> Void)?
    public var debugEnabled = false
    /// Accessibility changes decoration only; authoritative flight and arrival stay continuous.
    public var reduceMotion = false
    public private(set) var courtProjection: CourtProjection
    private var safeInsets: (top: CGFloat, bottom: CGFloat, leading: CGFloat, trailing: CGFloat) = (28, 8, 0, 0)
    private let tuning: GameTuning
    private let textures: TextureLibrary
    #if DEBUG
    public var debugTextureLibraryForLifetimeProbe: AnyObject { textures }
    public var debugLoadedCharacterAtlases: [String] { textures.debugLoadedCharacterAtlases }
    #endif
    private let world = SKNode()
    private let background: SKSpriteNode
    private let systemClockBacking = SKShapeNode()
    private let court: NightArenaCourt
    private let playerGround = SKShapeNode(ellipseOf: CGSize(width: 21, height: 3.6))
    private let bossGround = SKShapeNode(ellipseOf: CGSize(width: 16, height: 2.8))
    private let player: CharacterNode
    private let boss: CharacterNode
    private let bossCue = SKShapeNode(circleOfRadius: 14)
    private var requestedBossIdentity: String?
    private let ball: SKSpriteNode
    private let shotTrail = SKShapeNode()
    private let shotRim = SKShapeNode(circleOfRadius: 5.5)
    private let lobShadow = SKShapeNode(ellipseOf: CGSize(width: 10, height: 4))
    private let lobLanding = SKShapeNode()
    private let score = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let opponentScore = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let combo = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let rallyMomentum = RallyMomentumHUD()
    private var comboUntil = 0.0
    private var comboPoints = 0
    private let message = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let submessage = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
    private let hud = SKNode()
    private let hudBacking = SKShapeNode()
    private let hudAccent = SKShapeNode()
    private let opponentAccent = SKShapeNode()
    private let hudBevel = SKShapeNode()
    private let playerIdentity = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let opponentIdentity = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private var lastHUDIdentity: BossID?
    private let celebrationLayer = SKNode()
    private var hearts: [SKSpriteNode] = []
    private var targetNodes: [Int: TargetNode] = [:]
    private var cascadeNodes: [SKSpriteNode] = []
    private var effects: [ImpactRing] = []
    private var nextEffect = 0
    private var pulseUntil: Double = 0
    private var previousSimulationTime: Double?
    private var visualTime = 0.0
    private var lastScore: Int?
    private var lastPlayerRallyPoints: Int?
    private var lastOpponentRallyPoints: Int?
    private var lastHUDMode: GameMode?
    private var lastLives: Int?
    private var lastMessage = ""
    private var transientMessage = ""
    private var transientUntil: Double = 0
    private var lastFrameDelta: Double = 0
    private let clearEffect = SKSpriteNode()
    private var clearEffectBegan: Double = -.infinity
    private var clearEffectPrefix = "effectWave"
    #if DEBUG
    private let debugLayer = SKNode()
    private let debugShape = SKShapeNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo")
    #endif

    public init(size: CGSize, tuning: GameTuning = GameTuning(), textureLibrary: TextureLibrary = TextureLibrary()) {
        self.tuning = tuning
        self.textures = textureLibrary
        self.courtProjection = CourtProjection(viewportWidth: size.width, viewportHeight: size.height)
        self.background = SKSpriteNode(texture: textureLibrary.supporting("backgroundArena"))
        self.court = NightArenaCourt(material: textureLibrary.supporting("courtSlateB3"))
        self.player = CharacterNode(frontFacing: false, textures: textureLibrary, tuning: tuning)
        self.boss = CharacterNode(frontFacing: true, textures: textureLibrary, tuning: tuning)
        self.ball = SKSpriteNode(texture: textureLibrary.ball)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Neon.black
        anchorPoint = .zero
        addChild(world)
        background.name = "decorativeBackground"
        background.zPosition = -10
        background.alpha = 1
        world.addChild(background)
        // The native watchOS clock overlays the full-display scene. Keep its
        // small safe-area region dark even when the authored moon sits behind it.
        systemClockBacking.name = "systemClockBacking"
        systemClockBacking.zPosition = -5
        systemClockBacking.fillColor = SKColor(white: 0, alpha: 0.96)
        systemClockBacking.strokeColor = .clear
        systemClockBacking.lineWidth = 0
        world.addChild(systemClockBacking)
        world.addChild(court)
        buildCourt()
        for (node, name, color) in [(playerGround, "playerGrounding", Neon.cyan),
                                     (bossGround, "bossGrounding", Neon.magenta)] {
            node.name = name
            node.zPosition = 0.5
            node.fillColor = SKColor(white: 0, alpha: 0.58)
            node.strokeColor = color.withAlphaComponent(0.24)
            node.lineWidth = 0.55
            CrispVector.prepare(node)
            world.addChild(node)
        }
        world.addChild(player)
        world.addChild(boss)
        bossCue.name = "bossSpecialCue"
        bossCue.zPosition = 3.5
        bossCue.lineWidth = 1.8
        bossCue.fillColor = .clear
        bossCue.isHidden = true
        CrispVector.prepare(bossCue)
        world.addChild(bossCue)
        ball.name = "gameplayBall"
        world.addChild(ball)
        for (node, name, order) in [(shotTrail, "shotTrail", 9.5),
                                    (shotRim, "shotRim", 9.8),
                                    (lobShadow, "lobGroundShadow", 3.7),
                                    (lobLanding, "lobLandingCue", 3.6)] {
            node.name = name
            node.zPosition = order
            node.lineWidth = 1.2
            node.fillColor = .clear
            node.isHidden = true
            CrispVector.prepare(node)
            world.addChild(node)
        }
        lobShadow.strokeColor = Neon.white.withAlphaComponent(0.65)
        lobLanding.strokeColor = Neon.cyan.withAlphaComponent(0.65)
        // Ball stays above the approved character so center blocks never hide its departure.
        // Effects remain below both; no artwork controls game geometry.
        player.zPosition = 9
        boss.zPosition = 4
        ball.zPosition = 10
        // Render replaces this initial size with a readable projected billboard;
        // presentation size never changes the collision radius.
        ball.size = CGSize(width: tuning.ballRadius * 3.2 / textures.manifest.supporting["ball"]!.visibleFraction, height: tuning.ballRadius * 3.2 / textures.manifest.supporting["ball"]!.visibleFraction)
        addChild(hud)
        hud.zPosition = 20
        hudBacking.name = "hudScorePanels"
        hudBacking.zPosition = -2
        hudBacking.fillColor = SKColor(red: 0.055, green: 0.12, blue: 0.18, alpha: 0.95)
        hudBacking.strokeColor = Neon.cyan.withAlphaComponent(0.32)
        hudBacking.lineWidth = 0.5
        hud.addChild(hudBacking)
        for (node, color, name) in [(hudAccent, Neon.lime, "hudPlayerAccent"),
                                     (opponentAccent, Neon.magenta, "hudOpponentAccent")] {
            node.name = name
            node.zPosition = -1
            node.fillColor = color
            node.strokeColor = .clear
            hud.addChild(node)
        }
        for (label, color, name, alignment) in [
            (playerIdentity, Neon.lime, "hudPlayerIdentity", SKLabelHorizontalAlignmentMode.left),
            (opponentIdentity, Neon.magenta, "hudOpponentIdentity", SKLabelHorizontalAlignmentMode.right)] {
            label.name = name
            label.fontColor = color
            label.fontSize = 6.5
            label.horizontalAlignmentMode = alignment
            label.verticalAlignmentMode = .center
            hud.addChild(label)
        }
        hudBevel.name = "hudPlaqueBevel"
        hudBevel.strokeColor = Neon.white.withAlphaComponent(0.16)
        hudBevel.lineWidth = 0.5
        hud.addChild(hudBevel)
        score.horizontalAlignmentMode = .left
        score.verticalAlignmentMode = .center
        score.fontSize = 15
        score.fontColor = Neon.white
        score.name = "hudPlayerScore"
        hud.addChild(score)
        opponentScore.horizontalAlignmentMode = .right
        opponentScore.verticalAlignmentMode = .center
        opponentScore.fontSize = 12
        opponentScore.fontColor = Neon.white
        opponentScore.name = "hudOpponentScore"
        opponentScore.isHidden = true
        hud.addChild(opponentScore)
        combo.name = "comboIndicator"
        combo.fontSize = 10
        combo.fontColor = Neon.lime
        combo.horizontalAlignmentMode = .center
        combo.verticalAlignmentMode = .center
        combo.isHidden = true
        hud.addChild(combo)
        hud.addChild(rallyMomentum)
        for _ in 0..<tuning.initialLives {
            let heart = SKSpriteNode(texture: textures.supporting("uiHeartFull"))
            heart.size = CGSize(width: 15, height: 15)
            hud.addChild(heart)
            hearts.append(heart)
        }
        for label in [message, submessage] {
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.zPosition = 21
            addChild(label)
        }
        message.fontColor = Neon.lime
        message.fontSize = 16
        submessage.fontColor = Neon.white
        submessage.fontSize = 10
        clearEffect.zPosition = 22
        clearEffect.isHidden = true
        addChild(clearEffect)
        celebrationLayer.zPosition = 30
        addChild(celebrationLayer)
        // One allocation pass; every celebration reuses the same nodes and texture.
        for _ in 0..<min(256, max(0, tuning.celebrationCapacity)) {
            let node = SKSpriteNode(texture: textureLibrary.ball)
            node.isHidden = true
            celebrationLayer.addChild(node)
            cascadeNodes.append(node)
        }
        for _ in 0..<12 {
            let effect = ImpactRing(textures: textures)
            world.addChild(effect.node)
            effects.append(effect)
        }
        #if DEBUG
        debugLayer.zPosition = 50
        world.addChild(debugLayer)
        debugShape.lineWidth = 0.8
        debugShape.strokeColor = Neon.orange
        CrispVector.prepare(debugShape)
        debugLayer.addChild(debugShape)
        debugLabel.fontSize = 7
        debugLabel.fontColor = Neon.white
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .bottom
        debugLabel.numberOfLines = 0
        debugLabel.zPosition = 51
        addChild(debugLabel)
        #endif
        layoutScene()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("Use init(size:tuning:textureLibrary:)") }

    public override func update(_ currentTime: TimeInterval) { onFrame?(currentTime) }

    public override func didChangeSize(_ oldSize: CGSize) { layoutScene() }

    /// SwiftUI touch locations use a top-left origin; only X is needed for horizontal input.
    public func courtX(forViewX x: CGFloat) -> Double {
        courtProjection.courtX(forScreenX: x, atLogicalY: tuning.playerY + tuning.ballRadius)
    }

    public func render(state: GameState, events: [GameEvent], delta: Double) {
        if let previousSimulationTime, state.simulationTime < previousSimulationTime {
            // The session may reuse a scene for Play Again. Do not carry visual deadlines over.
            comboUntil = 0
            comboPoints = 0
            transientUntil = 0
            pulseUntil = 0
            visualTime = 0
            clearEffectBegan = -.infinity
            rallyMomentum.reset()
            player.reset()
            boss.release()
            requestedBossIdentity = nil
            for node in targetNodes.values { node.resetFeedback() }
            for index in effects.indices { effects[index].reset() }
        }
        lastFrameDelta = delta
        let frozen = state.isPaused || state.resumeCountdown > 0
        let visualDelta = frozen ? 0 : max(0, state.simulationTime - (previousSimulationTime ?? state.simulationTime))
        visualTime += visualDelta
        if let lastHUDMode, lastHUDMode != state.mode { rallyMomentum.reset() }
        rallyMomentum.prepare(returns: state.consecutivePlayerReturns)
        player.advance(x: state.playerX, planeY: tuning.playerY + tuning.ballRadius,
                       delta: visualDelta, frozen: frozen,
                       prediction: prediction(state: state, x: state.playerX, plane: tuning.playerY + tuning.ballRadius, front: false), projection: courtProjection)
        boss.isHidden = state.boss == nil
        if let bossState = state.boss {
            if requestedBossIdentity != bossState.id.rawValue {
                boss.selectBoss(bossState.id.rawValue)
                requestedBossIdentity = bossState.id.rawValue
            }
            let configuration = tuning.bossConfiguration(for: bossState.id)
            boss.advance(x: bossState.x, planeY: configuration.y - tuning.ballRadius,
                         delta: visualDelta, frozen: frozen,
                         prediction: prediction(state: state, x: bossState.x, plane: configuration.y - tuning.ballRadius, front: true), projection: courtProjection)
        }
        renderBossCue(state.boss, phase: state.phase)
        // Resolve impact positions before removing destroyed target nodes.
        consume(events, state: state)
        // Contact registration translates the complete sprite inside its node.
        // Grounding follows that visible foot anchor, including a reaching pose;
        // it does not move, retime or add children to the approved character.
        positionGrounding(playerGround, beneath: player, offset: -1.2)
        positionGrounding(bossGround, beneath: boss, offset: -0.8)
        bossGround.isHidden = boss.isHidden
        syncTargets(state.targets)
        world.isHidden = state.phase == .blackout
        hud.isHidden = state.phase == .blackout
        message.isHidden = state.phase == .blackout
        submessage.isHidden = state.phase == .blackout
        let isBossRally = state.mode.isBossRally
        if lastHUDMode != state.mode {
            score.fontSize = isBossRally ? 16 : 15
            opponentScore.fontSize = 16
            opponentScore.isHidden = !isBossRally
            for heart in hearts { heart.isHidden = isBossRally }
            lastScore = nil
            lastPlayerRallyPoints = nil
            lastOpponentRallyPoints = nil
            playerIdentity.text = isBossRally ? "YOU" : "POINTS"
            opponentIdentity.text = isBossRally ? state.bossID.rawValue.uppercased() : "LIVES"
            lastHUDIdentity = state.bossID
            lastHUDMode = state.mode
            layoutScoreDetails(isBossRally: isBossRally)
        }
        if isBossRally {
            if lastHUDIdentity != state.bossID {
                opponentIdentity.text = state.bossID.rawValue.uppercased()
                lastHUDIdentity = state.bossID
            }
            if lastPlayerRallyPoints != state.playerRallyPoints {
                score.text = String(state.playerRallyPoints)
                lastPlayerRallyPoints = state.playerRallyPoints
            }
            if lastOpponentRallyPoints != state.opponentRallyPoints {
                opponentScore.text = String(state.opponentRallyPoints)
                lastOpponentRallyPoints = state.opponentRallyPoints
            }
            layoutScoreDetails(isBossRally: true)
        } else if lastScore != state.score {
            score.text = String(state.score)
            lastScore = state.score
            layoutScoreDetails(isBossRally: false)
        }
        if lastLives != state.lives {
            for (index, heart) in hearts.enumerated() {
                let full = index < state.lives
                heart.texture = textures.supporting(full ? "uiHeartFull" : "uiHeartEmpty")
            }
            lastLives = state.lives
        }
        renderBall(state)
        court.markingAlpha = visualTime < pulseUntil ? 0.6 + 0.4 * sin((pulseUntil - visualTime) * 32) : 1
        for index in effects.indices { effects[index].update(time: visualTime, animated: !reduceMotion && !isBossRally) }
        let clearProgress = (visualTime - clearEffectBegan) / 0.8
        clearEffect.isHidden = clearProgress < 0 || clearProgress >= 1 || state.phase == .blackout
        if !clearEffect.isHidden { clearEffect.texture = textures.supporting(String(format: "%@%02d", clearEffectPrefix, min(8, Int(clearProgress * 8) + 1))) }
        renderCascade(state.celebration, visible: state.phase == .celebration)
        combo.isHidden = isBossRally || state.targetChain < 2 || visualTime >= comboUntil || state.phase != .playing
        let milestoneVisible = rallyMomentum.render(state: state, time: visualTime, reduceMotion: reduceMotion)
        playerIdentity.isHidden = milestoneVisible
        opponentIdentity.isHidden = milestoneVisible
        score.isHidden = milestoneVisible
        opponentScore.isHidden = !isBossRally || milestoneVisible
        renderMessage(state)
        #if DEBUG
        renderDebug(state)
        #endif
        previousSimulationTime = state.simulationTime
    }

    /// Insets come from an outer SwiftUI geometry reader before the game surface
    /// extends under system chrome. Scenery and its clock backing may enter that area.
    public func setViewport(_ viewport: CGSize, safeTop: CGFloat, safeBottom: CGFloat,
                            safeLeading: CGFloat = 0, safeTrailing: CGFloat = 0) {
        let next = (safeTop, safeBottom, safeLeading, safeTrailing)
        guard size != viewport || safeInsets != next else { return }
        safeInsets = next
        if size != viewport { size = viewport } else { layoutScene() }
    }

    private func layoutScene() {
        courtProjection = CourtProjection(viewportWidth: size.width, viewportHeight: size.height,
                                          safeTop: safeInsets.top, safeBottom: safeInsets.bottom,
                                          safeLeading: safeInsets.leading, safeTrailing: safeInsets.trailing)
        // Every world node is positioned in screen points through one projector.
        // Sprite artwork remains square; no nonuniform parent scaling is used.
        world.setScale(1)
        world.position = .zero
        let art = textures.manifest.supporting["backgroundArena"]!
        let visualCenterX = CGFloat(courtProjection.centerX)
        let requiredWidth = 2 * max(visualCenterX, size.width - visualCenterX)
        let scale = max(requiredWidth / art.pixelSize[0], size.height / art.pixelSize[1])
        background.size = CGSize(width: art.pixelSize[0] * scale, height: art.pixelSize[1] * scale)
        background.position = CGPoint(x: visualCenterX, y: size.height / 2)
        let clockHeight = min(27, max(0, safeInsets.top - 4))
        let clockWidth = min(64, max(1, size.width * 0.37))
        let clockPanel = CGRect(x: max(0, size.width - max(4, safeInsets.trailing + 4) - clockWidth),
                                y: size.height - safeInsets.top / 2 - clockHeight / 2,
                                width: clockWidth, height: clockHeight)
        systemClockBacking.path = CGPath(roundedRect: clockPanel, cornerWidth: 8, cornerHeight: 8, transform: nil)
        systemClockBacking.isHidden = clockHeight == 0
        buildCourt()
        let groundingScale = sqrt(size.width / 211)
        CrispVector.setVisualScale(groundingScale, on: playerGround)
        CrispVector.setVisualScale(groundingScale, on: bossGround)
        // Two independent plaques leave the arena and the 44pt Pause target open.
        // Paths change only on viewport changes; no blur, filters or live shadows.
        let panels = scorePanelFrames()
        let plates = CGMutablePath()
        for panel in [panels.left, panels.right] {
            plates.addRoundedRect(in: panel, cornerWidth: 4, cornerHeight: 4)
        }
        hudBacking.path = plates
        let bevel = CGMutablePath()
        for panel in [panels.left, panels.right] {
            bevel.move(to: CGPoint(x: panel.minX + 5, y: panel.maxY - 1))
            bevel.addLine(to: CGPoint(x: panel.maxX - 5, y: panel.maxY - 1))
        }
        hudBevel.path = bevel
        for (node, panel, right) in [(hudAccent, panels.left, false), (opponentAccent, panels.right, true)] {
            let x = right ? panel.maxX - 21 : panel.minX + 5
            node.path = CGPath(roundedRect: CGRect(x: x, y: panel.minY + 2, width: 16, height: 1),
                               cornerWidth: 0.5, cornerHeight: 0.5, transform: nil)
        }
        for effect in effects { effect.reproject(courtProjection) }
        let safeX = max(14, size.width * 0.08)
        score.position = CGPoint(x: safeInsets.leading + safeX, y: courtProjection.hudY)
        opponentScore.position = CGPoint(x: size.width - safeInsets.trailing - safeX, y: courtProjection.hudY)
        for (index, heart) in hearts.enumerated() {
            heart.position = CGPoint(x: size.width - safeInsets.trailing - safeX - CGFloat(hearts.count - 1 - index) * 14,
                                     y: courtProjection.hudY)
        }
        layoutScoreDetails(isBossRally: lastHUDMode?.isBossRally ?? false)
        clearEffect.position = CGPoint(x: size.width / 2, y: (courtProjection.nearY + courtProjection.farY) / 2)
        clearEffect.size = CGSize(width: size.width * 0.65, height: size.width * 0.65)
        message.position = CGPoint(x: size.width / 2, y: (courtProjection.nearY + courtProjection.farY) / 2)
        submessage.position = CGPoint(x: message.position.x, y: message.position.y - 19)
        message.fontSize = min(16, size.width / 11)
        #if DEBUG
        debugLabel.position = CGPoint(x: 8, y: 2)
        #endif
    }

    private func scorePanelFrames() -> (left: CGRect, right: CGRect) {
        let center = CGFloat(courtProjection.centerX)
        let left = safeInsets.leading + 6
        let right = size.width - safeInsets.trailing - 6
        let y = CGFloat(courtProjection.hudY) - 5.5
        return (CGRect(x: left, y: y, width: max(1, center - 27 - left), height: 19.5),
                CGRect(x: center + 27, y: y, width: max(1, right - center - 27), height: 19.5))
    }

    private func layoutScoreDetails(isBossRally: Bool) {
        let panels = scorePanelFrames()
        score.position = CGPoint(x: panels.left.minX + 8, y: courtProjection.hudY + 2)
        opponentScore.position = CGPoint(x: panels.right.maxX - 8, y: courtProjection.hudY + 2)
        playerIdentity.position = CGPoint(x: score.position.x, y: courtProjection.hudY + 12)
        opponentIdentity.position = CGPoint(x: opponentScore.position.x, y: courtProjection.hudY + 12)
        opponentIdentity.fontSize = 6.5
        if opponentIdentity.frame.width > panels.right.width - 16 {
            opponentIdentity.fontSize *= (panels.right.width - 16) / opponentIdentity.frame.width
        }
        if !isBossRally {
            score.fontSize = 15
            if score.frame.width > panels.left.width - 16 {
                score.fontSize *= (panels.left.width - 16) / score.frame.width
            }
        }
        for (index, heart) in hearts.enumerated() {
            heart.size = CGSize(width: 12, height: 12)
            heart.position = CGPoint(x: panels.right.maxX - 9 - CGFloat(hearts.count - 1 - index) * 12,
                                     y: courtProjection.hudY)
        }
        combo.horizontalAlignmentMode = .center
        combo.fontSize = 9
        combo.position = CGPoint(x: size.width / 2, y: courtProjection.hudY - 13)
        rallyMomentum.layout(playerScore: score.frame, opponentScore: opponentScore.frame,
                             y: courtProjection.hudY, centerX: courtProjection.centerX)
    }

    private func buildCourt() {
        court.layout(projection: courtProjection)
    }

    private func positionGrounding(_ grounding: SKShapeNode, beneath character: CharacterNode, offset: CGFloat) {
        let registration = character.children.first?.position ?? .zero
        grounding.position = CGPoint(x: character.position.x + registration.x,
                                     y: character.position.y + registration.y + offset)
    }

    private func syncTargets(_ targets: [TargetState]) {
        for (id, node) in targetNodes where !targets.contains(where: { $0.id == id }) {
            node.removeFromParent()
            targetNodes.removeValue(forKey: id)
        }
        for target in targets {
            if targetNodes[target.id] == nil {
                let node = TargetNode(target: target, textures: textures)
                node.zPosition = 3
                world.addChild(node)
                targetNodes[target.id] = node
            }
            targetNodes[target.id]?.apply(target, projection: courtProjection)
            targetNodes[target.id]?.update(time: visualTime, reduceMotion: reduceMotion)
        }
    }

    private func consume(_ events: [GameEvent], state: GameState) {
        guard !events.isEmpty else { return }
        let bossConfiguration = tuning.bossConfiguration(for: state.bossID)
        let poweredContact = events.contains {
            if case .bossPowerContact = $0 { return true }
            return false
        }
        for event in events {
            switch event {
            case let .paddleContact(x, side, centered):
                let clip: String
                switch side { case .forehand: clip = "forehand"; case .backhand: clip = "backhand"; case .block: clip = "block" }
                player.contact(clip: clip, offset: x - state.playerX, lift: 0)
                impact(at: Vector2(x: x, y: tuning.playerY + tuning.ballRadius), color: centered ? Neon.white : Neon.lime,
                       time: visualTime)
            case let .targetHit(id, _, destroyed, points):
                if visualTime >= comboUntil { comboPoints = 0 }
                comboPoints += points
                if state.targetChain >= 2 {
                    combo.text = "×\(tuning.comboMultiplier(for: state.targetChain))  +\(comboPoints)"
                    comboUntil = visualTime + 0.7
                }
                if let node = targetNodes[id] {
                    node.flash(at: visualTime)
                    if destroyed {
                        impact(at: node.logicalPosition, color: Neon.lime, time: visualTime, diameter: 12)
                    }
                }
            case let .targetCleaned(id, _, _):
                if let node = targetNodes[id] {
                    impact(at: node.logicalPosition, color: Neon.lime, time: visualTime, diameter: 12)
                }
            case .ballRecovered:
                show("BALL BACK", until: visualTime + tuning.recoveryReadyDuration)
            case let .rallyMilestone(returns):
                if state.mode.isBossRally {
                    rallyMomentum.celebrate(returns: returns, earnedSave: events.contains(.recoveryEarned), time: visualTime)
                }
            case .recoveryEarned:
                break // The simultaneous milestone presents the earned save.
            case let .comboChanged(chain, _):
                if chain == 0 { comboPoints = 0; comboUntil = 0 }
            case .waveCleared:
                clearEffectBegan = visualTime; clearEffectPrefix = "effectWave"
                pulseUntil = visualTime + 0.4
                show("WAVE CLEAR", until: visualTime + 0.7)
            case .bossIncoming:
                show(bossConfiguration.name.uppercased(), until: visualTime + tuning.readyDuration)
            case let .bossContact(x):
                let offset = x - (state.boss?.x ?? CourtGeometry.centerX)
                let clip = abs(offset) < 0.3 ? "block" : (offset < 0 ? "forehand" : "backhand")
                let visibleBall = state.ball?.position
                boss.contact(clip: clip, offset: (visibleBall?.x ?? x) - (state.boss?.x ?? CourtGeometry.centerX),
                             lift: (visibleBall?.y ?? bossConfiguration.y - tuning.ballRadius) - bossConfiguration.y + tuning.ballRadius)
                let shotColor: SKColor
                if poweredContact { shotColor = Neon.orange }
                else if state.rallyShot?.kind == .soft { shotColor = Neon.cyan }
                else if state.rallyShot?.kind == .lob { shotColor = Neon.white }
                else if state.mode.isBossRally {
                    switch state.boss?.lastShotPurpose {
                    case .some(.control), .none: shotColor = Neon.magenta
                    case .some(.placement): shotColor = Neon.cyan
                    case .some(.changeOfPace): shotColor = Neon.lime
                    case .some(.attack): shotColor = Neon.orange
                    }
                } else { shotColor = Neon.magenta }
                impact(at: Vector2(x: x, y: bossConfiguration.y - tuning.ballRadius),
                       color: shotColor, time: visualTime, tint: state.mode != .arcade)
            case .bossPowerTelegraph, .bossPowerContact, .bossPoachCommitment, .bossPoachRecovery,
                 .rallyShotPrepared, .rallyShotLaunched:
                // Preparation, direction and flight cues read the same committed
                // state as gameplay; active contact never carries a large label.
                break
            case let .bossPoint(points):
                if state.mode.isBossRally {
                    pulseUntil = visualTime + 0.35
                    show("YOUR POINT", until: visualTime + tuning.readyDuration)
                } else {
                    show("POINT \(points)/\(bossConfiguration.pointsToWin)", until: visualTime + tuning.readyDuration)
                }
            case .opponentPoint:
                pulseUntil = visualTime + 0.35
                show("BOSS POINT", until: visualTime + tuning.readyDuration)
            case .bossDefeated:
                clearEffectBegan = visualTime; clearEffectPrefix = "effectBoss"
                pulseUntil = visualTime + 0.6
                show("\(bossConfiguration.name.uppercased()) DOWN", until: visualTime + 0.9)
            case .lifeLost:
                show("MISSED", until: visualTime + 0.6)
                impact(at: Vector2(x: state.playerX, y: tuning.playerY), color: Neon.orange,
                       time: visualTime)
            case let .runEnded(won, _):
                show(won ? "RUN COMPLETE" : "GAME OVER", until: visualTime + 2)
            case .phaseChanged, .wallContact, .bossMatchEnded: break
            }
        }
    }

    private func show(_ text: String, until: Double) {
        transientMessage = text
        transientUntil = until
    }

    private func renderMessage(_ state: GameState) {
        let title: String
        let subtitle: String
        if state.isPaused {
            title = ""; subtitle = ""
        } else if state.resumeCountdown > 0 {
            title = "READY"; subtitle = String(Int(ceil(state.resumeCountdown)))
        } else if visualTime < transientUntil {
            title = transientMessage; subtitle = ""
        } else if state.phase == .ready {
            title = "READY"
            let configuration = tuning.bossConfiguration(for: state.bossID)
            if state.mode.isBossRally {
                subtitle = "\(configuration.name.uppercased()) · FIRST TO \(configuration.pointsToWin)"
            } else {
                subtitle = state.stage.isBoss ? "\(configuration.name.uppercased()) · \(state.bossPoints)/\(configuration.pointsToWin)" : "WAVE \(state.waveNumber)"
            }
        } else {
            title = ""; subtitle = ""
        }
        if title != lastMessage { message.text = title; lastMessage = title }
        if submessage.text != subtitle { submessage.text = subtitle }
        message.fontColor = state.stage.isBoss ? Neon.magenta : Neon.lime
    }

    private func renderBossCue(_ bossState: BossState?, phase: GamePhase) {
        guard let bossState, phase == .playing,
              bossState.specialPhase != .idle else {
            bossCue.isHidden = true
            return
        }
        let configuration = tuning.bossConfiguration(for: bossState.id)
        let point = courtProjection.screenPoint(for: Vector2(x: bossState.x,
                                                              y: configuration.y - tuning.ballRadius))
        bossCue.position = CGPoint(x: point.x, y: point.y)
        CrispVector.setVisualScale(sqrt(size.width / 211), on: bossCue)
        switch bossState.specialPhase {
        case .powerWindup:
            bossCue.strokeColor = Neon.orange
            bossCue.alpha = 0.8
        case .poachCommitment:
            bossCue.strokeColor = Neon.magenta
            bossCue.alpha = 0.8
        case .softWindup:
            bossCue.strokeColor = Neon.cyan
            bossCue.alpha = 0.8
        case .lobWindup:
            bossCue.strokeColor = Neon.white
            bossCue.alpha = 0.8
        case .powerRecovery, .poachRecovery, .softRecovery, .lobRecovery:
            bossCue.isHidden = true
            return
        case .idle: break
        }
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -14, y: -14, width: 28, height: 28))
        if bossState.specialPhase == .poachCommitment, let side = bossState.committedSide {
            // The arrow follows the core's actual commitment, never the player's
            // later input or a renderer prediction.
            let direction = side == .left ? -1.0 : 1.0
            path.move(to: CGPoint(x: direction * 3, y: 0))
            path.addLine(to: CGPoint(x: direction * 11, y: 0))
            path.move(to: CGPoint(x: direction * 7, y: 4))
            path.addLine(to: CGPoint(x: direction * 11, y: 0))
            path.addLine(to: CGPoint(x: direction * 7, y: -4))
        } else if bossState.specialPhase == .softWindup {
            path.move(to: CGPoint(x: -7, y: -4))
            path.addLine(to: CGPoint(x: 7, y: -4))
        } else if bossState.specialPhase == .lobWindup {
            path.move(to: CGPoint(x: -5, y: 0))
            path.addQuadCurve(to: CGPoint(x: 5, y: 0), control: CGPoint(x: 0, y: 12))
        }
        CrispVector.replacePath(of: bossCue, with: path)
        bossCue.isHidden = false
    }

    private func renderBall(_ state: GameState) {
        ball.isHidden = state.ball == nil || state.phase == .celebration
        for node in [shotTrail, shotRim, lobShadow, lobLanding] { node.isHidden = true }
        guard let ballState = state.ball else { return }
        let ground = courtProjection.screenPoint(for: ballState.position)
        let diameter = 2 * LobScreenProjection.ballRadius(at: ballState.position, projection: courtProjection)
        let side = diameter / textures.manifest.supporting["ball"]!.visibleFraction
        ball.size = CGSize(width: side, height: side)
        ball.zRotation = reduceMotion ? 0 : CGFloat(visualTime * 3.0)
        var visible = ground
        let activeShot = state.mode.isBossRally && state.phase == .playing ? state.rallyShot : nil
        if let flight = activeShot?.lobFlight {
            visible = LobScreenProjection.ballPoint(ground: ground, flight: flight,
                projection: courtProjection, radius: diameter / 2)
            lobShadow.position = CGPoint(x: ground.x, y: ground.y)
            lobShadow.alpha = 0.55 + 0.25 * (1 - flight.heightFraction)
            CrispVector.setVisualScale(sqrt(size.width / 211), on: lobShadow)
            lobShadow.isHidden = false
            let destination = courtProjection.screenPoint(for: flight.destination)
            lobLanding.position = CGPoint(x: destination.x, y: destination.y)
            let landingPath = CGMutablePath()
            landingPath.move(to: CGPoint(x: -3, y: 0))
            landingPath.addLine(to: CGPoint(x: 3, y: 0))
            landingPath.move(to: CGPoint(x: 0, y: -3))
            landingPath.addLine(to: CGPoint(x: 0, y: 3))
            CrispVector.replacePath(of: lobLanding, with: landingPath)
            lobLanding.isHidden = false
        }
        ball.position = CGPoint(x: visible.x, y: visible.y)
        guard let kind = activeShot?.kind, kind != .normal else { return }
        let color = kind == .power ? Neon.orange : (kind == .soft ? Neon.cyan : Neon.white)
        shotRim.strokeColor = color
        shotRim.position = ball.position
        shotRim.alpha = 0.8
        CrispVector.setVisualScale(diameter / 10, on: shotRim)
        shotRim.isHidden = kind == .lob
        guard !reduceMotion, kind == .power || kind == .soft else { return }
        // A fixed short stroke samples authoritative velocity. It does not keep
        // another ball, run an action, or retain a previous shot's path.
        let behind = courtProjection.screenPoint(for: ballState.position - ballState.velocity * 0.025)
        let direction = behind - ground
        guard direction.length > 0.0001 else { return }
        let length = kind == .power ? 13.0 : 5.0
        let end = visible + direction * (length / direction.length)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: visible.x + direction.x / direction.length * diameter * 0.45,
                             y: visible.y + direction.y / direction.length * diameter * 0.45))
        path.addLine(to: CGPoint(x: end.x, y: end.y))
        CrispVector.replacePath(of: shotTrail, with: path)
        shotTrail.strokeColor = color
        shotTrail.lineWidth = (kind == .power ? 1.8 : 1.2) * CrispVector.resolution
        shotTrail.alpha = kind == .power ? 0.8 : 0.65
        shotTrail.isHidden = false
    }

    private func renderCascade(_ pool: CelebrationPool, visible: Bool) {
        celebrationLayer.isHidden = !visible
        guard visible else { return }
        for (index, node) in cascadeNodes.enumerated() {
            guard index < pool.particles.count, pool.particles[index].isActive else {
                node.isHidden = true
                continue
            }
            let particle = pool.particles[index]
            node.isHidden = false
            node.position = CGPoint(x: particle.position.x / pool.width * size.width,
                                    y: particle.position.y / pool.height * size.height)
            let diameter = pool.baseRadius * 2 * particle.scale * size.width / pool.width
            node.size = CGSize(width: diameter / textures.manifest.supporting["ball"]!.visibleFraction, height: diameter / textures.manifest.supporting["ball"]!.visibleFraction)
            node.zRotation = particle.rotation
        }
    }

    private func impact(at position: Vector2, color: SKColor, time: Double, image: String? = nil,
                        diameter: Double = 26, tint: Bool = false) {
        guard !effects.isEmpty else { return }
        effects[nextEffect].start(at: position, projection: courtProjection, color: color,
                                  time: time, image: image, diameter: diameter, tint: tint)
        nextEffect = (nextEffect + 1) % effects.count
    }

    #if DEBUG
    private func renderDebug(_ state: GameState) {
        debugLayer.isHidden = !debugEnabled || state.phase == .blackout
        debugLabel.isHidden = !debugEnabled || state.phase == .blackout
        guard debugEnabled else { return }
        let path = CGMutablePath()
        func line(_ start: Vector2, _ end: Vector2) {
            path.move(to: screenPoint(start)); path.addLine(to: screenPoint(end))
        }
        func circle(_ center: Vector2, _ radius: Double) {
            for index in 0...32 {
                let angle = Double(index) / 32 * .pi * 2
                let p = screenPoint(Vector2(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
        for boundary in CourtGeometry.boundaryLines { line(boundary.start, boundary.end) }
        line(Vector2(x: state.playerX - tuning.playerHalfWidth, y: tuning.playerY),
             Vector2(x: state.playerX + tuning.playerHalfWidth, y: tuning.playerY))
        for target in state.targets { circle(target.position, target.radius) }
        if let ball = state.ball {
            circle(ball.position, ball.radius)
            line(ball.position, ball.position + ball.velocity * 0.13)
        }
        if let boss = state.boss {
            let configuration = tuning.bossConfiguration(for: boss.id)
            line(Vector2(x: boss.movementTarget, y: configuration.y - 1), Vector2(x: boss.movementTarget, y: configuration.y + 1))
            line(Vector2(x: boss.x - configuration.halfWidth, y: configuration.y), Vector2(x: boss.x + configuration.halfWidth, y: configuration.y))
        }
        CrispVector.replacePath(of: debugShape, with: path)
        debugLabel.text = String(format: "%@ W%d  %.1f ft/s\nC %.2f v%.2f  %.1fms", state.phase.rawValue,
                                 state.waveNumber, state.ball?.speed ?? 0, state.crownInput,
                                 state.crownVelocity, lastFrameDelta * 1000)
    }
    #endif

    private func screenPoint(_ logical: Vector2) -> CGPoint {
        let point = courtProjection.screenPoint(for: logical)
        return CGPoint(x: point.x, y: point.y)
    }

    private static func heartPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -4))
        path.addCurve(to: CGPoint(x: -4.5, y: 1), control1: CGPoint(x: -1.5, y: -2.5), control2: CGPoint(x: -4.5, y: -0.5))
        path.addCurve(to: CGPoint(x: 0, y: 2.5), control1: CGPoint(x: -4.5, y: 5), control2: CGPoint(x: -1, y: 5))
        path.addCurve(to: CGPoint(x: 4.5, y: 1), control1: CGPoint(x: 1, y: 5), control2: CGPoint(x: 4.5, y: 5))
        path.addCurve(to: CGPoint(x: 0, y: -4), control1: CGPoint(x: 4.5, y: -0.5), control2: CGPoint(x: 1.5, y: -2.5))
        path.closeSubpath()
        return path
    }

    private func prediction(state: GameState, x: Double, plane: Double, front: Bool) -> (clip: String, arrival: Double, offset: Double)? {
        guard state.phase == .playing, let ball = state.ball,
              front ? ball.velocity.y > 0 : ball.velocity.y < 0 else { return nil }
        let arrival: Double
        let landing: Double
        if !front, let flight = state.rallyShot?.lobFlight {
            arrival = flight.remainingDuration
            landing = flight.receivingX
        } else {
            arrival = (plane - ball.position.y) / ball.velocity.y
            let span = CourtGeometry.width - 2 * ball.radius
            var folded = (ball.position.x + ball.velocity.x * arrival - ball.radius).truncatingRemainder(dividingBy: 2 * span)
            if folded < 0 { folded += 2 * span }
            landing = ball.radius + (folded <= span ? folded : 2 * span - folded)
        }
        guard arrival >= 0, arrival < 0.4 else { return nil }
        let offset = landing - x
        let bossHalfWidth = tuning.bossConfiguration(for: state.bossID).halfWidth
        guard abs(offset) <= (front ? bossHalfWidth : tuning.playerHalfWidth) + ball.radius else { return nil }
        let clip = abs(offset) <= (front ? 0.3 : tuning.playerHalfWidth * tuning.centeredContactFraction) ? "block" : ((offset < 0) != front ? "backhand" : "forehand")
        return (clip, arrival, offset)
    }

}

private struct ImpactRing {
    let node = SKSpriteNode()
    private let textures: TextureLibrary
    private var began: Double = -.infinity
    private var perfect = false
    private var image: String?
    private var logicalPosition = Vector2.zero
    init(textures: TextureLibrary) {
        self.textures = textures
        node.size = CGSize(width: 26, height: 26)
        node.zPosition = 6
        node.isHidden = true
    }
    mutating func start(at position: Vector2, projection: CourtProjection, color: SKColor,
                        time: Double, image: String?, diameter: Double, tint: Bool) {
        node.size = CGSize(width: diameter, height: diameter)
        node.color = color
        node.colorBlendFactor = tint ? 0.55 : 0
        logicalPosition = position
        reproject(projection)
        perfect = color == Neon.white
        self.image = image
        began = time
    }
    func reproject(_ projection: CourtProjection) {
        let point = projection.screenPoint(for: logicalPosition)
        node.position = CGPoint(x: point.x, y: point.y)
    }
    mutating func reset() { began = -.infinity; node.isHidden = true }
    func update(time: Double, animated: Bool) {
        let progress = (time - began) / 0.22
        node.isHidden = progress < 0 || progress >= 1
        guard !node.isHidden else { return }
        node.texture = textures.supporting(image ?? String(format: perfect ? "effectPerfect%02d" : "effectHit%02d", min(6, Int(progress * 6) + 1)))
        // Arcade's existing six pooled impacts expand then dissolve. No extra
        // nodes or full-screen effect; ball rendering/contact stay independent.
        node.setScale(animated ? CGFloat(0.82 + 0.42 * progress) : 1)
        node.alpha = animated ? CGFloat(1 - progress * progress) : 1
    }
}
