import Foundation
import CoreFoundation

public struct GameSettings: Equatable, Codable, Sendable {
    public static let minimumSensitivity: Double = 0.5
    public static let defaultSensitivity: Double = 1
    public static let maximumSensitivity: Double = 2
    /// Court feet per Crown binding unit at the default setting. The old
    /// minimum gain was 0.5; this is exactly 30% of that physical baseline.
    public static let defaultCrownGain: Double = 0.15
    public var crownSensitivity: Double
    public var hapticsEnabled: Bool
    public init(crownSensitivity: Double = Self.defaultSensitivity, hapticsEnabled: Bool = true) {
        self.crownSensitivity = crownSensitivity.isFinite
            ? min(Self.maximumSensitivity, max(Self.minimumSensitivity, crownSensitivity)) : Self.defaultSensitivity
        self.hapticsEnabled = hapticsEnabled
    }
    public var effectiveCrownGain: Double { Self.defaultCrownGain * crownSensitivity }
    public var oldMinimumPercentage: Int { Int((effectiveCrownGain / 0.5 * 100).rounded()) }
}

public protocol ProgressStorage: AnyObject {
    var settings: GameSettings { get set }
    var bestScore: Int { get }
    @discardableResult func record(score: Int) -> Bool
}

/// Local records for one opponent, deliberately separate from Arcade scoring.
public struct BossRecord: Equatable, Codable, Sendable {
    public var wins: Int
    public var bestScore: Int
    public var longestRally: Int
    public init(wins: Int = 0, bestScore: Int = 0, longestRally: Int = 0) {
        self.wins = max(0, wins)
        self.bestScore = max(0, bestScore)
        self.longestRally = max(0, longestRally)
    }
}

/// Local, offline preferences; inject an isolated UserDefaults suite for tests.
public final class LocalStore: ProgressStorage {
    private let defaults: UserDefaults
    private let prefix: String
    public init(defaults: UserDefaults = .standard, keyPrefix: String = "pickleblast") {
        self.defaults = defaults; self.prefix = keyPrefix
    }
    public var settings: GameSettings {
        get {
            // UserDefaults' coercing accessors turn malformed strings into zero
            // or false. Preserve valid stored settings and default each corrupt
            // key independently, so one bad value cannot alter its neighbor.
            let sensitivity = defaults.object(forKey: prefix + ".sensitivity") as? NSNumber
            let haptics = defaults.object(forKey: prefix + ".haptics") as? NSNumber
            let numericSensitivity = sensitivity.flatMap {
                CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue
            }
            let booleanHaptics = haptics.flatMap {
                CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil
            }
            return GameSettings(crownSensitivity: numericSensitivity ?? GameSettings.defaultSensitivity,
                                hapticsEnabled: booleanHaptics ?? true)
        }
        set {
            let clean = GameSettings(crownSensitivity: newValue.crownSensitivity,
                                     hapticsEnabled: newValue.hapticsEnabled)
            defaults.set(clean.crownSensitivity, forKey: prefix + ".sensitivity")
            defaults.set(clean.hapticsEnabled, forKey: prefix + ".haptics")
        }
    }
    public var bestScore: Int {
        guard let value = defaults.object(forKey: prefix + ".best") as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              let score = Int(exactly: value.doubleValue) else { return 0 }
        return max(0, score)
    }
    @discardableResult public func record(score: Int) -> Bool {
        guard score > bestScore else { return false }
        defaults.set(score, forKey: prefix + ".best")
        return true
    }

    public func bossRecord(for id: BossID) -> BossRecord {
        guard let data = defaults.data(forKey: prefix + ".boss." + id.rawValue),
              let record = try? JSONDecoder().decode(BossRecord.self, from: data),
              record.wins >= 0, record.bestScore >= 0, record.longestRally >= 0 else {
            return BossRecord()
        }
        return record
    }

    @discardableResult public func recordBoss(id: BossID, won: Bool, score: Int,
                                              longestRally: Int) -> Bool {
        var record = bossRecord(for: id)
        let newBest = score > record.bestScore
        if won && record.wins < Int.max { record.wins += 1 }
        record.bestScore = max(record.bestScore, score)
        record.longestRally = max(record.longestRally, longestRally)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: prefix + ".boss." + id.rawValue)
        }
        return newBest
    }
}
