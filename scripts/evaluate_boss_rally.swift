import Foundation
#if canImport(PickleBlastCore)
import PickleBlastCore
#endif

private struct Options {
    var output = "docs/evidence/boss_rally_overhaul/baseline-scenarios-matched"
    var candidate = Candidate.current
    var rallyMotionInfluence = false
    var calibrationSeeds = 40
    var heldoutSeeds = 10
    var maxSeconds = 360.0
    var bosses = BossID.allCases
    var policies = BossPlayerPolicy.frozenComparisonCases
    var help = false
}

private enum Candidate: String {
    case current
    case reducedWallOpponent
}

private struct RallyRecord: Codable {
    let end: String
    let seconds: Double
    let playerContacts: Int
    let bossContacts: Int
}

private struct MatchRecord: Codable {
    let split: String
    let seed: String
    let boss: String
    let policy: String
    let outcome: String
    let capped: Bool
    let resultsReached: Bool
    let terminalDecision: Bool
    let unresolvedCap: Bool
    let decidedAtCaptureCap: Bool
    let matchSeconds: Double
    let playerPoints: Int
    let opponentPoints: Int
    let livesRemaining: Int
    let saves: Int
    let playerContacts: Int
    let bossContacts: Int
    let powerTelegraphs: Int
    let powerContacts: Int
    let poachCommitments: Int
    let leftShots: Int
    let centerShots: Int
    let rightShots: Int
    let meanContactPredictionError: Double?
    let powerRecoverySeconds: Double
    let powerRecoveryTravel: Double
    let poachRecoverySeconds: Double
    let poachRecoveryTravel: Double
    let unresolvedRallySeconds: Double
    let rallies: [RallyRecord]
}

private struct TraceRecord: Codable {
    let time: Double
    let kind: String
    let phase: String
    let ballX: Double?
    let ballY: Double?
    let ballVX: Double?
    let ballVY: Double?
    let playerX: Double
    let bossX: Double?
    let bossTargetX: Double?
    let bossLateralVelocity: Double?
    let specialPhase: String?
    let specialRemaining: Double?
    let bossPoints: Int
    let opponentPoints: Int
    let shotPurpose: String?
    let plannedReceivingX: Double?
    let lastObservedTime: Double?
    let bossPredictedInterceptX: Double?
    let bossReachableLeftX: Double?
    let bossReachableRightX: Double?
    let lives: Int
    let rallyTime: Double
    let predictedInterceptX: Double?
    let predictionTime: Double?
    let controllerTargetX: Double
    let selectedContactOffset: Double
}

private struct MatchAccumulator {
    var rallies: [RallyRecord] = []
    var rallyStartedAt: Double?
    var rallyPlayerContacts = 0
    var rallyBossContacts = 0
    var playerContacts = 0
    var bossContacts = 0
    var saves = 0
    var playerPoints = 0
    var opponentPoints = 0
    var powerTelegraphs = 0
    var powerContacts = 0
    var poachCommitments = 0
    var leftShots = 0
    var centerShots = 0
    var rightShots = 0
    var predictionErrors: [Double] = []
    var powerRecoverySeconds = 0.0
    var powerRecoveryTravel = 0.0
    var poachRecoverySeconds = 0.0
    var poachRecoveryTravel = 0.0
    var lastBossX: Double?
}

