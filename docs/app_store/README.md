> Current local build: 1.0 (10), physically accepted. Source/docs publication is authorized; enrollment/payment and App Store submission remain on hold. Store drafts are not published metadata.

# Preparing the App Store submission

These instructions are for the owner and authorized developers. Reviewed October 1, 2026. This folder contains local drafts, not an App Store Connect submission. Developer enrollment/payment and account setup remain on hold; the owner handles them separately. Build 6 polish and its physical acceptance are still in progress. No Apple account setting, app record, upload, TestFlight invitation, review submission, or release is performed by these files.

GitHub hosts PickleBlast's source, support issues, and public website. Apple does not clone this repository for ordinary review. Xcode compiles a chosen source revision into an archive containing the executable, approved artwork, privacy text, and other required resources. The distribution build is uploaded through Apple's tools. Uploading the repository or pushing a Git commit does not upload the app.

## Materials and destinations

| Material | Location and use |
| --- | --- |
| English listing draft | [metadata_en_US.json](metadata_en_US.json); enter reviewed values in App Store Connect |
| Reviewer instructions | [review_notes.txt](review_notes.txt); paste into Notes after final testing |
| Screenshot provenance | [screenshot_manifest.json](screenshot_manifest.json); historical build 4 captures pending replacement for the accepted candidate |
| Owner checklist | [App Store readiness](../APP_STORE_READINESS.md); review every unresolved item |
| Marketing URL | [PickleBlast](https://fcw1987.github.io/PickleBlast/) |
| Privacy Policy URL | [Privacy](https://fcw1987.github.io/PickleBlast/privacy/) |
| Support URL | [Support](https://fcw1987.github.io/PickleBlast/support/) |
| Archives, app bundles, symbols, signing and diagnostic files | Local ignored build output only; never GitHub or Pages |
| Account details and App Review contact name, email and phone | Owner enters privately in Apple's interfaces; never public drafts or screenshots |

## 1. Confirm the candidate and account prerequisites

Use the accepted preparation revision and run [build and test](../BUILD_AND_TEST.md). Preserve `com.pickleblast.watchapp`, version `1.0`, and the existing signing setup. The local polish candidate uses build `6`; this is not a claim that 6 is an unused upload number. Check previous uploads in App Store Connect before choosing the next unique number. If a change is required, update the project generator, regenerate the project, and rebuild/test the exact candidate.

The inspected toolchain is Xcode 27.0 (27A266a), with watchOS 27.0 SDK; deployment remains watchOS 10.0. Apple's effective April 28, 2026 upload minimum is Xcode 26 and watchOS 26 SDK. A newer build SDK does not require raising the deployment target. Recheck [current requirements](https://developer.apple.com/news/upcoming-requirements/) before upload.

The owner must confirm Developer Program membership, app registration, role, seller identity, applicable agreements, and distribution signing. Do not substitute a personal development signature for distribution validation. Keep signing material out of the repository and CI.

## 2. Create or identify the Watch app record, only when authorized

In App Store Connect, Apps > + > New App, Apple's current Watch procedure uses **iOS** as the record platform, including watch-only apps. Use the preserved registered bundle identifier and the approved name and primary language. The owner supplies the internal SKU and account-specific information privately. The record's iOS grouping does not require an iPhone companion. In Previews and Screenshots, use the **Apple Watch** tab; iPhone screenshots are not required for a watch-only app. [Apple's Watch record instructions](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information/)

No record was created during preparation. Do not create a second record if the correct one already exists.

## 3. Build a local Release archive

Open `PickleBlast.xcodeproj` in Xcode. Select the shared **PickleBlast** scheme and a generic **Any watchOS Device** destination, not a simulator. Product > Archive uses the scheme's Release configuration. The [archive command](../BUILD_AND_TEST.md#archive-preparation) can also produce unsigned local packaging evidence without account access. Keep the archive and symbols locally.

An unsigned archive cannot establish distribution eligibility. An archive carrying a development signature is also not yet an App Store distribution build. Inspect the archive's bundle identifier, version/build, icon, privacy manifest, bundled policy and runtime resources before proceeding. Preserve the working Watch installation and local records throughout validation.

## 4. Validate and upload only after owner authorization

In Xcode's Organizer > Archives, select the exact Watch archive. Use its distribution workflow for **App Store Connect**. Inspect the available validation/signing options and resolve genuine account or distribution prerequisites in Xcode. For the subsequent authorized upload, select the App Store Connect upload route and review the final summary before confirming. The precise controls can vary with the selected archive and account; an unavailable option is a blocker, not permission to change packaging or credentials.

The installed version is Xcode 27.0. Preparation does not assert that its signed distribution wizard or upload completed. Apple's [upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) links to the current Xcode distribution instructions; Xcode Help also provides them. Local Xcode upload requires no Xcode Cloud or source-linking service.

Wait for Apple's processing, then inspect the processed build and warnings in App Store Connect. Upload and processing do not publish the app.

## 5. Enter reviewed listing and release settings

Enter the English draft and approved actual screenshots, then verify every field in the interface. Field limits checked on October 1, 2026: name and subtitle 30 characters each; description 4,000 characters, plain text; promotional text 170 characters; keywords 100 UTF-8 bytes; review Notes 4,000 bytes. The first version has no What's New field. The existing `2026 fcw1987` copyright is a draft using the repository's rights holder; the owner confirms its suitability for the listing. [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) · [Version fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

Select normal public App Store distribution. In Pricing and Availability, set the price to **Free**. For App Availability, choose **Specific Countries or Regions**, select **United States only**, and leave future-country automatic inclusion unchecked. Do not select pre-order. Choose **Manually release this version** for owner-controlled release after review. Confirm the final availability list before saving. These are owner decisions, not changes made by this preparation. No runtime location check is needed; the public website remains worldwide. [Availability controls](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/)

Use Apple's standard EULA unless the owner separately chooses a custom agreement. Do not upload the restrictive repository source or asset license as the customer EULA. Complete app privacy, age-rating, content-rights, export-compliance and any account-wide compliance questions using the evidence and open decisions in the readiness checklist. Do not enroll in the Kids Category or declare accessibility features without the required testing. [Standard EULA](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)

Apple's private App Review contact fields are separate from the public Support URL. Enter real required contact information only in App Store Connect. Public support remains GitHub Issues; its review-acceptance uncertainty is explicitly recorded in the checklist.

## 6. TestFlight, review, and release are separate steps

After an authorized upload processes, an optional internal TestFlight check can verify installation, offline play, settings, offline policy/help and visible website addresses, haptics and records on a physical Watch. Use only already-authorized internal testers; external testing may require beta review. No testers are invited in this run. [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

Select that exact tested build for the App Store version. Complete all required fields, attach the screenshots, review the submission, and submit only with separate owner authorization. Approval with manual release leaves the app pending the owner's release action. [Submit for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)

The current work is local engineering and physical acceptance. Developer enrollment/payment and account setup remain on hold; no upload or submission is authorized by this polish pass. After the app is actually released, update the homepage's preparation notice with the real App Store URL and an authorized Apple badge if desired. Keep the Privacy and Support routes stable.
