import Foundation
import Testing
@testable import PickleBlastCore

@Suite("Corrupt local preference recovery")
struct StorageHardeningTests {
    @Test("Wrong-type Crown value falls back to default while a valid haptic setting survives")
    func wrongTypeSensitivityFallsBack() throws {
        let suite = "PickleBlastCorruptSensitivity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("not-a-number", forKey: "pickleblast.sensitivity")
        defaults.set(false, forKey: "pickleblast.haptics")

        let settings = LocalStore(defaults: defaults).settings
        #expect(settings.crownSensitivity == GameSettings.defaultSensitivity)
        #expect(settings.hapticsEnabled == false)
    }

    @Test("Wrong-type haptics value falls back to enabled while valid numeric sensitivity survives")
    func wrongTypeHapticsFallsBack() throws {
        let suite = "PickleBlastCorruptHaptics-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(1.25, forKey: "pickleblast.sensitivity")
        defaults.set("not-a-boolean", forKey: "pickleblast.haptics")

        let settings = LocalStore(defaults: defaults).settings
        #expect(settings.crownSensitivity == 1.25)
        #expect(settings.hapticsEnabled)
    }

    @Test("Boolean Crown value and numeric haptics value are rejected as the wrong types")
    func wrongPreferenceCategoriesFallBack() throws {
        let suite = "PickleBlastWrongPreferenceCategories-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: "pickleblast.sensitivity")
        defaults.set(0.0, forKey: "pickleblast.haptics")

        let settings = LocalStore(defaults: defaults).settings
        #expect(settings.crownSensitivity == GameSettings.defaultSensitivity)
        #expect(settings.hapticsEnabled)
    }

    @Test("Numeric string is not accepted as a best score and later valid records work")
    func corruptBestScoreFallsBack() throws {
        let suite = "PickleBlastCorruptBestScore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("999999", forKey: "pickleblast.best")
        let store = LocalStore(defaults: defaults)
        #expect(store.bestScore == 0)
        #expect(store.record(score: 725))
        #expect(store.bestScore == 725)
        #expect(LocalStore(defaults: defaults).bestScore == 725)
    }

    @Test("Valid stored settings and best score remain intact across store instances")
    func validSettingsAndBestScoreRoundTrip() throws {
        let suite = "PickleBlastStorageRoundTrip-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = LocalStore(defaults: defaults)
        first.settings = GameSettings(crownSensitivity: 1.75, hapticsEnabled: false)
        #expect(first.record(score: 12_345))

        let reloaded = LocalStore(defaults: defaults)
        #expect(reloaded.settings == GameSettings(crownSensitivity: 1.75, hapticsEnabled: false))
        #expect(reloaded.bestScore == 12_345)
    }
}
