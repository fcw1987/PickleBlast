# App Store readiness

Reviewed October 1, 2026 against the official sources linked below. **Preparation is not submission approval.** Developer enrollment/payment and account setup remain on hold. Build 10 is physically accepted and authorized for the source/docs merge; distribution and account setup remain on hold. No App Store Connect record, metadata entry, binary upload, TestFlight invitation, compliance declaration, review submission, or release has been performed in this preparation run. See the [owner upload guide](app_store/README.md) and [English metadata draft](app_store/metadata_en_US.json).

## Candidate and engineering evidence

The five-boss feature baseline is `b470aae62a2755e063752bc2ff8598845ba879b3`, version 1.0 (5). The accepted version 1.0 (10) build places Boss Rally first, offers Wall → Banger → Poacher → Dinker → Lobber as individual matches with post-win Play Next, and preserves Arcade. The Lobber ends the displayed list without looping. The legacy three-match sequence has no public menu entry. Build 10 source is 36ee3e28d5e116787c57c842d766eb6fad06d540; physical acceptance is recorded, while frame timing, RAM, GPU, heat and battery remain unmeasured. Historical preparation evidence below remains historical.

| Item | Verified configuration or required evidence |
| --- | --- |
| Product | Standalone watch-only app; `WKApplication` and `WKWatchOnly`, no iPhone companion |
| Identity | `com.pickleblast.watchapp`; version 1.0, accepted local build 10; not submitted |
| Build number | Owner must check prior uploads before selecting a unique submission number; local preparation does not establish the last uploaded number |
| Native project | Shared PickleBlast scheme, Release archive action, reproducible project generation; personal signing remains ignored and separate |
| Toolchain | Xcode 27.0 (27A266a), watchOS 27.0 SDK; deployment target remains watchOS 10.0 |
| Required SDK | Xcode 26 or later with watchOS 26 SDK or later, effective April 28, 2026; recheck before upload ([Apple requirements](https://developer.apple.com/news/upcoming-requirements/)) |
| Gameplay data | App-owned UserDefaults stores sensitivity, haptics, Arcade best and boss records; in-progress run is memory-only |
| Dependencies | Apple frameworks and local Swift modules only; no analytics, ads, accounts, gameplay backend or third-party runtime SDK |
| Icons/resources | Existing opaque 1024 × 1024 icon and derived catalog; approved runtime art retained; policy resource must match canonical source |
| Native policy/help | Settings exposes offline Privacy and Support plus version/build and readable website addresses; prior large/small watchOS 27 checks are historical and must be repeated for the accepted candidate |
| Archive | Prior unsigned/development archive audits are historical. Inspect the exact accepted candidate; distribution signing/validation remains outstanding |
| Known compiler diagnostic | Existing deprecated public `WKInterfaceSKScene` initializer warning; retained explicit teardown is documented in [Architecture](ARCHITECTURE.md) |

Use [build and test](BUILD_AND_TEST.md) for clean Debug/Release builds, `scripts/validate.sh`, native tests, and archive commands. Do not infer a current pass from this checklist. [Screenshot provenance](app_store/screenshot_manifest.json) identifies the capture build and exact source, while local result bundles and archive evidence remain outside Git. A passing simulator suite does not establish physical Crown feel, haptics, battery use, or full accessibility.

## Historical build 4 validation recorded October 1, 2026

The native app source and capture revision is `42bdfd137927220730ccfdd0a7aed6bd796e8f8f`. That preparation changed public materials and test tooling. Its gameplay core, rendering, tuning, session/save behavior, approved art, bundle identity and privacy manifest matched the then-accepted baseline. These statements describe build 4 only.

- `scripts/validate.sh` passed: 222 Swift tests, 50 artwork/import regressions, seven public-tree guard tests, 15 website regressions, five policy regressions, project/resource checks, public-file scanning, documentation links, metadata limits, policy consistency and an unsigned generic watchOS Release build.
- Clean checkout: unsigned generic watchOS Debug and Release builds passed with Xcode 27.0. A local Release archive passed inspection of identity, minimum OS, bundled privacy/policy and ten runtime atlases. Source files, website images and diagnostic controls are absent from the Release product.
- Apple Watch Ultra 4 (49mm), watchOS 27 simulator: both native Privacy/Support tests passed, including full reading, navigation and settings preservation. The ordinary Release all-opponent/pause/resume/Home/Arcade test passed and supplied the three curated screenshots.
- Apple Watch SE 3 (40mm), watchOS 27 simulator: Release readable-address and settings-persistence tests passed; the full-policy scrolling/preservation test passed after extending its short-drag allowance, with the complete end-of-content assertion retained.
- An additional watchOS 10 Series 9 (45mm) simulator attempt exposed a test tap on a partly visible Settings row. The helper now requires the full row; the follow-up stalled loading simulator accessibility and was stopped. Older-OS information-screen acceptance remains unverified, separate from the passing watchOS 27 checks.
- Separate development-signed Release: signature, entitlement, profile-validity, resources and absence of diagnostic controls passed local audit. An in-place physical Watch installation attempt was blocked by the device connection service (CoreDevice error 4016). No uninstall, reset or record erasure was performed. This is not physical play acceptance or distribution-signing evidence.
- The three store originals are real 422 × 514 opaque RGB PNGs from ordinary Release runs. Their [manifest](app_store/screenshot_manifest.json) records source, build, simulator, timestamps and hashes. Website copies are losslessly recompressed with unchanged image data. Independent review verified captures and provenance.

Local result bundles, signing evidence and the unsigned archive remain private. The owner must still review the archive's distribution privacy report, complete distribution-specific physical checks and validate the eventual distribution-signed candidate. The existing SpriteKit deprecation and the toolchain's skipped App Intents extraction diagnostic do not prevent these local builds.

## Public URLs, support, and privacy

The permanent routes are [Marketing](https://fcw1987.github.io/PickleBlast/), [Privacy](https://fcw1987.github.io/PickleBlast/privacy/), and [Support](https://fcw1987.github.io/PickleBlast/support/), hosted from this repository's `main` branch `/docs` Pages source. Before submission, open all three without GitHub authentication, verify nested routes/assets over HTTPS, and confirm the deployed content matches the candidate. A Pages build passing alone is not sufficient.

Ordinary public contact is **GitHub Issues only**, for bugs, feature requests, and support questions. The information pages can be read without an account; posting requires a GitHub account and is public. Private vulnerability reporting is a separate security route, not general support. No public email, phone number or postal contact is provided.

**Unresolved App Review acceptance risk:** Apple's [Support URL field documentation](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) asks for actual contact information, and [Guideline 1.5](https://developer.apple.com/app-store/review/guidelines/#safety) requires an accessible developer contact route. Neither explicitly guarantees acceptance of GitHub Issues alone. The owner has chosen that route; US-only availability does not remove the general requirement. This is a review interpretation risk, not an engineering failure or a reason to invent contact information. If Apple requests a different public route, the owner decides separately.

[PRIVACY.md](../PRIVACY.md) is the single maintained policy source. Generated website policy content and bundled native text must stay synchronized through the policy check. For a policy change, edit only `PRIVACY.md`, run `python3 scripts/sync_privacy.py`, review both generated outputs, then run `python3 scripts/sync_privacy.py --check`. The outputs are `WatchApp/Policy/Privacy.txt` and the marked region in `docs/privacy/index.html`. Native reading is offline. The watchOS 27 simulator returned a system failure directing the user to an iPhone when opening both the policy URL and a known-live HTTPS repository URL. The app therefore provides readable website addresses and native policy/help, without a dead web-launch button. This is evidence for the tested environment, not a claim about every watchOS version. Gameplay and native help do not require another device; the public addresses can be entered in a browser elsewhere. The generic [Apple OpenURLAction documentation](https://developer.apple.com/documentation/swiftui/openurlaction) does not by itself establish Watch browser behavior; the completion-handler overload is unavailable on watchOS in the inspected SDK.

## Proposed declarations and unresolved owner decisions

| Area | Source evidence | Submission action |
| --- | --- | --- |
| App privacy | No app telemetry, accounts, advertising or runtime third-party data SDKs. Settings and records stay in local UserDefaults. Website addresses are displayed as text; separately visiting GitHub pages/support has disclosed processing. | Proposed app answer is no data collected from the app, subject to owner review of Apple's definitions, the exact archive, and the voluntary support flow; do not infer it merely from the manifest. |
| Website/support privacy | GitHub Pages may log IP addresses for security; public issue usernames/text/attachments are visible; private security reports use GitHub's feature. No project site analytics are added. | Preserve the policy's distinction between app, host and support. Do not claim nobody collects data anywhere. |
| Required-reason APIs | PrivacyInfo.xcprivacy declares UserDefaults category with `CA92.1`, no tracking, no collected data types. LocalStore uses the app's own defaults. | Review the exact archive's privacy report and bundled manifest before upload. |
| Export compliance | `ITSAppUsesNonExemptEncryption=false`; no custom cryptography or app networking implementation identified. The app displays HTTPS website addresses without loading them. | Owner answers the current encryption questionnaire. Neither offline gameplay nor HTTPS alone establishes a legal exemption; preserve the value only if the final determination supports it. |
| Age rating | Pickleball sports action, cartoon opponents and effects; no chat, user-generated content inside gameplay, gambling, purchases, ads, health advice or location. External support is optional. | Complete Apple's current questionnaire, inspecting all art and external-link questions; do not invent a rating or select Kids Category. |
| Categories | Sports-themed paddle game with a separate Arcade mode. | Proposed primary Games; Sports and Arcade game subcategories. Owner confirms available choices. |
| Rights/EULA | Source available/all rights reserved; approved art and branding remain protected. Authorized distributed copies have separate end-user terms. | Owner confirms content ownership/permissions and listing copyright. Use Apple's standard EULA unless separately choosing a custom one. Never upload the source license as the customer EULA. |
| Accessibility | Native labels, scrolling text and touch/Crown alternatives exist. Gameplay is real time; the system Reduce Motion preference suppresses decorative motion while preserving flight information. | Declare only features tested against Apple's criteria. Labels alone do not establish VoiceOver gameplay support. Physical human testing remains required. |
| Account/compliance | Membership, roles, agreements, seller identity and distribution credentials are account-specific. | Owner confirms privately. If Apple presents account-wide trader/compliance questions, answer truthfully; US-only distribution does not answer them automatically. |
| App Review contact | No private contact values are committed. | Owner enters real required name/email/phone in App Store Connect's private review fields. These do not change the public Issues-only decision. |

Sources checked October 1, 2026: [App privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [privacy definitions and optional disclosure](https://developer.apple.com/app-store/app-privacy-details/), [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [export overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/), [encryption declarations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations), [age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/), [accessibility declarations](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels), [standard EULA](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/), [trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements).

## Fixed release plan

These are owner preferences to enter later, not completed App Store settings:

- Normal public App Store distribution, **Free**, English initial listing.
- **United States only** in Specific Countries or Regions; automatic availability in new territories unchecked.
- No pre-orders, subscriptions, purchases, advertising, or other monetization.
- Manual release after review approval; no automatic release date.
- No runtime region detection or geofencing; the website remains publicly accessible worldwide.

[Apple availability controls](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/) describe the specific-country and future-country settings. Availability does not replace membership, agreements or required declarations.

## Screenshot and final acceptance checklist

Use actual Watch app captures from the chosen build. Apple accepts Watch dimensions 422 × 514, 410 × 502, 416 × 496, 396 × 484, 368 × 448, or 312 × 390, and requires consistent Watch screenshot dimensions across localizations. Upload one to ten PNG/JPEG screenshots. Keep lossless originals separate from optimized website images; never distort captures. Use only the accepted candidate’s actual five-boss and Arcade interfaces. Current local screenshot drafts show actual accepted build 10 navigation/gameplay; recheck final distribution build and localization before submission. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) · [Upload formats/count](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)

- [ ] Confirm clean Debug/Release builds, required validation and large/small UI results for the exact accepted build 10 revision, including offline policy/help and readable addresses. Historical build 4/5 results do not satisfy this item; older-OS acceptance remains open.
- [ ] Inspect the accepted candidate’s local archive and distinguish unsigned packaging from development and distribution signatures.
- [ ] Review the distribution privacy report and perform distribution validation with the owner's eligible account.
- [ ] Complete [physical Watch acceptance](PHYSICAL_WATCH_TEST.md): controls, all bosses, Arcade, pause/interruption, persistence, haptics, readability and sustained play. Include older supported hardware/OS when available.
- [ ] Replace historical screenshots with actual accepted-candidate captures, inspect the icon crop, and verify provenance and metadata limits. Owner approves the final listing selection before upload.
- [ ] Owner rechecks the stable HTTPS routes and issue/security actions immediately before Apple submission; do not submit test reports. Current deployment results are reported separately from the local build evidence.
- [ ] Resolve account, final privacy/age/rights/export/accessibility answers and private App Review contact details.
- [ ] Confirm the selected upload build number and, after separate authorization, upload/process it; optionally test that exact build in TestFlight.
- [ ] Submit only after owner authorization, then release manually only after approval and the owner's release decision.

Apple's [Watch record procedure](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information/) uses an iOS record and Apple Watch screenshots for a watch-only app; no fake companion is needed. Follow the [upload guide](app_store/README.md) for the separate archive, upload, processing, testing, review and release steps. App Review acceptance is never guaranteed by engineering checks.
