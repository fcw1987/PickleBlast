import Foundation

public struct RuntimeArtManifest: Decodable {
    public let schemaVersion: Int
    public let characters: [String: CharacterArt]
    public let supporting: [String: SupportingArt]
}
public struct SupportingArt: Decodable {
    public let atlas: String
    public let name: String
    public let pixelSize: [Double]
    public let alphaBounds: [Double]
    public var visibleFraction: Double { max(alphaBounds[2] - alphaBounds[0], alphaBounds[3] - alphaBounds[1]) / max(pixelSize[0], pixelSize[1]) }
}
public struct CharacterArt: Decodable {
    public let atlas: String
    public let canvasSize: [Double]
    public let anchor: [Double]
    public let clips: [String: AnimationClip]
}
public struct AnimationFrame: Decodable {
    public let name: String
    public let timestamp: Double
    public let paddleCenter: [Double]
    public let wrist: [Double]
    public let bounds: [Double]
}
public struct AnimationClip: Decodable {
    public let duration: Double
    public let loop: Bool
    public let contactIndex: Int?
    public let strideSourcePixels: Double?
    public let frames: [AnimationFrame]
    public var contactTime: Double? { contactIndex.map { frames[$0].timestamp } }
    public func frameIndex(at elapsed: Double) -> Int {
        let t = loop ? max(0, elapsed).truncatingRemainder(dividingBy: duration) : min(duration, max(0, elapsed))
        return frames.lastIndex(where: { $0.timestamp <= t + 0.00000001 }) ?? 0
    }
}

/// Presentation clock and clip selection; never changes gameplay state or awards contacts.
struct MotionPlayback {
    private(set) var clip = "idle"
    private(set) var elapsed = 0.0
    private(set) var distance = 0.0
    private(set) var confirmed = false
    private(set) var contactCount = 0
    private var lastX: Double?
    private var idleTime = 0.0
    private var stillTime = 0.0
    var contactOffset = 0.0

    mutating func advance(x: Double, delta: Double, frozen: Bool, art: CharacterArt,
                          spriteWidth: Double, prediction: (clip: String, arrival: Double, offset: Double)?) {
        let travel = lastX.map { x - $0 } ?? 0
        lastX = x
        guard !frozen else { return }
        idleTime += delta
        distance += abs(travel)
        stillTime = abs(travel) > 0.00001 ? 0 : stillTime + delta
        if confirmed {
            elapsed += delta
            if elapsed < art.clips[clip]!.duration { return }
            confirmed = false
        }
        if let prediction, let predicted = art.clips[prediction.clip], let contact = predicted.contactTime,
           prediction.arrival <= contact, prediction.arrival >= 0 {
            // Track arrival on one continuous timeline; lateral input never restarts anticipation.
            clip = prediction.clip
            elapsed = max(0, contact - prediction.arrival)
            contactOffset = prediction.offset
            return
        }
        if art.clips[clip]?.contactIndex != nil {
            // A canceled prediction blends its pose back through approved recovery, with no hit.
            elapsed += delta
            if elapsed < art.clips[clip]!.duration { return }
        }
        if abs(travel) > 0.00001 {
            clip = travel < 0 ? "move_left" : "move_right"
            let stride = abs(art.clips[clip]!.strideSourcePixels ?? 26) * spriteWidth / 512
            elapsed = distance / stride * art.clips[clip]!.duration
        } else if delta > 0 && stillTime > 0.10 {
            clip = "idle"
            elapsed = idleTime
        }
        contactOffset = 0
    }
    mutating func contact(clip name: String, offset: Double, art: CharacterArt) {
        clip = name
        elapsed = art.clips[name]!.contactTime!
        contactOffset = offset
        confirmed = true
        contactCount += 1
    }
    func registrationWeight(art: CharacterArt) -> Double {
        guard let animation = art.clips[clip], let contact = animation.contactTime else { return 0 }
        if elapsed <= contact { return min(1, elapsed / contact) }
        return max(0, 1 - (elapsed - contact) / (animation.duration - contact))
    }
}
