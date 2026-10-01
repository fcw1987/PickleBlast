import SwiftUI
import PickleBlastCore

@main
struct PickleBlastApp: App {
    @StateObject private var preferences: AppPreferences = {
        #if DEBUG
        // Scripted evidence must not replace the owner's scores or settings
        // when the development build is exercised on a physical Watch.
        if DebugValidation.isValidationLaunch {
            return AppPreferences(storage: LocalStore(keyPrefix: "pickleblast.validation"))
        }
        #endif
        return AppPreferences()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(preferences)
                .tint(Neon.cyan)
                .preferredColorScheme(.dark)
        }
    }
}
