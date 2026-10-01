import SwiftUI
import SpriteKit
import PickleBlastCore
import PickleBlastRendering
#if os(watchOS)
import WatchKit
#endif

/// App surfaces use the same six colors as the SpriteKit scene.
enum Neon {
    static let cyan = Color(red: 0, green: 229.0 / 255, blue: 1)
    static let lime = Color(red: 215.0 / 255, green: 1, blue: 0)
    static let magenta = Color(red: 1, green: 46.0 / 255, blue: 209.0 / 255)
    static let orange = Color(red: 1, green: 138.0 / 255, blue: 0)
}

struct RootView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var selectedMode: GameMode? = {
        #if DEBUG
        DebugValidation.startsRun ? DebugValidation.startMode : nil
        #else
        nil
        #endif
    }()
    @State private var selectingOpponent = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let selectedMode {
                RunView(preferences: preferences, mode: selectedMode,
                        exit: { self.selectedMode = nil; selectingOpponent = false },
                        chooseOpponent: { self.selectedMode = nil; selectingOpponent = true })
            } else if selectingOpponent {
                BossSelectionView(select: { mode in
                    selectedMode = mode
                    selectingOpponent = false
                }, back: { selectingOpponent = false })
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 5) {
                            HStack(spacing: 5) {
                                ApprovedImage(key: "ball")
                                    .frame(width: 28, height: 28)
                                    .accessibilityHidden(true)
                                ApprovedImage(key: "wordmark")
                                    .aspectRatio(700.0 / 180.0, contentMode: .fit)
                                    .frame(width: 106, height: 28)
                                    .accessibilityLabel("PickleBlast")
                            }
                            Button { selectedMode = .arcade } label: {
                                HStack(spacing: 6) {
                                    ApprovedImage(key: "uiPlay").frame(width: 16, height: 16)
                                    Text("Arcade")
                                }
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Neon.lime, in: Capsule())
                                .foregroundStyle(.black)
                            }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("home.play")
                            Button { selectingOpponent = true } label: {
                                Text("Boss Rally")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(Neon.magenta, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("home.bossRally")
                            if preferences.best > 0 {
                                Text("BEST \(preferences.best)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Neon.lime)
                                    .accessibilityIdentifier("home.best")
                            }
                            NavigationLink("How to Play") { HowToPlayView() }
                                .accessibilityIdentifier("home.help")
                            NavigationLink { SettingsView() } label: { Label { Text("Settings") } icon: { ApprovedImage(key: "uiSettings").frame(width: 20, height: 20) } }
                                .accessibilityIdentifier("home.settings")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                    .background(.black)
                }
            }
        }
    }
}

private enum BossAppearance {
    static func title(_ id: BossID) -> String {
        switch id {
        case .wall: return "THE WALL"
        case .banger: return "THE BANGER"
        case .poacher: return "THE POACHER"
        }
    }

    static func cue(_ id: BossID) -> String {
        switch id {
        case .wall: return "Move the Wall, then change sides"
        case .banger: return "Read the drive, place the return"
        case .poacher: return "Bait the step, use the open side"
        }
    }

    static func color(_ id: BossID) -> Color {
        switch id {
        case .wall: return Neon.orange
        case .banger: return Neon.magenta
        case .poacher: return Neon.lime
        }
    }
}