@main
private struct BossEvaluationRunner {
    static func main() throws {
        var options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
        if options.help {
            print("""
            Usage: evaluate_boss_rally [options]
              --output PATH             Output directory (default: docs/evidence/boss_rally_overhaul/baseline-scenarios-matched)
              --calibration-seeds N     Seed count per boss/policy (default: 40)
              --heldout-seeds N         Separate held-out count (default: 10)
              --max-seconds N           Per-match simulation cap (default: 360)
              --bosses wall,banger,poacher
              --policies neutral,placer,patternSetter,powerResponder,casual,stationary,lateCasual
              --candidate current|reducedWallOpponent
              --motion-influence enabled|disabled
              --help

            Calibration seeds begin at 0xB0550000; held-out seeds begin at 0xF00D1000.
            The runner never uses direct state mutation or instant player placement.
            """)
            return
        }
        options.calibrationSeeds = max(0, options.calibrationSeeds)
        options.heldoutSeeds = max(0, options.heldoutSeeds)
        guard options.calibrationSeeds + options.heldoutSeeds > 0 else {
            throw ParseError("At least one calibration or held-out seed is required")
        }
        options.maxSeconds = max(5, options.maxSeconds)

        let output = URL(fileURLWithPath: options.output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let traceDirectory = output.appendingPathComponent("traces", isDirectory: true)
        try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        let csvURL = output.appendingPathComponent("matches.csv")
        try "split,seed,boss,policy,outcome,capped,resultsReached,terminalDecision,unresolvedCap,decidedAtCaptureCap,matchSeconds,playerPoints,opponentPoints,livesRemaining,saves,playerContacts,bossContacts,powerTelegraphs,powerContacts,poachCommitments,leftShots,centerShots,rightShots,meanContactPredictionError,powerRecoverySeconds,powerRecoveryTravel,poachRecoverySeconds,poachRecoveryTravel,unresolvedRallySeconds,rallies\n".write(to: csvURL, atomically: true, encoding: .utf8)

        var total = 0
        for split in ["calibration", "heldout"] {
            let count = split == "calibration" ? options.calibrationSeeds : options.heldoutSeeds
            let seedBase: UInt64 = split == "calibration" ? 0xB055_0000 : 0xF00D_1000
            for index in 0..<count {
                let scenarioSeed = seedBase &+ UInt64(index)
                for boss in options.bosses {
                    for policyKind in options.policies {
                        let trace = index == 0 && [BossPlayerPolicy.neutral, .patternSetter,
                            .powerResponder, .stationary, .lateCasual].contains(policyKind)
                        let match = runMatch(boss: boss, policyKind: policyKind,
                            seed: scenarioSeed, split: split, maxSeconds: options.maxSeconds,
                            candidate: options.candidate,
                            rallyMotionInfluence: options.rallyMotionInfluence,
                            trace: trace)
                        try appendCSV(match.csv, to: csvURL)
                        if trace {
                            let traceURL = traceDirectory.appendingPathComponent("\(split)-\(boss.rawValue)-\(policyKind.rawValue)-\(String(scenarioSeed, radix: 16)).jsonl")
                            let traceEncoder = JSONEncoder()
                            traceEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                            let lines = try match.trace.map { try traceEncoder.encode($0) + Data([0x0A]) }
                            try lines.reduce(into: Data()) { $0.append($1) }.write(to: traceURL, options: .atomic)
                        }
                        total += 1
                    }
                }
            }
            fputs("Completed \(split) seed set (\(count) seeds × \(options.bosses.count) bosses × \(options.policies.count) policies).\n", stderr)
        }

        let manifest = [
            "sourceCommit": ProcessInfo.processInfo.environment["BOSS_EVAL_SOURCE_COMMIT"] ?? "unprovided",
            "sourceDigest": ProcessInfo.processInfo.environment["BOSS_EVAL_SOURCE_DIGEST"] ?? "unprovided",
            "candidate": options.candidate.rawValue,
            "rallyMotionInfluenceEnabled": options.rallyMotionInfluence,
            "wallOpponentTuning": options.candidate == .reducedWallOpponent
                ? ["maximumLateralSpeed": 7.2, "lateralAcceleration": 24.0,
                   "lateralBraking": 30.0, "observationDelay": 0.20]
                : ["maximumLateralSpeed": 8.2, "lateralAcceleration": 28.0,
                   "lateralBraking": 34.0, "observationDelay": 0.18],
            "playerPolicyConfigurations": Dictionary(uniqueKeysWithValues:
                BossPlayerPolicy.allCases.map { policy in
                    let p = BossPolicyConfiguration.profile(for: policy)
                    return (policy.rawValue, ["observationDelay": p.observationDelay,
                        "decisionInterval": p.decisionInterval,
                        "maximumMovementSpeed": p.maximumMovementSpeed,
                        "movementAcceleration": p.movementAcceleration,
                        "movementBraking": p.movementBraking])
                }),
            "lateCasualStressControl": [
                "humanCalibration": false,
                "description": "Impaired synthetic control with delayed observation, bounded movement, and one coherent positioning error per incoming flight; no shot placement.",
                "positioningErrorUniformRangeFeet": [-4.5, 4.5]
            ] as [String: Any],
            "engineSeedPolicy": "shared matched seed across policies and bosses",
            "calibrationSeeds": options.calibrationSeeds,
            "heldoutSeeds": options.heldoutSeeds,
            "calibrationSeedStart": "0xB0550000",
            "heldoutSeedStart": "0xF00D1000",
            "maxSecondsPerMatch": options.maxSeconds,
            "terminalClassification": "The points-to-win threshold determines outcome even if the simulation cap arrives before the results phase. capped means results were not reached; unresolvedCap means no terminal point target was reached before the cap.",
            "fixedStep": GameTuning().fixedStep,
            "policies": options.policies.map(\.rawValue),
            "bosses": options.bosses.map(\.rawValue),
            "matchRows": total,
            "policyObservationBoundary": "delayed ball/phase samples plus the controller's own current player position; boss state excluded",
            "traceBoundary": "selected neutral traces include boss-state diagnostics for review; policy never receives those fields",
            "arcadeBaseline": "see AcceptedArcadeBaselineTests.publicInputTrace at seed 0xA6C4DE; this harness does not use its instantaneous-oracle controller as balance evidence"
        ] as [String: Any]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        print("Wrote \(total) matched scenario rows to \(output.path)")
    }

    private static func runMatch(boss: BossID, policyKind: BossPlayerPolicy,
                                 seed: UInt64, split: String, maxSeconds: Double,
                                 candidate: Candidate,
                                 rallyMotionInfluence: Bool,
                                 trace shouldTrace: Bool) -> (csv: MatchRecord, trace: [TraceRecord]) {
        var tuning = GameTuning()
#if BOSS_OVERHAUL
        if boss == .wall {
            switch candidate {
            case .current:
                tuning.rallyWall.maximumLateralSpeed = 8.2
                tuning.rallyWall.lateralAcceleration = 28
                tuning.rallyWall.lateralBraking = 34
                tuning.rallyWall.observationDelay = 0.18
            case .reducedWallOpponent:
                tuning.rallyWall.maximumLateralSpeed = 7.2
                tuning.rallyWall.lateralAcceleration = 24
                tuning.rallyWall.lateralBraking = 30
                tuning.rallyWall.observationDelay = 0.20
            }
        }
        tuning.rallyMotionInfluenceEnabled = rallyMotionInfluence
#else
        precondition(candidate == .current, "Reduced Wall candidate is available only in the overhaul core")
        precondition(!rallyMotionInfluence, "Motion influence is unavailable in the baseline core")
#endif
        let engine = GameEngine(mode: .bossRally(boss), tuning: tuning, seed: seed)
        let policySeed = seed ^ (UInt64(policyKind.rawValue.utf8.reduce(0) { ($0 &* 33) &+ UInt64($1) }) << 16)
        let policyConfiguration = BossPolicyConfiguration.profile(for: policyKind)
        var policy = BossEvaluationPolicy(kind: policyKind, seed: policySeed,
            tuning: tuning, configuration: policyConfiguration, startingPositionSeed: seed)
        var metric = MatchAccumulator()
        var traces: [TraceRecord] = []
        var pendingEvents: [GameEvent] = []
        var elapsed = 0.0
        var nextTraceTime = 0.0
        let step = tuning.fixedStep
        let maxSteps = Int(maxSeconds / step)

        for _ in 0..<maxSteps {
            if engine.state.phase == .results { break }
            let before = engine.state
            policy.observe(.init(time: before.simulationTime, phase: before.phase,
                                 ball: before.ball, playerX: before.playerX), events: pendingEvents)
            let movement = policy.movementDelta(currentPlayerX: before.playerX, elapsed: step)
            if movement != 0 { engine.movePlayer(crownDelta: movement, sensitivity: 1) }
            let events = engine.update(delta: step)
            elapsed += step
            updateMetrics(events: events, stateBefore: before, stateAfter: engine.state,
                          policy: policy, step: step, elapsed: elapsed, metric: &metric)
            pendingEvents = events

            if shouldTrace, elapsed + 1e-9 >= nextTraceTime {
                traces.append(traceRow(time: elapsed, kind: "sample", state: engine.state,
                                       policy: policy))
                nextTraceTime += 0.5
            }
            if shouldTrace {
                for event in events where traceable(event) {
                    traces.append(traceRow(time: elapsed, kind: eventName(event),
                                           state: engine.state, policy: policy))
                }
            }
        }
        if let start = metric.rallyStartedAt {
            metric.rallies.append(.init(end: "capped", seconds: max(0, elapsed - start),
                playerContacts: metric.rallyPlayerContacts, bossContacts: metric.rallyBossContacts))
        }

        let resultsReached = engine.state.phase == .results
        let targetPoints = engine.activeBossConfiguration.pointsToWin
        let terminalWin = playerPoints(engine.state) >= targetPoints || (resultsReached && engine.state.won)
        let terminalLoss = opponentPoints(engine.state) >= targetPoints || (resultsReached && !engine.state.won)
        let terminalDecision = terminalWin || terminalLoss
        let outcome = terminalWin ? "engineWon" : (terminalLoss ? "engineLost" : "unresolved")
        let capped = !resultsReached
        let predictionError = metric.predictionErrors.isEmpty ? nil : metric.predictionErrors.reduce(0, +) / Double(metric.predictionErrors.count)
        let record = MatchRecord(split: split, seed: String(seed, radix: 16), boss: boss.rawValue,
            policy: policyKind.rawValue, outcome: outcome, capped: capped,
            resultsReached: resultsReached, terminalDecision: terminalDecision,
            unresolvedCap: capped && !terminalDecision,
            decidedAtCaptureCap: capped && terminalDecision,
            matchSeconds: elapsed, playerPoints: playerPoints(engine.state),
            opponentPoints: opponentPoints(engine.state), livesRemaining: engine.state.lives,
            saves: metric.saves, playerContacts: metric.playerContacts, bossContacts: metric.bossContacts,
            powerTelegraphs: metric.powerTelegraphs, powerContacts: metric.powerContacts,
            poachCommitments: metric.poachCommitments, leftShots: metric.leftShots,
            centerShots: metric.centerShots, rightShots: metric.rightShots,
            meanContactPredictionError: predictionError,
            powerRecoverySeconds: metric.powerRecoverySeconds,
            powerRecoveryTravel: metric.powerRecoveryTravel,
            poachRecoverySeconds: metric.poachRecoverySeconds,
            poachRecoveryTravel: metric.poachRecoveryTravel,
            unresolvedRallySeconds: metric.rallyStartedAt != nil ? max(0, elapsed - (metric.rallyStartedAt ?? elapsed)) : 0,
            rallies: metric.rallies)
        return (record, traces)
    }

    private static func updateMetrics(events: [GameEvent], stateBefore: GameState,
                                      stateAfter: GameState, policy: BossEvaluationPolicy,
                                      step: Double, elapsed: Double,
                                      metric: inout MatchAccumulator) {
        if stateBefore.phase != .playing && stateAfter.phase == .playing {
            metric.rallyStartedAt = elapsed
            metric.rallyPlayerContacts = 0
            metric.rallyBossContacts = 0
        }
        if let oldX = metric.lastBossX, let boss = stateAfter.boss {
            switch boss.specialPhase {
            case .powerRecovery:
                metric.powerRecoverySeconds += step
                metric.powerRecoveryTravel += abs(boss.x - oldX)
            case .poachRecovery:
                metric.poachRecoverySeconds += step
                metric.poachRecoveryTravel += abs(boss.x - oldX)
            default: break
            }
        }
        metric.lastBossX = stateAfter.boss?.x

        for event in events {
            switch event {
            case .paddleContact(let x, _, _):
                metric.playerContacts += 1
                metric.rallyPlayerContacts += 1
                if let predicted = policy.diagnosticState.predictedInterceptX {
                    metric.predictionErrors.append(abs(x - predicted))
                }
                let offset = policy.diagnosticState.selectedContactOffset
                if offset < -0.18 { metric.leftShots += 1 }
                else if offset > 0.18 { metric.rightShots += 1 }
                else { metric.centerShots += 1 }
            case .bossContact:
                metric.bossContacts += 1
                metric.rallyBossContacts += 1
            case .ballRecovered:
                metric.saves += 1
                closeRally(end: "saved", elapsed: elapsed, metric: &metric)
            case .lifeLost:
#if !BOSS_OVERHAUL
                metric.opponentPoints += 1
#endif
                closeRally(end: "lifeLost", elapsed: elapsed, metric: &metric)
            case .bossPoint:
                metric.playerPoints += 1
                closeRally(end: "bossPoint", elapsed: elapsed, metric: &metric)
#if BOSS_OVERHAUL
            case .opponentPoint:
                metric.opponentPoints += 1
                closeRally(end: "opponentPoint", elapsed: elapsed, metric: &metric)
#endif
            case .bossPowerTelegraph: metric.powerTelegraphs += 1
            case .bossPowerContact: metric.powerContacts += 1
            case .bossPoachCommitment: metric.poachCommitments += 1
            default: break
            }
        }
    }

    private static func closeRally(end: String, elapsed: Double, metric: inout MatchAccumulator) {
        guard let start = metric.rallyStartedAt else { return }
        metric.rallies.append(.init(end: end, seconds: max(0, elapsed - start),
            playerContacts: metric.rallyPlayerContacts, bossContacts: metric.rallyBossContacts))
        metric.rallyStartedAt = nil
        metric.rallyPlayerContacts = 0
        metric.rallyBossContacts = 0
    }

    private static func traceRow(time: Double, kind: String, state: GameState,
                                 policy: BossEvaluationPolicy) -> TraceRecord {
        let ball = state.ball
        let boss = state.boss
        let diagnostics = policy.diagnosticState
#if BOSS_OVERHAUL
        let lateralVelocity = boss?.lateralVelocity
        let pointValues = (state.playerRallyPoints, state.opponentRallyPoints)
        let shotPurpose = boss?.lastShotPurpose?.rawValue
        let plannedReceivingX = boss?.plannedReceivingX
        let lastObservedTime = boss?.lastObservedTime
        let bossIntercept = boss?.predictedInterceptX
        let bossReachableLeft = boss?.reachableLeftX
        let bossReachableRight = boss?.reachableRightX
#else
        let lateralVelocity: Double? = nil
        let pointValues = (state.bossPoints, tuningInitialLivesMinus(state))
        let shotPurpose: String? = nil
        let plannedReceivingX: Double? = nil
        let lastObservedTime: Double? = nil
        let bossIntercept: Double? = nil
        let bossReachableLeft: Double? = nil
        let bossReachableRight: Double? = nil
#endif
        return TraceRecord(time: time, kind: kind, phase: state.phase.rawValue,
            ballX: ball?.position.x, ballY: ball?.position.y,
            ballVX: ball?.velocity.x, ballVY: ball?.velocity.y,
            playerX: state.playerX, bossX: boss?.x, bossTargetX: boss?.movementTarget,
            bossLateralVelocity: lateralVelocity,
            specialPhase: boss?.specialPhase.rawValue, specialRemaining: boss?.specialRemaining,
            bossPoints: pointValues.0, opponentPoints: pointValues.1,
            shotPurpose: shotPurpose, plannedReceivingX: plannedReceivingX,
            lastObservedTime: lastObservedTime, bossPredictedInterceptX: bossIntercept,
            bossReachableLeftX: bossReachableLeft, bossReachableRightX: bossReachableRight,
            lives: state.lives, rallyTime: state.rallyTime,
            predictedInterceptX: diagnostics.predictedInterceptX,
            predictionTime: diagnostics.predictedFlightTime,
            controllerTargetX: diagnostics.targetX,
            selectedContactOffset: diagnostics.selectedContactOffset)
    }

    private static func traceable(_ event: GameEvent) -> Bool {
        switch event {
        case .paddleContact, .bossContact, .bossPowerTelegraph, .bossPowerContact,
             .bossPoachCommitment, .bossPoachRecovery, .bossPoint, .ballRecovered,
             .lifeLost, .runEnded, .phaseChanged:
            return true
#if BOSS_OVERHAUL
        case .opponentPoint:
            return true
#endif
        default: return false
        }
    }

    private static func eventName(_ event: GameEvent) -> String {
        switch event {
        case .paddleContact: return "paddleContact"
        case .bossContact: return "bossContact"
        case .bossPowerTelegraph: return "bossPowerTelegraph"
        case .bossPowerContact: return "bossPowerContact"
        case .bossPoachCommitment: return "bossPoachCommitment"
        case .bossPoachRecovery: return "bossPoachRecovery"
        case .bossPoint: return "bossPoint"
#if BOSS_OVERHAUL
        case .opponentPoint: return "opponentPoint"
#endif
        case .ballRecovered: return "ballRecovered"
        case .lifeLost: return "lifeLost"
        case .runEnded: return "runEnded"
        case .phaseChanged(let phase): return "phaseChanged.\(phase.rawValue)"
        default: return "event"
        }
    }

    private static func appendCSV(_ record: MatchRecord, to url: URL) throws {
        let durationText = record.rallies.map {
            "\($0.end):\(String(format: "%.3f", $0.seconds)):\($0.playerContacts):\($0.bossContacts)"
        }.joined(separator: ";")
        let fields: [String] = [record.split, record.seed, record.boss, record.policy,
            record.outcome, String(record.capped), String(record.resultsReached),
            String(record.terminalDecision), String(record.unresolvedCap),
            String(record.decidedAtCaptureCap), String(format: "%.4f", record.matchSeconds),
            String(record.playerPoints), String(record.opponentPoints), String(record.livesRemaining),
            String(record.saves), String(record.playerContacts), String(record.bossContacts),
            String(record.powerTelegraphs), String(record.powerContacts), String(record.poachCommitments),
            String(record.leftShots), String(record.centerShots), String(record.rightShots),
            record.meanContactPredictionError.map { String(format: "%.4f", $0) } ?? "",
            String(format: "%.4f", record.powerRecoverySeconds), String(format: "%.4f", record.powerRecoveryTravel),
            String(format: "%.4f", record.poachRecoverySeconds), String(format: "%.4f", record.poachRecoveryTravel),
            String(format: "%.4f", record.unresolvedRallySeconds), durationText]
        let line = fields.map(csvEscape).joined(separator: ",") + "\n"
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func parseOptions(_ args: [String]) throws -> Options {
        var result = Options()
        var index = 0
        while index < args.count {
            let option = args[index]
            index += 1
            if option == "--help" { result.help = true; continue }
            guard index < args.count else { throw ParseError("Missing value for \(option)") }
            let value = args[index]
            index += 1
            switch option {
            case "--output": result.output = value
            case "--candidate":
                guard let candidate = Candidate(rawValue: value) else {
                    throw ParseError("Unknown candidate: \(value)")
                }
                result.candidate = candidate
            case "--motion-influence":
                switch value {
                case "enabled": result.rallyMotionInfluence = true
                case "disabled": result.rallyMotionInfluence = false
                default: throw ParseError("Invalid \(option): \(value); use enabled or disabled")
                }
            case "--calibration-seeds": result.calibrationSeeds = try integer(value, option)
            case "--heldout-seeds": result.heldoutSeeds = try integer(value, option)
            case "--max-seconds":
                guard let number = Double(value), number.isFinite else { throw ParseError("Invalid \(option): \(value)") }
                result.maxSeconds = number
            case "--bosses":
                result.bosses = try value.split(separator: ",").map { raw in
                    guard let boss = BossID(rawValue: String(raw)) else { throw ParseError("Unknown boss: \(raw)") }
                    return boss
                }
            case "--policies":
                result.policies = try value.split(separator: ",").map { raw in
                    guard let policy = BossPlayerPolicy(rawValue: String(raw)) else { throw ParseError("Unknown policy: \(raw)") }
                    return policy
                }
            default: throw ParseError("Unknown option: \(option)")
            }
        }
        return result
    }

    private static func integer(_ string: String, _ option: String) throws -> Int {
        guard let value = Int(string) else { throw ParseError("Invalid \(option): \(string)") }
        return value
    }

    private static func playerPoints(_ state: GameState) -> Int {
#if BOSS_OVERHAUL
        return state.playerRallyPoints
#else
        return state.bossPoints
#endif
    }

    private static func opponentPoints(_ state: GameState) -> Int {
#if BOSS_OVERHAUL
        return state.opponentRallyPoints
#else
        return GameTuning().initialLives - state.lives
#endif
    }

#if !BOSS_OVERHAUL
    private static func tuningInitialLivesMinus(_ state: GameState) -> Int {
        GameTuning().initialLives - state.lives
    }
#endif
}

private struct ParseError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
