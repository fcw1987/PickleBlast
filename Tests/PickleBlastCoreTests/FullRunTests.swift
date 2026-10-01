import Foundation
import Testing
import PickleBlastCore

/// Integration driver uses only the controls available to a player. It cannot
/// replace positions, clear targets, award points, or bypass phase transitions.
struct AutomaticPlayer {
    private var returns = 0
    private var bossReturns = 0
    private var plannedReturn = -1
    private var plannedAngle = 0.0
    private let touchTransform = CourtTransform(viewportWidth: 211, viewportHeight: 257)

    mutating func observe(_ events: [GameEvent], stage: GameStage) {
        for event in events {
            if case .paddleContact = event {
                returns += 1
                if stage.isBoss { bossReturns += 1 }
            }
        }
    }

    mutating func position(in engine: GameEngine) {
        guard let ball = engine.state.ball, ball.velocity.y < 0,
              engine.state.phase == .playing else { return }
        if !engine.state.stage.isBoss,
           let front = engine.state.targets.map({ $0.position.y - $0.radius - ball.radius }).min(),
           ball.position.y > front - 0.1 { return }
        let contactY = engine.tuning.playerY + ball.radius
        let untilContact = max(0, (contactY - ball.position.y) / ball.velocity.y)
        let span = 20 - 2 * ball.radius
        let unfolded = ball.position.x + ball.velocity.x * untilContact - ball.radius
        var folded = unfolded.truncatingRemainder(dividingBy: 2 * span)
        if folded < 0 { folded += 2 * span }
        let landingX = ball.radius + (folded <= span ? folded : 2 * span - folded)

        var desiredAngle: Double = 0
        if engine.state.stage.isBoss {
            // Vary deliberate edge contacts to force the limited-speed boss to
            // recover after side-wall bounces. No boss state is modified.
            let fractions: [Double] = [0.92, -0.88, 0.68, -0.97, 0.82, -0.72]
            let velocity = ReceivingTrajectory.outgoing(
                apparentAngle: fractions[bossReturns % fractions.count] * engine.tuning.maximumOutgoingApparentAngle,
                at: .init(x: landingX, y: contactY), speed: 1,
                projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor)
            desiredAngle = atan2(velocity.x, velocity.y)
        } else {
            if plannedReturn != returns {
                plannedAngle = denseWaveAngle(in: engine, landing: landingX, contactY: contactY)
                plannedReturn = returns
            }
            desiredAngle = plannedAngle
        }
        let requestedVelocity = Vector2(x: sin(desiredAngle), y: cos(desiredAngle))
        let screenSlope = ReceivingTrajectory.projectedSlope(of: requestedVelocity,
            at: .init(x: landingX, y: contactY), projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor)
        let fraction = atan(screenSlope) / engine.tuning.maximumOutgoingApparentAngle
        let desiredX = landingX - fraction * engine.tuning.playerHalfWidth
        if returns.isMultiple(of: 2) {
            engine.movePlayer(crownDelta: desiredX - engine.state.playerX, sensitivity: 1)
        } else {
            engine.setPlayerFromTouch(screenX: touchTransform.screenPoint(for: .init(x: desiredX, y: 0)).x,
                                      transform: touchTransform)
        }
    }
    /// DEBUG/test-only ray planning. It chooses a return angle through the same
    /// public player control; it never alters a ball, target, score or transition.
    /// Mirrored target images represent ordinary side/far-wall reflections.
    private func denseWaveAngle(in engine: GameEngine, landing: Double, contactY: Double) -> Double {
        let radius = engine.tuning.ballRadius
        let span = CourtGeometry.width - 2 * radius
        let far = CourtGeometry.length - radius
        var images: [(position: Vector2, radius: Double)] = []
        images.reserveCapacity(engine.state.targets.count * 6)
        for target in engine.state.targets {
            let x = target.position.x
            for imageX in [x, 2 * radius - x, 2 * (CourtGeometry.width - radius) - x] {
                for imageY in [target.position.y, 2 * far - target.position.y] {
                    images.append((.init(x: imageX, y: imageY), target.radius + radius))
                }
            }
        }
        let start = Vector2(x: landing, y: contactY)
        var bestAngle = 0.0
        var bestValue = -Double.infinity
        for aim in images {
            let angle = atan2(aim.position.x - landing, aim.position.y - contactY)
            let direction = Vector2(x: sin(angle), y: cos(angle))
            let apparentAngle = atan(ReceivingTrajectory.projectedSlope(of: direction, at: start,
                projectionSlopeFactor: engine.tuning.receivingProjectionSlopeFactor))
            let fraction = apparentAngle / engine.tuning.maximumOutgoingApparentAngle
            let playerX = landing - fraction * engine.tuning.playerHalfWidth
            guard abs(fraction) <= 1,
                  playerX >= engine.tuning.playerMargin,
                  playerX <= CourtGeometry.width - engine.tuning.playerMargin else { continue }
            var first = Double.infinity
            for obstacle in images {
                let offset = obstacle.position - start
                let along = offset.dot(direction)
                let perpendicularSquared = offset.dot(offset) - along * along
                guard along > 0, perpendicularSquared <= obstacle.radius * obstacle.radius else { continue }
                let distance = along - sqrt(max(0, obstacle.radius * obstacle.radius - perpendicularSquared))
                if distance > 0 { first = min(first, distance) }
            }
            guard first.isFinite else { continue }
            let firstY = contactY + direction.y * first
            let worldY = firstY <= far ? firstY : 2 * far - firstY
            // Prefer a real bank behind the field; otherwise open the deepest
            // available target. Slight angular preference makes ties stable.
            let frontX = landing + tan(angle) * (23.0 - contactY)
            var folded = (frontX - radius).truncatingRemainder(dividingBy: 2 * span)
            if folded < 0 { folded += 2 * span }
            let entryX = radius + (folded <= span ? folded : 2 * span - folded)
            let sideEntry = entryX < 2 || entryX > 18
            let value = worldY + (firstY > far ? 20 : 0) + (sideEntry ? 2 : 0) - abs(angle) * 0.01
            if value > bestValue { bestValue = value; bestAngle = angle }
        }
        return bestAngle
    }

}

