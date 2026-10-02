import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Five-opponent saved-data compatibility")
struct FiveBossRecordCompatibilityTests {
    @Test("Adding opponents preserves the original serialized keys, settings and Arcade best")
    func oldRecordsSurviveAddingOpponents() throws {
        let suite = "PickleBlast-five-boss-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Literal legacy JSON and keys make this an update-format fixture,
        // independent of current enum ordering and the current encoder.
        let legacy: [String: Data] = [
            "wall": Data(#"{"wins":4,"bestScore":3200,"longestRally":19}"#.utf8),
            "banger": Data(#"{"wins":2,"bestScore":2750,"longestRally":12}"#.utf8),
            "poacher": Data(#"{"wins":7,"bestScore":4100,"longestRally":26}"#.utf8)
        ]
        for (id, data) in legacy { defaults.set(data, forKey: "pickleblast.boss." + id) }
        defaults.set(1.37, forKey: "pickleblast.sensitivity")
        defaults.set(false, forKey: "pickleblast.haptics")
        defaults.set(18_750, forKey: "pickleblast.best")
        let store = LocalStore(defaults: defaults)
        #expect(store.bossRecord(for: .wall) == BossRecord(wins: 4, bestScore: 3200, longestRally: 19))
        #expect(store.bossRecord(for: .banger) == BossRecord(wins: 2, bestScore: 2750, longestRally: 12))
        #expect(store.bossRecord(for: .poacher) == BossRecord(wins: 7, bestScore: 4100, longestRally: 26))
        for id in [BossID.dinker, .lobber] {
            #expect(store.bossRecord(for: id) == BossRecord())
            #expect(defaults.object(forKey: "pickleblast.boss." + id.rawValue) == nil)
        }
        store.recordBoss(id: .dinker, won: true, score: 2500, longestRally: 9)
        store.recordBoss(id: .lobber, won: false, score: 1000, longestRally: 15)
        let reloaded = LocalStore(defaults: defaults)
        #expect(reloaded.bossRecord(for: .dinker) == BossRecord(wins: 1, bestScore: 2500, longestRally: 9))
        #expect(reloaded.bossRecord(for: .lobber) == BossRecord(wins: 0, bestScore: 1000, longestRally: 15))
        for (id, data) in legacy { #expect(defaults.data(forKey: "pickleblast.boss." + id) == data) }
        #expect(reloaded.bestScore == 18_750)
        #expect(reloaded.settings == GameSettings(crownSensitivity: 1.37, hapticsEnabled: false))
        #expect(reloaded.settings.effectiveCrownGain == 0.15 * 1.37)
    }

    @Test("A corrupt new record cannot erase old records or the other new opponent")
    func corruptNewRecordIsIsolated() throws {
        let suite = "PickleBlast-five-boss-corruption-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalStore(defaults: defaults)
        store.recordBoss(id: .wall, won: true, score: 2500, longestRally: 8)
        store.recordBoss(id: .lobber, won: true, score: 2500, longestRally: 10)
        defaults.set(Data(#"{"wins":-9,"bestScore":1000,"longestRally":10}"#.utf8), forKey: "pickleblast.boss.dinker")
        #expect(store.bossRecord(for: .dinker) == BossRecord())
        #expect(store.bossRecord(for: .wall).wins == 1)
        #expect(store.bossRecord(for: .lobber).wins == 1)
        store.recordBoss(id: .dinker, won: true, score: 2500, longestRally: 12)
        #expect(store.bossRecord(for: .dinker) == BossRecord(wins: 1, bestScore: 2500, longestRally: 12))
        #expect(store.bossRecord(for: .lobber).longestRally == 10)
    }
}
