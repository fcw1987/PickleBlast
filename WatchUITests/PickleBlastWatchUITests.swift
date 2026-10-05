import XCTest

/// Genuine Watch UI tests: launch normally and synthesize touch/Crown events.
/// Ordinary navigation/settings use no fixtures. The explicitly named controlled
/// input tests freeze DEBUG simulation time to isolate slow synthetic Crown calls.
/// The separately named scripted full-run test opts into the DEBUG autoplayer.
final class PickleBlastWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoordinatePauseTapResumeAndHomeInEveryMode() throws {
        for mode in ["arcade", "wall", "dinker", "lobber"] {
            let app = launchHome()
            if mode == "arcade" { _ = startRun(app) }
            else {
                app.buttons["home.bossRally"].tap()
                let choice = app.buttons["boss.select.\(mode)"]
                reveal(choice, in: app); choice.tap()
                XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 5))
            }
            let pause = app.buttons["game.pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(pause.frame.width, 43.9)
            XCTAssertGreaterThanOrEqual(pause.frame.height, 43.9)
            XCTAssertGreaterThanOrEqual(pause.frame.minY, app.frame.minY)
            // A literal screen tap near the lower edge, away from the 14pt
            // icon, proves the expanded target receives a physical touch.
            // Identifier.tap() alone can hide native-host gesture conflicts.
            func tapPauseEdge() {
                let frame = pause.frame
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                    dx: frame.midX - app.frame.minX,
                    dy: frame.minY - app.frame.minY + 36)).tap()
            }
            tapPauseEdge()
            let resume = app.buttons["pause.resume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 5), "Pause edge tap in \(mode)")
            capture("coordinate-pause-\(mode)", app: app)
            resume.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            let court = element("game.court", in: app)
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let value = court.value as? String ?? ""
                return !value.contains("Resume countdown") && !value.contains("Paused") && court.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            tapPauseEdge()
            let home = app.buttons["pause.home"]
            reveal(home, in: app)
            home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testOrdinaryPauseScrollRestartResetsEachMode() throws {
        let app = launchHome()
        for mode in ["arcade", "banger", "dinker", "lobber"] {
            if mode == "arcade" { _ = startRun(app) }
            else {
                app.buttons["home.bossRally"].tap()
                let choice = app.buttons["boss.select.\(mode)"]
                reveal(choice, in: app); choice.tap()
            }
            let court = element("game.court", in: app)
            XCTAssertTrue(court.waitForExistence(timeout: 5))
            // Change authoritative position through ordinary touch so reset
            // cannot pass merely because the initial score is still zero.
            dragAcross(court, from: 0.5, to: 0.7)
            XCTAssertGreaterThan(try playerX(court), 11)
            app.buttons["game.pause"].tap()
            XCTAssertTrue(app.buttons["pause.resume"].waitForExistence(timeout: 5))
            capture("ordinary-restart-before-scroll-\(mode)", app: app)
            let restart = app.buttons["pause.restart"]
            reveal(restart, in: app)
            XCTAssertLessThanOrEqual(restart.frame.maxY, app.frame.maxY - 4)
            capture("ordinary-restart-visible-\(mode)", app: app)
            restart.tap()

            let reset = try value(court)
            XCTAssertEqual(try playerX(court), 10, accuracy: 0.001, reset)
            if mode == "arcade" {
                XCTAssertTrue(reset.hasPrefix("Arcade."), reset)
                XCTAssertTrue(reset.contains("Score 0. 3 lives. 2 saves."), reset)
            } else {
                XCTAssertTrue(reset.contains("Boss Rally. THE \(mode.uppercased())."), reset)
                XCTAssertTrue(reset.contains("You 0. Boss 0. 0 saves. Rally 0 returns."), reset)
                XCTAssertTrue(reset.contains("Score 0."), reset)
            }
            XCTAssertFalse(reset.contains("Paused"), reset)
            XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testBossRallyHomeOrderRosterAndBack() throws {
        let app = launchHome()
        XCTAssertLessThan(app.buttons["home.bossRally"].frame.midY, app.buttons["home.play"].frame.midY,
                          "Boss Rally is the first game mode, with Arcade immediately below")
        capture("boss-rally-first-home", app: app)
        app.buttons["home.bossRally"].tap()
        let menuAppeared = app.buttons["boss.select.wall"].waitForExistence(timeout: 10)
        if !menuAppeared {
            capture("boss-rally-first-transition-failure", app: app)
        }
        XCTAssertTrue(menuAppeared,
                      "Single Boss Rally tap must open the chooser. Home=\(app.buttons["home.bossRally"].exists), chooser=\(element("boss.selection", in: app).exists), court=\(element("game.court", in: app).exists).\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["boss.select.allThree"].exists)
        XCTAssertFalse(app.staticTexts["Play All Three"].exists)
        let expected = ["wall", "banger", "poacher", "dinker", "lobber"].map { "boss.select.\($0)" }
        let actual = app.buttons.allElementsBoundByIndex.map(\.identifier).filter { expected.contains($0) }
        XCTAssertEqual(actual, expected, "Opponent order also defines Play Next order")
        for identifier in expected {
            let choice = app.buttons[identifier]
            reveal(choice, in: app)
            XCTAssertTrue(choice.isEnabled)
            capture("roster-\(identifier)", app: app)
        }
        let back = app.buttons["boss.select.back"]
        reveal(back, in: app); back.tap()
        XCTAssertTrue(app.buttons["home.bossRally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.play"].isHittable)
    }

    @MainActor
    func testScriptedAllThreeAutomaticProgressionAndFinalResult() throws {
        let app = XCUIApplication()
        // Retain coverage of the internal legacy series using an explicit DEBUG
        // launch. The obsolete series is no longer offered in ordinary menus.
        // This public-input oracle is not a human balance model.
        app.launchArguments = ["--validation-series", "--validation-autoplay"]
        app.launchEnvironment = [:]
        app.launch()
        let court = element("game.court", in: app)
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        for (index, boss) in ["THE WALL", "THE BANGER", "THE POACHER"].enumerated() {
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (court.value as? String ?? "").contains("Match \(index + 1) of 3. \(boss)")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 80), .completed)
            capture("scripted-all-three-match-\(index + 1)", app: app)
            XCTAssertFalse(element("results", in: app).exists)
        }
        XCTAssertTrue(element("results", in: app).waitForExistence(timeout: 90))
        XCTAssertEqual(element("results.seriesProgress", in: app).label, "3 OF 3 BOSSES DEFEATED")
        XCTAssertEqual(element("results.matchScore", in: app).label, "YOU 3 · BOSS 0")
        capture("scripted-all-three-win", app: app)
        let opponents = app.buttons["results.chooseOpponent"]
        reveal(opponents, in: app); opponents.tap()
        XCTAssertTrue(app.buttons["boss.select.wall"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["boss.select.allThree"].exists)
    }

    @MainActor
    func testScriptedPlayNextAdvancesAllFiveOpponents() throws {
        // Ordinary menu/result controls, with the existing DEBUG public-input
        // oracle playing the rallies. No score or victory state is injected.
        let app = launchHome(arguments: ["--validation-autoplay", "--validation-manual-start"])
        app.buttons["home.bossRally"].tap()
        let wall = app.buttons["boss.select.wall"]
        reveal(wall, in: app); wall.tap()
        let court = element("game.court", in: app)
        let results = element("results", in: app)
        let opponents = ["wall", "banger", "poacher", "dinker", "lobber"]
        for (index, id) in opponents.enumerated() {
            XCTAssertTrue(court.waitForExistence(timeout: 5))
            assertFreshBossMatch(id, court: court)
            XCTAssertTrue(results.waitForExistence(timeout: 90), "Victory against \(id)")
            XCTAssertEqual(element("results.matchScore", in: app).label, "YOU 3 · BOSS 0")
            let next = app.buttons["results.playNext"]
            if index < opponents.count - 1 {
                let nextID = opponents[index + 1]
                reveal(next, in: app)
                XCTAssertTrue(next.label.contains("Play Next"), next.label)
                XCTAssertTrue(next.label.uppercased().contains(nextID.uppercased()), next.label)
                XCTAssertFalse(element("results.sequenceComplete", in: app).exists)
                capture("play-next-\(id)-to-\(nextID)", app: app)
                next.tap()
                XCTAssertFalse(results.exists, "Play Next must leave results for a fresh match")
            } else {
                XCTAssertFalse(next.exists, "The final opponent must not silently wrap to The Wall")
                let complete = element("results.sequenceComplete", in: app)
                reveal(complete, in: app)
                XCTAssertEqual(complete.label, "Final opponent defeated")
                capture("play-next-final-lobber", app: app)
            }
        }
        let home = app.buttons["results.home"]
        reveal(home, in: app); home.tap()
        XCTAssertTrue(app.buttons["home.bossRally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.play"].isHittable)
    }

    @MainActor
    func testOrdinaryCenteredAutomaticReturn() throws {
        let app = launchHome()
        let court = startRun(app)
        // No DEBUG controller or injected state: the untouched centered player
        // automatically returns the first serve and earns a real target hit.
        let scored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = court.value as? String ?? ""
            return value.contains("Score ") && !value.contains("Score 0.")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scored], timeout: 15), .completed)
        XCTAssertTrue((court.value as? String ?? "").contains("3 lives"))
        capture("ordinary-centered-return", app: app)
    }

    @MainActor
    func testOrdinaryFreeRecoveriesThenChargedMiss() throws {
        let app = launchHome()
        let court = startRun(app)
        dragAcross(court, from: 0.5, to: 0.02)
        func awaitStatus(_ fragment: String) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (court.value as? String ?? "").contains(fragment)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed)
        }
        awaitStatus("3 lives. 1 saves.")
        let savedScore = try XCTUnwrap((court.value as? String)?.components(separatedBy: "Score ").last?.components(separatedBy: ".").first.flatMap(Int.init))
        capture("ordinary-first-free-recovery", app: app)
        awaitStatus("3 lives. 0 saves.")
        capture("ordinary-second-free-recovery", app: app)
        awaitStatus("2 lives. 0 saves.")
        capture("ordinary-charged-miss", app: app)
        let afterMisses = try XCTUnwrap((court.value as? String)?.components(separatedBy: "Score ").last?.components(separatedBy: ".").first.flatMap(Int.init))
        XCTAssertEqual(afterMisses, savedScore, "Recoveries and a charged miss preserve already earned score")
    }

    @MainActor
    func testHomePlayPauseResumeAndHome() throws {
        let app = launchHome()
        capture("ordinary-home", app: app)
        let court = startRun(app)

        app.buttons["game.pause"].tap()
        let resume = app.buttons["pause.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(resume.isEnabled)
        capture("ordinary-pause", app: app)

        resume.tap()
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
        // The core intentionally ignores gameplay input during the resume
        // countdown. Its completion is observable, so do not race it or sleep.
        let countdownFinished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let status = court.value as? String ?? ""
            return status.contains("Player x=") && !status.contains("Resume countdown") && !status.contains("Paused")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [countdownFinished], timeout: 5), .completed)
        capture("ordinary-resumed-court", app: app)

        app.buttons["game.pause"].tap()
        let home = app.buttons["pause.home"]
        reveal(home, in: app)
        home.tap()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testControlledTouchThenCrownReversesAtLeftBoundary() throws {
        let app = launchControls()
        let court = element("game.court", in: app)
        // Exercise focus restoration after the actual pause/resume UI before
        // checking the first reverse Crown movement. DEBUG holds gameplay still.
        app.buttons["game.pause"].tap()
        XCTAssertTrue(app.buttons["pause.resume"].waitForExistence(timeout: 5))
        app.buttons["pause.resume"].tap()
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
        dragAcross(court, from: 0.5, to: 0.02)
        let left = try playerX(court)
        XCTAssertLessThan(left, 2, "Touch reaches the authoritative left boundary")

        // Excess input into the wall must not accumulate an invisible offset.
        XCUIDevice.shared.rotateDigitalCrown(delta: -0.05, velocity: 3)
        XCTAssertEqual(try playerX(court), left, accuracy: 0.02)
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.125, velocity: 3)
        waitForPlayer(court, description: "The first reverse Crown movement leaves the left boundary") {
            $0 > left + 0.005
        }
        capture("controlled-left-reversal", app: app)
    }

    @MainActor
    func testControlledTouchThenCrownReversesAtRightBoundary() throws {
        let app = launchControls()
        // Leaving the game and starting again must restore Crown focus too.
        app.buttons["game.pause"].tap()
        let home = app.buttons["pause.home"]
        reveal(home, in: app)
        home.tap()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        let court = startRun(app)
        dragAcross(court, from: 0.5, to: 0.98)
        let right = try playerX(court)
        XCTAssertGreaterThan(right, 18, "Touch reaches the authoritative right boundary")

        XCUIDevice.shared.rotateDigitalCrown(delta: 0.05, velocity: 3)
        XCTAssertEqual(try playerX(court), right, accuracy: 0.02)
        XCUIDevice.shared.rotateDigitalCrown(delta: -0.125, velocity: 3)
        waitForPlayer(court, description: "The first reverse Crown movement leaves the right boundary") {
            $0 < right - 0.005
        }
        capture("controlled-right-reversal", app: app)
    }

    @MainActor
    func testPrivacyAndSupportScrollBackPreserveSettings() throws {
        let app = launchHome()
        let best = element("home.best", in: app)
        let originalBest = best.exists ? best.label : nil
        openSettings(app)
        let sensitivity = element("settings.sensitivity", in: app)
        reveal(sensitivity, in: app)
        let originalSensitivity = try value(sensitivity)
        let haptics = element("settings.haptics", in: app)
        reveal(haptics, in: app)
        let originalHaptics = try value(haptics)
        let privacy = element("settings.privacy", in: app)
        scrollInformationTo(privacy, in: app); privacy.tap()
        XCTAssertTrue(element("privacy.offline", in: app).waitForExistence(timeout: 5))
        let privacyURL = element("privacy.url", in: app)
        scrollInformationTo(privacyURL, in: app)
        XCTAssertTrue(privacyURL.label.contains("https://fcw1987.github.io/PickleBlast/privacy/"))
        capture("privacy-offline-top", app: app)
        scrollInformationTo(element("privacy.end", in: app), in: app)
        XCTAssertTrue(element("privacy.end", in: app).isHittable)
        capture("privacy-offline-bottom", app: app)
        let privacyBack = app.buttons["privacy.back"]
        scrollInformationTo(privacyBack, in: app); privacyBack.tap()
        let support = element("settings.support", in: app)
        scrollInformationTo(support, in: app); support.tap()
        XCTAssertTrue(element("support.offline", in: app).waitForExistence(timeout: 5))
        let supportVersion = element("support.version", in: app)
        XCTAssertTrue(supportVersion.label.hasPrefix("Version "))
        let supportURL = element("support.url", in: app)
        scrollInformationTo(supportURL, in: app)
        XCTAssertTrue(supportURL.label.contains("https://fcw1987.github.io/PickleBlast/support/"))
        capture("support-offline-top", app: app)
        scrollInformationTo(element("support.help.public", in: app), in: app)
        XCTAssertTrue(element("support.help.public", in: app).label.contains("reports are public"))
        let supportBack = app.buttons["support.back"]
        scrollInformationTo(supportBack, in: app)
        capture("support-offline-bottom", app: app)
        supportBack.tap()
        let version = element("settings.version", in: app)
        scrollInformationTo(version, in: app)
        XCTAssertTrue(version.label.hasPrefix("Version "), version.label)
        XCTAssertTrue(version.label.contains("(build "), version.label)
        capture("settings-information", app: app)
        scrollInformationTo(sensitivity, in: app, towardTop: true)
        reveal(sensitivity, in: app)
        XCTAssertEqual(try value(sensitivity), originalSensitivity)
        reveal(haptics, in: app)
        XCTAssertEqual(try value(haptics), originalHaptics)

        // Verify durable settings and Arcade best as well as the in-memory UI.
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 10))
        XCTAssertEqual(best.exists ? best.label : nil, originalBest)
        openSettings(app)
        reveal(sensitivity, in: app)
        XCTAssertEqual(try value(sensitivity), originalSensitivity)
        reveal(haptics, in: app)
        XCTAssertEqual(try value(haptics), originalHaptics)
    }

    @MainActor
    func testPrivacyAndSupportShowReadableAddressesWithoutWebLaunchControls() throws {
        let app = launchHome()
        openSettings(app)
        for page in ["privacy", "support"] {
            let entry = element("settings.\(page)", in: app)
            scrollInformationTo(entry, in: app); entry.tap()
            XCTAssertTrue(element("\(page).offline", in: app).waitForExistence(timeout: 5))
            let address = element("\(page).url", in: app)
            scrollInformationTo(address, in: app)
            XCTAssertTrue(address.label.contains("https://fcw1987.github.io/PickleBlast/\(page)/"))
            let fallback = element("\(page).fallback", in: app)
            scrollInformationTo(fallback, in: app)
            XCTAssertTrue(fallback.label.contains("browser on another device"))
            XCTAssertFalse(app.buttons["\(page).open"].exists)
            XCTAssertFalse(element("\(page).linkStatus", in: app).exists)
            capture("\(page)-readable-address", app: app)
            // Return through the normal navigation bar; the longer test also
            // proves every offline paragraph and the bottom Back control.
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.exists)
            back.tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func scrollInformationTo(_ target: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        // The complete policy, including readable source URLs, takes more
        // short drags on the 40 mm display. Keep the end-of-content assertion.
        for _ in 0..<120 {
            if target.exists && target.isHittable { return }
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
            if (target.exists && target.frame.minY < 52) || (!target.exists && towardTop) {
                upper.press(forDuration: 0.05, thenDragTo: lower,
                            withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                lower.press(forDuration: 0.05, thenDragTo: upper,
                            withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Information remains scrollable: \(target.identifier)")
    }

    @MainActor
    func testSettingsPersistAcrossRelaunch() throws {
        let app = launchHome()
        openSettings(app)
        let sensitivity = element("settings.sensitivity", in: app)
        reveal(sensitivity, in: app)
        let originalSensitivity = try value(sensitivity)
        let originalPercentage = try sensitivityPercentage(originalSensitivity)
        sensitivity.adjust(toNormalizedSliderPosition: originalPercentage == 15 ? 1 : 0)
        waitForValueChange(sensitivity, from: originalSensitivity)
        let changedSensitivity = try value(sensitivity)
        let haptics = element("settings.haptics", in: app)
        reveal(haptics, in: app)
        let originalHaptics = try value(haptics)
        haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        waitForValueChange(haptics, from: originalHaptics)
        let changedHaptics = try value(haptics)

        // Termination and a new ordinary launch test LocalStore persistence.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 10))
        openSettings(app)
        let relaunchedSensitivity = element("settings.sensitivity", in: app)
        reveal(relaunchedSensitivity, in: app)
        XCTAssertEqual(try value(relaunchedSensitivity), changedSensitivity)
        capture("ordinary-sensitivity-persisted", app: app)

        // Restore the slider while it is fully visible. Scrolling to haptics
        // can leave it clipped behind the small Watch's navigation header.
        // Assert cleanup after both attempts so slider failure cannot skip haptics.
        let sensitivityRestored = restoreSensitivity(relaunchedSensitivity, in: app,
            percentage: originalPercentage, expected: originalSensitivity)
        let relaunchedHaptics = element("settings.haptics", in: app)
        reveal(relaunchedHaptics, in: app)
        XCTAssertEqual(try value(relaunchedHaptics), changedHaptics)
        capture("ordinary-haptics-persisted", app: app)
        if reveal(relaunchedHaptics, in: app, failIfHidden: false),
           try value(relaunchedHaptics) != originalHaptics {
            relaunchedHaptics.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
        let hapticsRestored = valueBecomes(relaunchedHaptics, equalTo: originalHaptics)
        XCTAssertTrue(sensitivityRestored,
            "Restore sensitivity: expected \(originalSensitivity), actual \(String(describing: relaunchedSensitivity.value)), frame \(relaunchedSensitivity.frame), app frame \(app.frame)")
        XCTAssertTrue(hapticsRestored,
            "Restore haptics: expected \(originalHaptics), actual \(String(describing: relaunchedHaptics.value)), frame \(relaunchedHaptics.frame)")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 10))
        openSettings(app)
        let restoredSensitivity = element("settings.sensitivity", in: app)
        reveal(restoredSensitivity, in: app)
        XCTAssertEqual(try value(restoredSensitivity), originalSensitivity)
        let restoredHaptics = element("settings.haptics", in: app)
        reveal(restoredHaptics, in: app)
        XCTAssertEqual(try value(restoredHaptics), originalHaptics)
        capture("ordinary-settings-restored", app: app)
    }

    @MainActor
    func testOrdinaryGameOverAndReplayTwice() throws {
        let app = launchHome()
        _ = startRun(app)

        // Move aside through normal touch input so automatic center returns do
        // not sustain the rally. No fixture or injected life/score forces defeat.
        for replayNumber in 1...2 {
            let results = element("results", in: app)
            let court = element("game.court", in: app)
            for remainingLives in stride(from: 2, through: 0, by: -1) {
                if results.exists { break }
                dragAcross(court, from: 0.5, to: 0.02)
                let missed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    if results.exists { return true }
                    guard court.exists, let status = court.value as? String else { return false }
                    // A slow accessibility query can observe more than one
                    // completed miss; never require a transient life count.
                    return (0...remainingLives).contains { status.contains("\($0) lives") }
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [missed], timeout: 20), .completed,
                               "Normal touch movement should allow the next miss")
            }
            XCTAssertTrue(results.waitForExistence(timeout: 5),
                          "Ordinary run \(replayNumber) should reach results")
            XCTAssertTrue(app.staticTexts["GAME OVER"].exists)
            capture("ordinary-game-over-\(replayNumber)", app: app)

            let replay = app.buttons["results.replay"]
            reveal(replay, in: app)
            replay.tap()
            XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
            capture("ordinary-replay-\(replayNumber)", app: app)
        }
    }

    @MainActor
    func testScriptedFullRunVictoryAndReplay() throws {
        let app = XCUIApplication()
        // This is scripted gameplay using public core movement inputs, distinct
        // from ordinary UI navigation and static fixture screenshots.
        app.launchArguments = ["--validation-autoplay"]
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 10))
        let results = element("results", in: app)
        XCTAssertTrue(results.waitForExistence(timeout: 240), "Scripted full run should reach results")

        let visibleText = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(visibleText.contains("THE WALL IS DOWN"), visibleText)
        let scoreLabel = element("results.score", in: app).label
        XCTAssertTrue(scoreLabel.hasPrefix("Final score"), scoreLabel)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(Int(scoreLabel.filter(\.isNumber))), 20_050, "All authored targets plus wave/boss awards must be represented; exact collision-event accounting is covered in the deterministic core run.")
        capture("scripted-dense-full-run-victory", app: app)

        let replay = app.buttons["results.replay"]
        reveal(replay, in: app)
        replay.tap()
        XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
        capture("scripted-full-run-replay", app: app)
    }

    @MainActor
    func testInstalledAppIconAndOpenFromWatchLauncher() throws {
        let app = launchHome()
        // XCUIDeviceButton.home and pressButton are provided by the installed
        // Watch XCUIAutomation headers. Carousel's identifier is verified from
        // the installed Watch runtime's CoreServices/Carousel.app/Info.plist.
        XCUIDevice.shared.press(.home)
        // The first press returns to Smart Stack on this runtime. Root verified
        // that screen in the failed capture; the second press opens the app grid.
        XCUIDevice.shared.press(.home)
        let launcher = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let icon = launcher.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "PickleBlast", "com.pickleblast.watchapp")
        ).firstMatch

        // Newly installed apps can be below the visible portion of the grid or
        // list. Only capture an app-icon claim after locating its actual item.
        for _ in 0..<10 {
            if icon.exists && icon.isHittable { break }
            launcher.swipeUp()
        }
        let launcherTree = XCTAttachment(string: launcher.debugDescription)
        launcherTree.name = "watch-launcher-accessibility"
        launcherTree.lifetime = .keepAlways
        add(launcherTree)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = icon.exists && icon.isHittable ? "installed-pickleblast-app-icon" : "watch-launcher-icon-search-failed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(icon.exists && icon.isHittable, "Installed PickleBlast icon must be visible in the Watch launcher")

        icon.tap()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 10))
        capture("ordinary-opened-from-watch-icon", app: app)
    }

    @MainActor
    func testBossRallySelectEachOpponentPauseResumeAndHome() throws {
        let app = launchHome()
        for id in ["wall", "banger", "poacher", "dinker", "lobber"] {
            let rally = app.buttons["home.bossRally"]
            reveal(rally, in: app)
            rally.tap()
            // Wait for actionable menu content across Watch accessibility trees.
            XCTAssertTrue(app.buttons["boss.select.wall"].waitForExistence(timeout: 10),
                          app.debugDescription)
            XCTAssertFalse(app.buttons["boss.select.allThree"].exists)
            let choice = app.buttons["boss.select.\(id)"]
            reveal(choice, in: app)
            capture("ordinary-boss-select-\(id)", app: app)
            choice.tap()
            let court = element("game.court", in: app)
            XCTAssertTrue(court.waitForExistence(timeout: 5))
            XCTAssertTrue((court.value as? String ?? "").lowercased().contains(id))
            XCTAssertTrue((court.value as? String ?? "").contains("Boss Rally"))
            capture("ordinary-boss-\(id)", app: app)
            app.buttons["game.pause"].tap()
            XCTAssertTrue(app.buttons["pause.resume"].waitForExistence(timeout: 5))
            app.buttons["pause.resume"].tap()
            XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let status = court.value as? String ?? ""
                return !status.contains("Resume countdown") && !status.contains("Paused")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            capture("ordinary-boss-resumed-\(id)", app: app)
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
        _ = startRun(app)
        XCTAssertTrue((element("game.court", in: app).value as? String ?? "").contains("Arcade"))
        capture("ordinary-arcade-after-boss-selection", app: app)
    }

    @MainActor
    func testCrownFocusAfterSelectingEachBoss() throws {
        // Freeze simulation only; selection scrolling and both Crown directions
        // use the native controls and the authoritative position binding.
        let app = launchHome(arguments: ["--validation-controls", "--validation-manual-start"])
        for id in ["wall", "banger", "poacher", "dinker", "lobber"] {
            app.buttons["home.bossRally"].tap()
            let choice = app.buttons["boss.select.\(id)"]
            reveal(choice, in: app); choice.tap()
            let court = element("game.court", in: app)
            XCTAssertTrue(court.waitForExistence(timeout: 5))
            let initial = try playerX(court)
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.125, velocity: 3)
            waitForPlayer(court, description: "Crown focuses gameplay after selecting \(id)") {
                $0 > initial + 0.05
            }
            let moved = try playerX(court)
            XCUIDevice.shared.rotateDigitalCrown(delta: -0.125, velocity: 3)
            waitForPlayer(court, description: "Crown reverses after selecting \(id)") {
                $0 < moved - 0.05
            }
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testSystemInterruptionRequiresResumeInBothModes() throws {
        let app = launchHome()
        for mode in ["arcade", "banger"] {
            if mode == "arcade" { _ = startRun(app) }
            else {
                app.buttons["home.bossRally"].tap()
                let choice = app.buttons["boss.select.banger"]
                reveal(choice, in: app); choice.tap()
            }
            let startingCourt = element("game.court", in: app)
            XCTAssertTrue(startingCourt.waitForExistence(timeout: 5))
            let identity = (startingCourt.value as? String ?? "").lowercased()
            XCTAssertTrue(identity.contains(mode == "arcade" ? "arcade" : "boss rally"))
            if mode == "banger" { XCTAssertTrue(identity.contains("banger")) }
            for cycle in 0..<2 {
                XCUIDevice.shared.press(.home)
                let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.state != .runningForeground
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 5), .completed)
                app.activate()
                let resume = app.buttons["pause.resume"]
                XCTAssertTrue(resume.waitForExistence(timeout: 5))
                capture("interrupted-\(mode)-\(cycle)", app: app)
                resume.tap()
                let court = element("game.court", in: app)
                let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let status = court.value as? String ?? ""
                    return court.exists && !status.contains("Resume countdown") && !status.contains("Paused")
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            }
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testBossRallyOrdinaryDefeatRetryAndChooseOpponent() throws {
        let app = launchHome()
        let rally = app.buttons["home.bossRally"]
        reveal(rally, in: app); rally.tap()
        let wall = app.buttons["boss.select.wall"]
        reveal(wall, in: app); wall.tap()
        let court = element("game.court", in: app)
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        let results = element("results", in: app)
        for replay in 0..<2 {
            for _ in 0..<6 {
                if results.exists { break }
                dragAcross(court, from: 0.5, to: 0.02)
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    results.exists || (court.value as? String ?? "").contains("ready.")
                }, object: nil)
                _ = XCTWaiter.wait(for: [changed], timeout: 5)
            }
            XCTAssertTrue(results.waitForExistence(timeout: 20))
            XCTAssertEqual(element("results.matchScore", in: app).label, "YOU 0 · BOSS 3")
            XCTAssertFalse(app.buttons["results.playNext"].exists, "Defeat requires retry or choosing an opponent")
            XCTAssertFalse(element("results.sequenceComplete", in: app).exists)
            capture("ordinary-boss-defeat-\(replay)", app: app)
            if replay == 0 {
                let retry = app.buttons["results.replay"]
                reveal(retry, in: app)
                XCTAssertEqual(retry.label, "Retry")
                retry.tap()
                XCTAssertTrue(court.waitForExistence(timeout: 5))
                assertFreshBossMatch("wall", court: court)
            }
        }
        let choose = app.buttons["results.chooseOpponent"]
        reveal(choose, in: app); choose.tap()
        XCTAssertTrue(element("boss.selection", in: app).waitForExistence(timeout: 5))
        capture("ordinary-boss-choose-after-defeat", app: app)
    }

    @MainActor
    func testBossRallyStartsWithoutSavesAndThirdPointEndsMatch() throws {
        let app = launchHome()
        app.buttons["home.bossRally"].tap()
        let choice = app.buttons["boss.select.wall"]
        reveal(choice, in: app); choice.tap()
        let court = element("game.court", in: app)
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        XCTAssertFalse((court.value as? String ?? "").contains("lives"))
        dragAcross(court, from: 0.5, to: 0.02)
        // No return streak has earned a save. Ordinary misses must award points
        // immediately, and the third genuine miss decides the match.
        XCTAssertTrue((court.value as? String ?? "").contains("0 saves."))
        for status in ["You 0. Boss 1. 0 saves.", "You 0. Boss 2. 0 saves."] {
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (court.value as? String ?? "").contains(status)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 8), .completed, status)
            capture("rally-score-" + status, app: app)
        }
        XCTAssertTrue(element("results", in: app).waitForExistence(timeout: 8))
        XCTAssertEqual(element("results.matchScore", in: app).label, "YOU 0 · BOSS 3")
        capture("rally-third-opponent-point", app: app)
        let retry = app.buttons["results.replay"]
        reveal(retry, in: app); retry.tap()
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        XCTAssertTrue((court.value as? String ?? "").contains("You 0. Boss 0. 0 saves."))
    }

    @MainActor func testScriptedWallRallyVictoryRematchAndChooseOpponent() throws { try scriptedBossVictory("wall") }
    @MainActor func testScriptedBangerRallyVictoryRematchAndChooseOpponent() throws { try scriptedBossVictory("banger") }
    @MainActor func testScriptedPoacherRallyVictoryRematchAndChooseOpponent() throws { try scriptedBossVictory("poacher") }
    @MainActor func testScriptedDinkerRallyVictoryRematchAndChooseOpponent() throws { try scriptedBossVictory("dinker") }
    @MainActor func testScriptedLobberRallyVictoryRematchAndChooseOpponent() throws { try scriptedBossVictory("lobber") }

    /// Normal menu navigation with a bounded, delayed public-input controller.
    /// Run under simctl recordVideo for real-time, clean ability comparisons;
    /// this is scripted input, never a claim of human play or difficulty.
    @MainActor
    func testRealtimeFiveBossAbilityRecording() throws {
        let app = launchHome(arguments: ["--validation-policy=neutral", "--validation-realtime",
                                        "--validation-manual-start", "--validation-seed=2958360576"])
        for id in ["wall", "banger", "poacher", "dinker", "lobber"] {
            app.buttons["home.bossRally"].tap()
            let choice = app.buttons["boss.select.\(id)"]
            reveal(choice, in: app); choice.tap()
            let court = element("game.court", in: app)
            XCTAssertTrue(court.waitForExistence(timeout: 5))
            XCTAssertTrue((court.value as? String ?? "").lowercased().contains(id))
            capture("realtime-\(id)-start", app: app)
            let deadline = Date().addingTimeInterval(42)
            while Date() < deadline && !element("results", in: app).exists {
                Thread.sleep(forTimeInterval: 1)
            }
            capture("realtime-\(id)-end", app: app)
            if element("results", in: app).exists {
                let home = app.buttons["results.home"]
                reveal(home, in: app); home.tap()
            } else {
                app.buttons["game.pause"].tap()
                let home = app.buttons["pause.home"]
                reveal(home, in: app); home.tap()
            }
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testLobRiseApexDescentPauseResumeAndHome() throws {
        for phase in ["rise", "apex", "descent"] {
            let app = XCUIApplication()
            app.launchArguments = ["--validation-boss=lobber", "--validation-policy=neutral",
                                   "--validation-realtime", "--validation-seed=2958360576",
                                   "--validation-pause-lob=\(phase)"]
            app.launchEnvironment = [:]
            app.launch()
            let resume = app.buttons["pause.resume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 40), "No real lob reached \(phase)")
            capture("lob-paused-\(phase)", app: app)
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(resume.exists)
            resume.tap()
            let court = element("game.court", in: app)
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let status = court.value as? String ?? ""
                return court.exists && !status.contains("Paused") && !status.contains("Resume countdown")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            capture("lob-resumed-\(phase)", app: app)
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testPowerPreparationPauseResumeAndHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--validation-boss=banger", "--validation-policy=powerResponder",
                               "--validation-seed=2958360576", "--validation-pause-special"]
        app.launchEnvironment = [:]
        app.launch()
        // The real core reaches its first power reservation; a DEBUG-only
        // trigger calls the ordinary pause method at that event, without
        // injecting a ball, points, opponent or special state.
        let resume = app.buttons["pause.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30))
        capture("interrupted-power-preparation", app: app)
        resume.tap()
        let court = element("game.court", in: app)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let status = court.value as? String ?? ""
            return court.exists && !status.contains("Paused") && !status.contains("Resume countdown")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
        capture("resumed-power-preparation", app: app)
        app.buttons["game.pause"].tap()
        let home = app.buttons["pause.home"]
        reveal(home, in: app); home.tap()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRepeatedModeHomeTransitionsRemainResponsive() throws {
        let app = launchHome()
        capture("stress-home-initial", app: app)
        for cycle in 0..<12 {
            let mode = ["arcade", "wall", "banger", "poacher", "dinker", "lobber"][cycle % 6]
            if mode == "arcade" {
                _ = startRun(app)
            } else {
                app.buttons["home.bossRally"].tap()
                let choice = app.buttons["boss.select.\(mode)"]
                reveal(choice, in: app); choice.tap()
                XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 5))
            }
            XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
            capture("stress-play-\(cycle)-\(mode)", app: app)
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["home.bossRally"].isHittable)
            capture("stress-home-\(cycle)-\(mode)", app: app)
        }
    }

    @MainActor
    func testModeHomeLifetimesWithoutRepeatedScreenshots() throws {
        let app = launchHome(arguments: ["--validation-lifetimes"])
        for cycle in 0..<24 {
            let mode = ["arcade", "wall", "banger", "poacher", "dinker", "lobber"][cycle % 6]
            if mode == "arcade" { _ = startRun(app) }
            else {
                app.buttons["home.bossRally"].tap()
                let choice = app.buttons["boss.select.\(mode)"]
                reveal(choice, in: app); choice.tap()
                XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 5))
            }
            app.buttons["game.pause"].tap()
            let home = app.buttons["pause.home"]
            reveal(home, in: app); home.tap()
            XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
            print("NATIVE_STRESS settled-home-\(cycle)-\(mode)")
            // The separate app process keeps running while its scene teardown
            // settles; the root samples host RSS without taking a screenshot.
            Thread.sleep(forTimeInterval: 1.2)
        }
        capture("lifetime-probe-final-home", app: app)
    }

    @MainActor
    private func scriptedBossVictory(_ id: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--validation-autoplay", "--validation-boss=\(id)"]
        app.launchEnvironment = [:]
        app.launch()
        let results = element("results", in: app)
        XCTAssertTrue(results.waitForExistence(timeout: 90))
        let visible = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").uppercased()
        XCTAssertTrue(visible.contains(id.uppercased()), visible)
        XCTAssertFalse(app.staticTexts["GAME OVER"].exists)
        XCTAssertEqual(element("results.matchScore", in: app).label, "YOU 3 · BOSS 0")
        if id == "lobber" {
            XCTAssertFalse(app.buttons["results.playNext"].exists)
            XCTAssertEqual(element("results.sequenceComplete", in: app).label, "Final opponent defeated")
        } else {
            XCTAssertTrue(app.buttons["results.playNext"].exists)
            XCTAssertFalse(element("results.sequenceComplete", in: app).exists)
        }
        let score = element("results.score", in: app).label
        XCTAssertEqual(try XCTUnwrap(Int(score.filter(\.isNumber))), 2_500)
        capture("scripted-\(id)-victory", app: app)
        let rematch = app.buttons["results.replay"]
        reveal(rematch, in: app)
        XCTAssertEqual(rematch.label, "Rematch")
        rematch.tap()
        let court = element("game.court", in: app)
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        assertFreshBossMatch(id, court: court)
        capture("scripted-\(id)-rematch", app: app)
        XCTAssertTrue(results.waitForExistence(timeout: 90))
        let choose = app.buttons["results.chooseOpponent"]
        reveal(choose, in: app); choose.tap()
        XCTAssertTrue(element("boss.selection", in: app).waitForExistence(timeout: 5))
        capture("scripted-\(id)-choose-opponent", app: app)
        let back = app.buttons["boss.select.back"]
        reveal(back, in: app); back.tap()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertFreshBossMatch(_ id: String, court: XCUIElement,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let status = court.value as? String ?? ""
        XCTAssertTrue(status.hasPrefix("Boss Rally. THE \(id.uppercased())."), status, file: file, line: line)
        XCTAssertTrue(status.contains("You 0. Boss 0. 0 saves."), status, file: file, line: line)
        XCTAssertTrue(status.contains("Score 0."), status, file: file, line: line)
        XCTAssertFalse(status.contains("Paused"), status, file: file, line: line)
    }

    @MainActor
    private func launchControls() -> XCUIApplication {
        let app = XCUIApplication()
        // Freeze only the DEBUG validation simulation. Real SwiftUI Crown/touch
        // controls still act on authoritative state; synthetic Crown calls take
        // several seconds in this runtime, longer than a normal incoming rally.
        app.launchArguments = ["--validation-controls"]
        app.launch()
        XCTAssertTrue(element("game.court", in: app).waitForExistence(timeout: 10))
        if app.buttons["pause.resume"].exists { app.buttons["pause.resume"].tap() }
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func launchHome(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.buttons["home.play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.play"].isHittable)
        XCTAssertTrue(app.buttons["home.bossRally"].isHittable,
                      "Both game modes must be available on Home without scrolling")
        return app
    }

    @MainActor
    private func startRun(_ app: XCUIApplication) -> XCUIElement {
        let play = app.buttons["home.play"]
        reveal(play, in: app)
        play.tap()
        let court = element("game.court", in: app)
        XCTAssertTrue(court.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 5))
        return court
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settings = element("home.settings", in: app)
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(element("settings.haptics", in: app).waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    @discardableResult
    private func reveal(_ target: XCUIElement, in app: XCUIApplication,
                        failIfHidden: Bool = true) -> Bool {
        // Older XCTest can report clipped chooser/result buttons as hittable
        // even when their centers are below the display. Scroll them fully in.
        let needsFullGeometry = target.identifier.hasPrefix("boss.select.") ||
            ["home.settings", "settings.haptics", "settings.sensitivity",
             "pause.restart", "results.playNext", "results.home", "results.replay"].contains(target.identifier)
        // Five opponent cards need more short drags on the 40 mm display.
        for _ in 0..<16 {
            if target.exists {
                if !needsFullGeometry && target.isHittable { return true }
                if target.frame.height > 0 && target.frame.maxY <= app.frame.maxY - 4 && target.frame.minY >= 52 { return true }
            }
            // Watch's default full-screen swipe can skip an entire card in
            // the longer chooser and oscillate around it. Use a short drag
            // wholly inside the display, then inspect fresh element geometry.
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            if target.exists && target.frame.minY < 52 {
                upper.press(forDuration: 0.05, thenDragTo: lower,
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            } else {
                lower.press(forDuration: 0.05, thenDragTo: upper,
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            }
        }
        let visible = target.exists && (needsFullGeometry
            ? target.frame.height > 0 && target.frame.maxY <= app.frame.maxY - 4 && target.frame.minY >= 52
            : target.isHittable)
        if failIfHidden {
            XCTAssertTrue(visible, "Expected a visible \(target.identifier), frame \(target.frame), app frame \(app.frame)")
        }
        return visible
    }

    @MainActor
    private func dragAcross(_ court: XCUIElement, from start: CGFloat, to end: CGFloat) {
        // Stay below the HUD and above the pause control on both Watch sizes.
        let origin = court.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.55))
        let destination = court.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.55))
        origin.press(forDuration: 0.05, thenDragTo: destination)
    }

    @MainActor
    private func playerX(_ court: XCUIElement) throws -> Double {
        let accessibilityValue = try value(court)
        let prefix = "Player x="
        guard let range = accessibilityValue.range(of: prefix) else {
            XCTFail("Court must expose its authoritative player position: \(accessibilityValue)")
            throw UIContractError.missingPlayerPosition
        }
        let token = accessibilityValue[range.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "-" }
        // The accessibility sentence has a period immediately after the number.
        guard let result = Double(token.hasSuffix(".") ? token.dropLast() : token[...]) else {
            XCTFail("Unparseable authoritative player position: \(accessibilityValue)")
            throw UIContractError.missingPlayerPosition
        }
        return result
    }

    @MainActor
    private func waitForPlayer(_ court: XCUIElement, description: String,
                               condition: @escaping (Double) -> Bool) {
        let predicate = NSPredicate { _, _ in
            guard let position = try? self.playerX(court) else { return false }
            return condition(position)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, description)
    }

    @MainActor
    private func value(_ element: XCUIElement) throws -> String {
        guard let raw = element.value else {
            XCTFail("Missing accessibility value for \(element.identifier)")
            throw UIContractError.missingValue
        }
        return String(describing: raw)
    }

    private func sensitivityPercentage(_ value: String) throws -> Int {
        guard let result = Int(value.prefix { $0.isNumber }) else {
            XCTFail("Unparseable sensitivity percentage: \(value)")
            throw UIContractError.missingValue
        }
        return result
    }

    @MainActor
    private func waitForValueChange(_ element: XCUIElement, from original: String) {
        let predicate = NSPredicate { _, _ in
            guard let actual = try? self.value(element) else { return false }
            return actual != original
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func valueBecomes(_ element: XCUIElement, equalTo expected: String) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard let actual = element.value else { return false }
            return String(describing: actual) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    @MainActor
    private func restoreSensitivity(_ slider: XCUIElement, in app: XCUIApplication,
                                    percentage: Int, expected: String) -> Bool {
        // The displayed baseline percentage rounds half-values. Recover the
        // nearest of the existing seven slider detents, not a new Crown gain.
        let position = CGFloat((Double(percentage - 15) * 6 / 45).rounded() / 6)
        for attempt in 1...3 {
            let visible = reveal(slider, in: app, failIfHidden: false)
            let actual = slider.value.map { String(describing: $0) } ?? "<missing>"
            print("SETTINGS_RESTORE attempt=\(attempt) expected=\(expected) actual=\(actual) normalized=\(position) visible=\(visible) frame=\(slider.frame) appFrame=\(app.frame)")
            guard visible else { continue }
            if actual == expected { return true }
            slider.adjust(toNormalizedSliderPosition: position)
            if valueBecomes(slider, equalTo: expected) { return true }
        }
        return false
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum UIContractError: Error {
        case missingPlayerPosition
        case missingValue
    }
}
