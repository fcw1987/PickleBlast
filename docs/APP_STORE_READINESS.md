# App Store readiness

Reviewed against Apple's current requirements on October 1, 2026. **Not ready for submission.** No App Store Connect record, upload, TestFlight release or distribution validation has been performed. Recheck the linked requirements before submission.

## Ready in the source

- Standalone watch-only application; `WKApplication` and `WKWatchOnly` are enabled, with no iPhone companion. Existing identity `com.pickleblast.watchapp`, marketing version 1.0 and development build 4 are preserved.
- Portable native project, shared Release archive scheme and account-free simulator configuration. Local development signing is separate and ignored.
- Complete runtime resources and app icon catalog. The opaque 1024 × 1024 icon and its variants compile; distribution processing and final crop review remain required.
- Offline application with local settings/records, no accounts, advertising, analytics, tracking, networking or third-party runtime SDKs.
- Privacy manifest declares app-owned UserDefaults use (`CA92.1`), no tracking and no collected data. Verify the exact distribution archive's privacy report before upload. [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## Technically prepared; owner action required

Current upload requirements call for Xcode 26 or later with the watchOS 26 SDK or later, effective April 28, 2026. The local Xcode 27/watchOS 27 toolchain exceeds that minimum; the deployment target remains watchOS 10. A successful unsigned build or archive is packaging evidence, not distribution approval. [Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/)

Select a unique submission build number, confirm bundle registration and prepare the exact distribution archive. Review the all-rights-reserved source and asset notices alongside the underlying content rights before distribution. The repository terms do not replace the App Store's end-user terms. Preserve all applicable third-party rights.

`ITSAppUsesNonExemptEncryption=false` is currently set; no app networking or cryptographic feature was identified. The owner must confirm the final export-compliance answers and territories. [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

## Requires Developer Program and App Store Connect access

Confirm paid membership, seller identity, roles, agreements, distribution signing and registered app identity. Create the app record only when authorized. Then validate the distribution archive, upload, inspect processing, and complete review. No credentials or signing secrets belong in this repository or hosted CI. [Developer Program](https://developer.apple.com/programs/) · [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## Requires real hosted URLs

Publish an approved privacy policy and support page using [PRIVACY.md](../PRIVACY.md) and [SUPPORT.md](../SUPPORT.md) as source material. Supply a reachable support contact and working URLs in App Store Connect. No placeholder endpoint is configured.

The app currently has no policy link in Settings. Guideline 5.1.1 requires an easily accessible in-app privacy policy link as well as the metadata URL. Add and test that small Settings entry once the actual policy endpoint is supplied; no gameplay change is needed. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Requires physical human validation

Complete [on-wrist regression](PHYSICAL_WATCH_TEST.md), including Crown/touch feel, all bosses, Arcade, pause/interruption recovery, records, haptics, readability, sustained sessions and relaunch. Check older supported hardware/OS versions. Menu labels and status descriptions alone do not establish real-time VoiceOver playability. Assess larger text, contrast, color cues, motion and haptics before making accessibility claims. No dedicated reduced-motion mode is implemented. [Accessibility declarations](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)

## Requires final listing decisions

Choose category, pricing, territories, age-rating questionnaire answers, copyright/seller identity, review contact and any applicable trader status. Games is the likely category for owner consideration; no classification or rating has been selected. [Age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/) · [Trader status](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)

Prepare localized screenshots of actual gameplay. Apple currently accepts Watch sizes 422 × 514, 410 × 502, 416 × 496, 396 × 484, 368 × 448 or 312 × 390; keep one size across localizations. The three README screenshots are actual 422 × 514 simulator captures, available as reference for final selection. They are not an approved listing. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

Suggested review notes: Standalone Apple Watch game. No sign-in, companion app, purchases or backend. Turn the Digital Crown or drag on the court to move; returns are automatic. Boss Rally has three opponents and All Three, first-to-three matches, and two saves per match. Pause offers Resume, Home and Restart. Settings and records stay local.
