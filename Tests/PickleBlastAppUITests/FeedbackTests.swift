import Testing
@testable import PickleBlastAppUI
import PickleBlastCore

@Suite("Restrained combo feedback")
struct FeedbackTests {
    @Test func milestonesAreLimitedAndNeverDelayReturns() {
        var policy = GameplayFeedbackPolicy()
        #expect(policy.select([.comboChanged(chain: 2, multiplier: 2)], at: 1, enabled: true) == nil)
        #expect(policy.select([.comboChanged(chain: 3, multiplier: 3)], at: 2, enabled: true) == .combo)
        #expect(policy.select([.comboChanged(chain: 5, multiplier: 5)], at: 2.1, enabled: true) == nil)
        #expect(policy.select([.paddleContact(x: 10, side: .block, centered: true)], at: 2.11, enabled: true) == .contact)
        #expect(policy.select([.comboChanged(chain: 5, multiplier: 5)], at: 3, enabled: true) == .combo)
    }
    @Test func inactiveAndPriority() {
        var policy = GameplayFeedbackPolicy()
        let events: [GameEvent] = [.comboChanged(chain: 5, multiplier: 5), .waveCleared(number: 1), .lifeLost(remaining: 2)]
        #expect(policy.select(events, at: 1, enabled: false) == nil)
        #expect(policy.select(events, at: 1, enabled: true) == .failure)
        #expect(policy.select([.targetHit(id: 1, kind: .paddle, destroyed: true, score: 100)], at: 2, enabled: true) == nil)
    }
    @Test func recoveryIsDistinctAndCleanupDoesNotSpamHaptics() {
        var policy = GameplayFeedbackPolicy()
        #expect(policy.select([.ballRecovered(remaining: 1)], at: 1, enabled: false) == nil)
        #expect(policy.select([.ballRecovered(remaining: 1)], at: 1, enabled: true) == .recovery)
        #expect(policy.select([.ballRecovered(remaining: 1)], at: 1.01, enabled: true) == nil)
        #expect(policy.select([.targetCleaned(id: 1, kind: .paddle, score: 100)], at: 2, enabled: true) == nil)
        #expect(policy.select([.lifeLost(remaining: 2)], at: 3, enabled: true) == .failure)
        #expect(policy.select([.paddleContact(x: 10, side: .block, centered: true)], at: 4, enabled: true) == .contact)
    }

}