private struct BossSelectionView: View {
    let select: (GameMode) -> Void
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("BOSS RALLY")
                    .font(.headline)
                    .foregroundStyle(Neon.cyan)
                    .accessibilityAddTraits(.isHeader)
                Button { select(.bossSeries) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ALL THREE")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(Neon.cyan)
                        Text("Wall → Banger → Poacher")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                        Text("Win each match to face the next boss.")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Neon.cyan, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Challenge all three bosses: Wall, Banger, then Poacher")
                .accessibilityIdentifier("boss.select.allThree")
                ForEach(BossID.allCases, id: \.self) { boss in
                    Button { select(.bossRally(boss)) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(BossAppearance.title(boss))
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(BossAppearance.color(boss))
                            Text(BossAppearance.cue(boss))
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(BossAppearance.color(boss), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Challenge \(BossAppearance.title(boss))")
                    .accessibilityIdentifier("boss.select.\(boss.rawValue)")
                }
                Button("Back", action: back).accessibilityIdentifier("boss.select.back")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(Color.black)
        .accessibilityIdentifier("boss.selection")
    }
}

struct HowToPlayView: View {
    private let steps: [(String, String)] = [
        ("digitalcrown.horizontal.arrow.clockwise", "Turn the Crown to move. You can also drag across the court."),
        ("figure.pickleball", "Get beneath the incoming ball. Your player returns it automatically."),
        ("arrow.up.left.and.arrow.up.right", "Meet the ball at your center to return straight. Edge contact sends it left or right."),
        ("square.grid.3x2", "Clear three dense waves. Every target breaks in one hit."),
        ("heart.fill", "Arcade gives two free ball recoveries per stage before a miss costs a life."),
        ("figure.pickleball", "Boss Rally is first to three points. Choose one opponent or All Three to face Wall, Banger, then Poacher. You get two saves per match. R counts rally returns; S shows saves."),
        ("bolt.fill", "The Wall covers steadily. The Banger's power drive leaves an opening. The Poacher commits to one side."),
        ("pause.fill", "Tap Pause at the top to take a break, restart, or return Home. After an interruption, choose Resume.")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 9) {
                        Group {
                            if index == 0 { ApprovedImage(key: "uiCrown").frame(width: 23, height: 23) }
                            else { Image(systemName: steps[index].0).foregroundStyle(Neon.cyan) }
                        }
                            .frame(width: 23)
                            .accessibilityHidden(true)
                        Text(steps[index].1).font(.callout)
                    }
                }
            }.padding(.horizontal, 6)
        }
        .navigationTitle("How to Play")
        .background(.black)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        Form {
            Section("Crown sensitivity") {
                VStack(spacing: 2) {
                Slider(value: $preferences.sensitivity,
                       in: GameSettings.minimumSensitivity...GameSettings.maximumSensitivity,
                       step: 0.25)
                    .accessibilityLabel("Crown sensitivity")
                    .accessibilityValue("\(GameSettings(crownSensitivity: preferences.sensitivity).oldMinimumPercentage) percent of previous minimum")
                    .accessibilityIdentifier("settings.sensitivity")
                Text("\(GameSettings(crownSensitivity: preferences.sensitivity).oldMinimumPercentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Neon.cyan)
                    .accessibilityIdentifier("settings.sensitivity.value")
                }
            }
            Toggle("Haptics", isOn: $preferences.haptics)
                .accessibilityIdentifier("settings.haptics")
            Section("Information") {
                NavigationLink("Privacy") { PrivacyView() }
                    .accessibilityIdentifier("settings.privacy")
                NavigationLink("Support") { SupportView() }
                    .accessibilityIdentifier("settings.support")
                Text(verbatim: PublicInformation.version)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("settings.version")
            }
            #if DEBUG
            Section("Development") {
                Toggle("Diagnostics", isOn: $preferences.diagnostics)
                Text("Collision regions, velocity, Crown input and frame timing.")
                    .font(.caption2)
            }
            #endif
        }
        .navigationTitle("Settings")
    }
}

#if os(watchOS)
/// WatchKit still exposes an explicit scene teardown hook. SpriteView retained
/// scenes after Home on Watch, so the game surface uses this localized host.
/// The initializer is deprecated, but remains available to the Watch target.
private struct WatchSceneSurface: WKInterfaceObjectRepresentable {
    let scene: SKScene
    let isPaused: Bool

    func makeWKInterfaceObject(context: Context) -> WKInterfaceSKScene {
        let host = WKInterfaceSKScene()
        host.preferredFramesPerSecond = 30
        host.presentScene(scene)
        host.isPaused = isPaused
        return host
    }

    func updateWKInterfaceObject(_ host: WKInterfaceSKScene, context: Context) {
        if host.scene !== scene { host.presentScene(scene) }
        host.isPaused = isPaused
    }

    static func dismantleWKInterfaceObject(_ host: WKInterfaceSKScene, coordinator: ()) {
        host.isPaused = true
        host.presentScene(nil)
    }
}
#endif

