# Physical Watch verification

Follow [local signing instructions](../RUN_ON_MY_WATCH.md). Preserve the bundle identifier and installed data; updates do not require uninstalling or resetting pairing. Enter credentials and respond to trust prompts only in Xcode/on the device.

Privately record source commit, configuration, version/build, executable hash and profile validity. Confirm installation with an installed-app query, launch with a process query, and independently terminate/relaunch. A signed build alone proves neither installation nor launch. UI automation preparation timeouts are not gameplay results.

Check on the Watch:

- Ordinary app-icon launch; Boss Rally first on Home and Arcade below it. Confirm five individual opponent choices and Back navigation.
- Arcade returns, movement at both edges and dense waves.
- Existing Crown sensitivity, drag parity and immediate boundary reversal.
- Touch Pause in Arcade and every individual boss, including after Play Next. Resume freezes/rebases, Home exits, Restart resets the selected match.
- Readable contacts and opponent movement; saves award no point; matches end at three. Play Next appears only after wins, advances Wall → Banger → Poacher → Dinker → Lobber and resets score/saves. Lobber ends the list without a loop.
- Repeat Rematch/Retry, Choose Opponent, Back, Home and Pause/Resume after several matches; check records update once per completed match.
- Dinker rhythm without long waits; Lobber rise/descent and contact timing; Banger drive contrast; Poacher side intent. Play with haptics off as well.
- HUD/system-indicator clearance, animations, target clearances and contact alignment.
- Interruption/wrist-down pause, settings/records after relaunch and repeated replay/Home cycles.
- Sustained play for haptic comfort, warmth and battery. Simulator metrics cannot substitute.

Separate human playtesting from install, process launch, simulator tests and scripted scenarios. Public images must omit notifications, account screens and device identifiers. Record which checks were actually performed, the build version and any failures.