@Suite("Public-input complete runs and stress")
struct FullRunTests {
    @Test("Incoming launch cannot damage a target before the first player strike")
    func noFreeLaunchScore() {
        let engine = GameEngine(seed: 7)
        var sawPlayer = false
        for _ in 0..<600 {
            let events = engine.update(delta: 1.0 / 120)
            if events.contains(where: { if case .paddleContact = $0 { return true }; return false }) {
                sawPlayer = true
                break
            }
            #expect(!events.contains { if case .targetHit = $0 { return true }; return false })
            #expect(engine.state.score == 0)
        }
        #expect(sawPlayer)
    }

    @Test("Controls alone complete all waves, beat The Wall, and replay deterministically")
    func completeRunAndReplay() {
        let engine = GameEngine(seed: 7)
        var previousScore: Int?
        for run in 0..<2 {
            if run > 0 { engine.reset(seed: 7) }
            var player = AutomaticPlayer()
            var cleared: [Int] = []
            var bossPoints: [Int] = []
            var contacts = 0
            var results = 0
            var peakCascade = 0
            var frames = 0
            var accountedScore = 0
            var damageByWave = [0, 0, 0]
            var cleanedByWave = [0, 0, 0]
            var activeSeconds = [0.0, 0, 0]
            var longestChain = [0, 0, 0]
            var backfieldEntries = [0, 0, 0]
            var backfieldChainHits = [0, 0, 0]
            var longestBackfieldChain = [0, 0, 0]
            var currentBackfieldChain = 0
            var sideEntries = [0, 0, 0]
            var previousBall: Vector2?
            var previousInBackfield = false
            var lastDamageFrame = 0
            var longestStallFrames = 0
            var chainEnteredBackfield = false
            while engine.state.phase != .results && frames < 144_000 {
                let stageBefore = engine.state.stage
                if let wave = stageBefore.waveNumber, engine.state.phase == .playing {
                    activeSeconds[wave - 1] += 1.0 / 120
                    let inBackfield = (engine.state.ball?.position.y ?? 0) > [33.8, 42.2, 42.25][wave - 1]
                    if inBackfield && !previousInBackfield {
                        backfieldEntries[wave - 1] += 1
                        chainEnteredBackfield = true
                    }
                    previousInBackfield = inBackfield
                    if let ball = engine.state.ball, let previousBall,
                       previousBall.y < 23, ball.position.y >= 23,
                       ball.position.x < 2 || ball.position.x > 18 {
                        sideEntries[wave - 1] += 1
                    }
                    previousBall = engine.state.ball?.position
                }
                player.position(in: engine)
                let events = engine.update(delta: 1.0 / 120)
                player.observe(events, stage: engine.state.stage)
                for event in events {
                    if case let .waveCleared(number) = event { cleared.append(number) }
                    if case let .bossPoint(points) = event { bossPoints.append(points) }
                    if case .paddleContact = event { contacts += 1; chainEnteredBackfield = false; currentBackfieldChain = 0 }
                    if case let .targetHit(_, _, _, score) = event {
                        accountedScore += score
                        if let wave = stageBefore.waveNumber {
                            damageByWave[wave - 1] += 1
                            longestChain[wave - 1] = max(longestChain[wave - 1], engine.state.targetChain)
                            if chainEnteredBackfield {
                                backfieldChainHits[wave - 1] += 1
                                currentBackfieldChain += 1
                                longestBackfieldChain[wave - 1] = max(longestBackfieldChain[wave - 1], currentBackfieldChain)
                            }
                        }
                        longestStallFrames = max(longestStallFrames, frames - lastDamageFrame)
                        lastDamageFrame = frames
                    }
                    if case let .targetCleaned(_, _, score) = event {
                        accountedScore += score
                        if let wave = stageBefore.waveNumber { cleanedByWave[wave - 1] += 1 }
                    }
                    if case .waveCleared = event { accountedScore += engine.tuning.waveBonus }
                    if case .bossPoint = event { accountedScore += engine.tuning.bossPointScore }
                    if case .bossDefeated = event { accountedScore += engine.tuning.bossVictoryBonus }
                    if case .runEnded = event { results += 1 }
                }
                peakCascade = max(peakCascade, engine.state.celebration.activeCount)
                frames += 1
            }
            #expect(engine.state.phase == .results, "Run stopped at \(engine.state.stage), \(engine.state.targets.count) targets, \(engine.state.bossPoints) boss points after \(frames) frames")
            #expect(engine.state.won)
            #expect(cleared == [1, 2, 3])
            #expect(bossPoints == [1, 2, 3])
            #expect(contacts >= 8)
            #expect(results == 1)
            #expect(peakCascade >= 100)
            #expect(engine.state.score == accountedScore)
            #expect(zip(damageByWave, cleanedByWave).map(+) == [36, 48, 58])
            #expect(cleanedByWave.allSatisfy { $0 <= engine.tuning.cleanupTargetThreshold })
            #expect(damageByWave == [32, 44, 54])
            #expect(backfieldEntries.allSatisfy { $0 > 0 })
            #expect(longestBackfieldChain.allSatisfy { $0 >= 2 })
            #expect(sideEntries.allSatisfy { $0 > 0 })
            #expect(longestStallFrames < 30 * 120, "Controlled trajectories must not stall for 30 seconds without damage")
            #expect(longestChain.allSatisfy { $0 >= 3 })
            for index in 0..<3 {
                print("DENSE WAVE \(index + 1) playerHits=\(damageByWave[index]) cleanupHits=\(cleanedByWave[index]) activeSeconds=\(activeSeconds[index]) hitsPerSecond=\(Double(damageByWave[index]) / activeSeconds[index]) longestChain=\(longestChain[index]) backfieldEntries=\(backfieldEntries[index]) backfieldChainHits=\(backfieldChainHits[index]) longestBackfieldChain=\(longestBackfieldChain[index]) sideEntries=\(sideEntries[index])")
            }
            print("DENSE RUN \(run) score=\(engine.state.score) frames=\(frames) longestNoDamageSeconds=\(Double(longestStallFrames) / 120)")
            if let previousScore { #expect(engine.state.score == previousScore) }
            previousScore = engine.state.score
        }
    }

    @Test("Long deterministic play keeps state finite and resources bounded")
    func boundedStress() {
        let engine = GameEngine(seed: 91)
        var player = AutomaticPlayer()
        var runs = 0
        var maxParticles = 0
        for frame in 0..<60_000 {
            if engine.state.phase == .results {
                runs += 1
                engine.reset(seed: UInt64(runs + 91))
                player = AutomaticPlayer()
            }
            player.position(in: engine)
            let events = engine.update(delta: 1.0 / 60)
            player.observe(events, stage: engine.state.stage)
            maxParticles = max(maxParticles, engine.state.celebration.activeCount)
            if frame.isMultiple(of: 120) {
                #expect(engine.state.playerX.isFinite)
                #expect((0...3).contains(engine.state.lives))
                #expect(engine.state.targets.count <= 58)
                #expect(engine.state.celebration.particles.count <= 128)
                #expect(engine.state.celebration.activeCount <= 128)
                if let ball = engine.state.ball {
                    #expect(ball.position.x.isFinite && ball.position.y.isFinite)
                    #expect(ball.speed.isFinite && ball.speed <= engine.tuning.maximumBallSpeed + 0.000_001)
                    #expect(ball.position.x >= ball.radius - 0.001)
                    #expect(ball.position.x <= 20 - ball.radius + 0.001)
                }
            }
        }
        #expect(runs > 0)
        #expect(maxParticles >= 100)
    }
}