struct RunView: View {
    @StateObject private var session: GameSession
    @Environment(\.scenePhase) private var scenePhase
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @FocusState private var crownFocused: Bool
    #endif
    private let exit: () -> Void
    private let chooseOpponent: () -> Void
    private let pauseTargetSize: CGFloat = 44

    private var modeAccessibility: String {
        switch session.mode {
        case .arcade: return "Arcade."
        case let .bossRally(id): return "Boss Rally. \(BossAppearance.title(id))."
        case .bossSeries:
            let match = (BossID.allCases.firstIndex(of: session.engine.state.bossID) ?? 0) + 1
            return "Boss Rally. All Three. Match \(match) of \(BossID.allCases.count). \(BossAppearance.title(session.engine.state.bossID))."
        }
    }

    private var courtAccessibilityValue: String {
        let state = session.engine.state
        let activity = session.paused ? "Paused" : (state.resumeCountdown > 0 ? "Resume countdown" : session.phase.rawValue)
        switch session.mode {
        case .arcade:
            return modeAccessibility + " " + String(format: "Player x=%.3f. Crown gain %.3f. Score %d. %d lives. %d saves. %@.",
                state.playerX, session.crownGain, session.score, session.lives, state.recoveriesRemaining, activity)
        case .bossRally, .bossSeries:
            return modeAccessibility + " " + String(format: "You %d. Boss %d. %d saves. Rally %d returns. Player x=%.3f. Crown gain %.3f. Score %d. %@.",
                session.playerRallyPoints, session.opponentRallyPoints, state.recoveriesRemaining,
                state.currentRallyReturns, state.playerX, session.crownGain, session.score, activity)
        }
    }

    init(preferences: AppPreferences, mode: GameMode = .arcade,
         exit: @escaping () -> Void, chooseOpponent: @escaping () -> Void = {}) {
        _session = StateObject(wrappedValue: GameSession(preferences: preferences, mode: mode))
        self.exit = exit
        self.chooseOpponent = chooseOpponent
    }

