import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Per-boss local records")
struct BossRecordTests {
    private func store() throws -> (LocalStore, UserDefaults, String) {
        let suite = "PickleBlast-boss-records-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (LocalStore(defaults: defaults), defaults, suite)
    }

    private func key(for id: BossID) -> String { "pickleblast.boss.\(id.rawValue)" }

    @Test("Boss records are isolated, monotonic, and separate from Arcade best")
    func recordsAreIsolatedAndMonotonic() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.bestScore == 0)
        #expect(store.bossRecord(for: .wall) == BossRecord())
        #expect(store.bossRecord(for: .banger) == BossRecord())

        #expect(store.record(score: 7_500))
        #expect(store.recordBoss(id: .wall, won: false, score: 1_200, longestRally: 8))
        #expect(!store.recordBoss(id: .wall, won: false, score: 900, longestRally: 4))
        #expect(!store.recordBoss(id: .wall, won: true, score: 900, longestRally: 10))
        #expect(store.recordBoss(id: .wall, won: true, score: 1_500, longestRally: 3))
        #expect(store.recordBoss(id: .banger, won: true, score: 650, longestRally: 5))

        #expect(store.bossRecord(for: .wall) == BossRecord(wins: 2, bestScore: 1_500, longestRally: 10))
        #expect(store.bossRecord(for: .banger) == BossRecord(wins: 1, bestScore: 650, longestRally: 5))
        #expect(store.bossRecord(for: .poacher) == BossRecord())
        #expect(store.bestScore == 7_500)

        let encoded = try #require(defaults.data(forKey: key(for: .wall)))
        #expect(try JSONDecoder().decode(BossRecord.self, from: encoded) ==
                BossRecord(wins: 2, bestScore: 1_500, longestRally: 10))
    }

    @Test("Malformed record falls back per boss and a later result repairs that key")
    func malformedRecordFallsBackAndRepairs() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not-json".utf8), forKey: key(for: .wall))
        defaults.set(17, forKey: key(for: .banger)) // Wrong property-list type for JSON data.
        #expect(store.bossRecord(for: .wall) == BossRecord())
        #expect(store.bossRecord(for: .banger) == BossRecord())

        #expect(store.recordBoss(id: .wall, won: true, score: 2_000, longestRally: 6))
        #expect(store.bossRecord(for: .wall) == BossRecord(wins: 1, bestScore: 2_000, longestRally: 6))
        #expect(store.bossRecord(for: .banger) == BossRecord())
    }

    @Test("Valid JSON with a negative field is rejected only for that boss")
    func negativeStoredFieldFallsBackPerBoss() throws {
        let (store, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data(#"{"wins":-1,"bestScore":800,"longestRally":12}"#.utf8),
                     forKey: key(for: .wall))
        defaults.set(try JSONEncoder().encode(BossRecord(wins: 2, bestScore: 1_400, longestRally: 16)),
                     forKey: key(for: .banger))

        #expect(store.bossRecord(for: .wall) == BossRecord())
        #expect(store.bossRecord(for: .banger) ==
                BossRecord(wins: 2, bestScore: 1_400, longestRally: 16))
        #expect(store.bossRecord(for: .poacher) == BossRecord())

        #expect(store.recordBoss(id: .wall, won: true, score: 900, longestRally: 5))
        #expect(store.bossRecord(for: .wall) == BossRecord(wins: 1, bestScore: 900, longestRally: 5))
        #expect(store.bossRecord(for: .banger) ==
                BossRecord(wins: 2, bestScore: 1_400, longestRally: 16))
    }

    @Test("Negative in-memory record fields are clamped to zero")
    func negativeFieldsAreSanitized() {
        #expect(BossRecord(wins: -1, bestScore: -25, longestRally: -3) == BossRecord())
    }
}
