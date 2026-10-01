import Foundation
import Testing
@testable import PickleBlastAppUI
import PickleBlastCore

@MainActor
@Suite("Permanent presentation retirement", .serialized)
struct PresentationTeardownTests {
    @Test("Permanent exit stops callbacks without treating an interruption as exit")
    func permanentExitStopsCallbacks() {
        let suite = "PickleBlast-presentation-exit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GameSession(preferences: AppPreferences(storage: LocalStore(defaults: defaults)))
        session.setActive(true)
        session.setActive(false)
        #expect(!session.presentationEnded)
        #expect(session.scene.onFrame != nil)
        session.setActive(true)
        session.resume()
        #expect(!session.presentationEnded)
        #expect(session.scene.onFrame != nil)
        session.endPresentation()
        #expect(session.presentationEnded)
        #expect(session.scene.onFrame == nil)
        #expect(!session.active)
        #expect(session.engine.state.isPaused)
        let frozen = session.engine.state
        session.scene.onFrame?(100)
        session.drag(screenX: 0)
        session.setActive(true)
        session.resume()
        session.restart()
        #expect(!session.active)
        #expect(session.engine.state == frozen)
        session.endPresentation()
        #expect(session.presentationEnded)
    }
}