    var body: some View {
        // Read unconsumed Watch safe-area insets outside the full-display scene.
        // Menus and controls stay in this safe region; only the game scene expands.
        GeometryReader { safeGeometry in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                if session.finished {
                    ResultsView(session: session,
                                exit: { retirePresentation(then: exit) },
                                chooseOpponent: { retirePresentation(then: chooseOpponent) })
                        .allowsHitTesting(!session.presentationEnded)
                } else {
                    GeometryReader { fullGeometry in
                        gameplaySurface(size: fullGeometry.size,
                                        headerBottom: safeGeometry.safeAreaInsets.top + pauseTargetSize)
                            .frame(width: fullGeometry.size.width, height: fullGeometry.size.height)
                            .onAppear {
                                resize(fullGeometry.size, insets: safeGeometry.safeAreaInsets)
                                #if DEBUG
                                if DebugValidation.startsRun {
                                    DebugValidation.log("PRESENTATION fullFrame=\(fullGeometry.frame(in: .global)) safeFrame=\(safeGeometry.frame(in: .global))")
                                }
                                #endif
                                session.beginIfActive(scenePhase == .active,
                                                      luminanceReduced: displayLuminanceReduced)
                                focusCrown()
                            }
                            .onChange(of: fullGeometry.size) { _, size in
                                resize(size, insets: safeGeometry.safeAreaInsets)
                            }
                            .onChange(of: safeGeometry.safeAreaInsets) { _, insets in
                                resize(fullGeometry.size, insets: insets)
                            }
                    }
                    .ignoresSafeArea(.container)
                    if !session.paused && session.phase != .blackout {
                        pauseButton
                    }
                    if session.paused {
                        pauseOverlay.allowsHitTesting(!session.presentationEnded)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, _ in updateDisplayActivity() }
        .onChange(of: session.renderingPaused) { _, _ in focusCrown() }
        #if os(watchOS)
        .onChange(of: luminanceReduced) { _, _ in updateDisplayActivity() }
        #endif
        .onDisappear { session.setActive(false) }
    }

    private func resize(_ size: CGSize, insets: EdgeInsets) {
        session.resize(size, safeTop: insets.top, safeBottom: insets.bottom,
                       safeLeading: insets.leading, safeTrailing: insets.trailing)
    }

    private func gameplaySurface(size: CGSize, headerBottom: CGFloat) -> some View {
        #if os(watchOS)
        let spriteSurface = WatchSceneSurface(scene: session.scene, isPaused: session.renderingPaused)
        #else
        let spriteSurface = SpriteView(scene: session.scene, isPaused: session.renderingPaused,
                                       preferredFramesPerSecond: 30)
        #endif
        return ZStack(alignment: .bottom) {
            // The native scene renders only. It must not consume header or
            // overlay taps before SwiftUI can deliver them to their buttons.
            spriteSurface
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            courtInput
                .frame(width: size.width, height: max(0, size.height - max(0, headerBottom)))
                .allowsHitTesting(!session.renderingPaused && !session.presentationEnded)
        }
    }

    private var courtInput: some View {
        // Keep X in full-display coordinates for the rendering projection's
        // inverse. The input region begins below Pause's safe-area hit target.
        let surface = Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { session.drag(screenX: $0.location.x) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Court")
            .accessibilityValue(courtAccessibilityValue)
            .accessibilityHint("Turn the Crown or drag to move. Returns are automatic.")
            .accessibilityIdentifier("game.court")
        #if os(watchOS)
        return surface
            .focusable(!session.renderingPaused)
            .focused($crownFocused)
            .digitalCrownRotation(
                Binding(get: { session.crownPosition }, set: { session.setCrownPosition($0) }),
                from: session.crownMinimum, through: session.crownMaximum,
                sensitivity: .high, isContinuous: false, isHapticFeedbackEnabled: false,
                onChange: { session.crownVelocity($0.velocity) })
        #else
        // Host compilation checks shared SwiftUI code; this is not a shipped Mac app.
        return surface
        #endif
    }

    private var pauseButton: some View {
        Button { session.pause() } label: {
            VStack(spacing: 0) {
                ApprovedImage(key: "uiPause")
                    .frame(width: 14, height: 14)
                    .frame(height: 20)
                Spacer(minLength: 0)
            }
            // Keep the icon aligned with the existing HUD, while extending the
            // entire 44-point target downward within the safe region.
            .frame(width: pauseTargetSize, height: pauseTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pause game")
        .accessibilityHint("Resume, restart, or return Home")
        .accessibilityIdentifier("game.pause")
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    Text("PAUSED").font(.headline).foregroundStyle(Neon.cyan)
                    Button {
                        updateDisplayActivity()
                        session.resume()
                        focusCrown()
                    } label: {
                        Text("Resume")
                            .frame(maxWidth: .infinity, minHeight: pauseTargetSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Neon.lime)
                    .foregroundStyle(.black)
                    .disabled(!session.active)
                    .accessibilityIdentifier("pause.resume")
                    Button {
                        retirePresentation(then: exit)
                    } label: {
                        Label { Text("Home") } icon: { ApprovedImage(key: "uiClose").frame(width: 18, height: 18) }
                            .frame(maxWidth: .infinity, minHeight: pauseTargetSize)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("pause.home")
                    Button {
                        updateDisplayActivity()
                        session.restart()
                        focusCrown()
                    } label: {
                        Label { Text("Restart") } icon: { ApprovedImage(key: "uiRestart").frame(width: 18, height: 18) }
                            .frame(maxWidth: .infinity, minHeight: pauseTargetSize)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("pause.restart")
                }.padding(.horizontal, 12)
            }
        }
    }

    private var displayLuminanceReduced: Bool {
        #if os(watchOS)
        luminanceReduced
        #else
        false
        #endif
    }

    private func updateDisplayActivity() {
        session.setActive(scenePhase == .active, luminanceReduced: displayLuminanceReduced)
    }

    private func retirePresentation(then navigate: @escaping () -> Void) {
        guard !session.presentationEnded else { return }
        session.endPresentation()
        navigate()
    }

    private func focusCrown() {
        #if os(watchOS)
        crownFocused = !session.renderingPaused
        #endif
    }
}

struct ResultsView: View {
    @ObservedObject var session: GameSession
    let exit: () -> Void
    let chooseOpponent: () -> Void

    private var bossRallyID: BossID? {
        if case let .bossRally(id) = session.mode { return id }
        return nil
    }

    private var isSeries: Bool { session.mode == .bossSeries }
    private var isBossRally: Bool { session.mode.isBossRally }

    private var replayTitle: String {
        if isSeries { return session.engine.state.won ? "Play All Three Again" : "Retry All Three" }
        if isBossRally { return session.engine.state.won ? "Rematch" : "Retry" }
        return "Play Again"
    }

    private var resultTitle: String {
        guard session.engine.state.won else {
            if isBossRally { return "\(BossAppearance.title(session.engine.state.bossID))\nWINS" }
            return "GAME OVER"
        }
        if isSeries { return "ALL THREE\nARE DOWN" }
        return "\(BossAppearance.title(bossRallyID ?? .wall))\nIS DOWN"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(resultTitle)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(session.engine.state.won ? Neon.magenta : Neon.cyan)
                if isSeries {
                    let wins = session.engine.state.completedBossMatches.filter(\.won).count
                    Text("\(wins) OF \(BossID.allCases.count) BOSSES DEFEATED")
                        .font(.caption.bold())
                        .foregroundStyle(Neon.cyan)
                        .accessibilityIdentifier("results.seriesProgress")
                }
                if isBossRally {
                    Text("YOU \(session.playerRallyPoints) · BOSS \(session.opponentRallyPoints)")
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Neon.cyan)
                        .accessibilityIdentifier("results.matchScore")
                }
                Text("\(session.score)")
                    .font(.system(size: isBossRally ? 24 : 35, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Neon.lime)
                    .accessibilityLabel("Final score \(session.score)")
                    .accessibilityIdentifier("results.score")
                if session.newBest {
                    Text(isBossRally ? "NEW BOSS BEST" : "NEW HIGH SCORE")
                        .font(.caption.bold()).foregroundStyle(Neon.lime)
                }
                if isSeries {
                    ForEach(session.engine.state.completedBossMatches, id: \.bossID) { match in
                        VStack(spacing: 2) {
                            Text("\(BossAppearance.title(match.bossID)) · \(match.won ? "WIN" : "LOSS")")
                                .foregroundStyle(BossAppearance.color(match.bossID))
                            Text("\(match.score) POINTS · BEST RALLY \(match.longestRallyReturns)")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("results.seriesMatch.\(match.bossID.rawValue)")
                    }
                } else if let bossRallyID {
                    let record = session.preferences.bossRecord(for: bossRallyID)
                    Text("WINS \(record.wins) · BEST \(record.bestScore)")
                        .font(.caption2.monospacedDigit())
                        .accessibilityIdentifier("results.bossRecord")
                    Text("BEST RALLY \(record.longestRally) RETURNS")
                        .font(.caption2.monospacedDigit())
                        .accessibilityIdentifier("results.longestRally")
                } else {
                    Text("PERSONAL BEST \(session.preferences.best)")
                        .font(.caption2.monospacedDigit())
                        .accessibilityIdentifier("results.best")
                }
                Button(replayTitle) {
                    session.restart()
                }
                    .buttonStyle(.borderedProminent)
                    .tint(Neon.lime)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("results.replay")
                if isBossRally {
                    Button("Choose Opponent", action: chooseOpponent)
                        .accessibilityIdentifier("results.chooseOpponent")
                }
                Button("Home", action: exit).accessibilityIdentifier("results.home")
            }.padding(.horizontal, 10)
        }
        .accessibilityIdentifier("results")
    }
}

/// One cached decode per menu asset, using the same supplied atlas resources as SpriteKit.
private enum MenuArt {
    static let library = TextureLibrary()
    static let images: [String: CGImage] = Dictionary(uniqueKeysWithValues:
        ["ball", "wordmark", "uiPlay", "uiPause", "uiRestart", "uiSettings", "uiClose", "uiCrown"].map {
            ($0, library.supporting($0).cgImage())
        })
}
private struct ApprovedImage: View {
    let key: String
    var body: some View { Image(decorative: MenuArt.images[key]!, scale: 2).resizable().interpolation(.high) }
}
