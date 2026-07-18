# V01 Mac App Store Release Dossier

This is the working release record for ZetaMax’s first public Mac App Store submission. It separates facts already present in the repository from decisions and assets that still require release-owner action.

## Release identity

| Field | Current value |
| --- | --- |
| Product name | ZetaMax |
| Release label | V01 |
| Xcode marketing version | `1.0` |
| Xcode build number | `1` |
| Bundle identifier | `com.ayush.ZetaMax` |
| Platform | macOS |
| Minimum system | macOS 14.0 |
| Primary category | Education |
| Distribution | Mac App Store |
| Price | Release-owner decision |
| Copyright | © 2026 Ayush Singh |

Keep the V01 label for project communication and use the App Store version/build values in App Store Connect. Increment the build number for every subsequent uploaded archive associated with version 1.0.

## Submission blockers found in the repository audit

These items should be resolved before the first review submission:

- [ ] **Complete the app icon catalog.** The current catalog supplies only two 512×512 files, leaves multiple macOS slots unassigned, and has no 1024×1024 source for the 512 pt @2x slot.
- [ ] **Expose the privacy policy inside the app.** Settings explains local storage but does not currently provide an easily accessible policy link. Apple’s review guidelines require a privacy-policy link in App Store Connect and within the app.
- [ ] **Select the distribution team and confirm signing.** Automatic signing is enabled, but no development team is committed to the project.
- [ ] **Publish stable support and privacy URLs.** These repository documents can be used after the repository is public and their GitHub URLs are verified.
- [ ] **Remove generated build output from version control.** `.build/` is now ignored, but files already tracked there should be removed from the Git index in a dedicated repository-cleanup change.

## Product-page copy

Treat this as editorial source, then check the current App Store Connect fields and limits before pasting.

### Name

**ZetaMax**

### Subtitle

**Adaptive mental math practice**

### Promotional text

Train faster mental arithmetic with adaptive drills, focused targets, clear benchmarks, and private on-device analytics—built natively for Mac.

### Description

Make every minute of mental arithmetic practice count.

ZetaMax is a private, native Mac training app for building speed, consistency, and confidence with numbers. Choose a familiar mixed drill, focus on a specific skill, let adaptive practice revisit slower categories, or take a locked benchmark you can compare over time.

PRACTICE YOUR WAY

• Classic sessions with configurable operations, ranges, and duration<br>
• Adaptive sessions guided by your on-device timing history<br>
• Focused targets for multiplication, exact division, negative subtraction, powers, percentages, decimals, and quant interview preparation<br>
• Versioned benchmarks from 30 seconds to 10 minutes

UNDERSTAND YOUR PACE

• Track questions per minute, median response time, P90, and consistency<br>
• Explore progress by operation, question category, and operand<br>
• See response-time distributions and pace through each session<br>
• Review benchmark projections, results, and personal bests<br>
• Turn recommendations into focused 45-second sessions

PRIVATE BY DESIGN

No account. No advertising. No tracking. No ZetaMax backend.

Your practice history stays in the app’s local data store. Export CSV or JSON when you choose, and delete your history at any time.

ZetaMax is designed for keyboard-first focus, responsive Mac windows, and light or dark appearance.

### Keywords

`mental math,arithmetic,practice,quant,benchmark,addition,multiplication,division,percentages`

### What’s new for version 1.0

Welcome to ZetaMax V01.

• Four deliberate practice modes<br>
• On-device recommendations and performance analytics<br>
• Versioned benchmarks and personal bests<br>
• Searchable history with CSV and JSON export<br>
• Native light and dark Mac experience<br>
• No account, ads, or tracking

## Product claims checklist

Every public claim should remain true in the submitted binary:

- [x] No account required.
- [x] No application backend or network client.
- [x] No ads, tracking, telemetry, or third-party SDK.
- [x] Practice, analytics, and recommendations work offline.
- [x] Practice data is stored locally with SwiftData.
- [x] CSV and JSON export are user initiated.
- [x] All practice data can be deleted in Settings.
- [x] Benchmark profiles are locked and versioned.
- [x] Interrupted sessions are excluded from comparable metrics.
- [ ] Privacy policy is reachable inside the submitted app.

Re-audit this list whenever dependencies, networking, logging, accounts, or data handling change.

## App privacy answers

Based on the V01 source audit, the app itself does not “collect” data as Apple defines collection: no practice data is transmitted off device for developer or third-party access.

Proposed App Store Connect answer:

- **Data collection:** Data Not Collected.
- **Tracking:** No.

The release owner remains responsible for verifying the final archived binary, every included SDK, and the then-current App Store privacy questionnaire. Apple’s own App Store processing is separate from data collected by the application.

Reference: [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/).

## App Review notes

Suggested review note:

> ZetaMax is an offline mental arithmetic practice app. It has no login, purchases, advertising, or application backend. All session and analytics data is stored locally.
>
> To exercise the primary flow: open Practice, choose a 30-second Classic or Benchmark session, select Start session, and answer the displayed arithmetic questions. Correct answers advance automatically; Return records a non-empty incorrect submission. After the timer ends, the result appears in History and Analytics.
>
> Analytics intentionally reveal more detail as local completed history grows. CSV and JSON exports are available in Settings and History through the standard macOS file exporter.

Add reviewer contact information in App Store Connect. If the submitted build differs from these instructions, update the note.

## Screenshot plan

Use real production UI with representative, non-personal fixture data. Keep typography legible at product-page size and present a coherent story:

1. **Practice with intent** — show the four modes and clear configuration.
2. **See the whole picture** — Analytics Overview with headline metrics and trend.
3. **Find the bottleneck** — Skills with operation/category detail and operand explorer.
4. **Understand your pace** — Distribution with histogram and session pace.
5. **Benchmark honestly** — projections, results, and personal bests.
6. **Keep your history yours** — searchable History and local export.

The three verified captures retained under `Artifacts/FinalTestScreenshots` are useful references. Local QA runs may contain additional ignored captures. Re-capture the final signed build after all V01 UI changes and export only sizes accepted by the current macOS media manager.

Reference: [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots).

## Preflight checklist

### Product

- [ ] Complete a fresh-install walkthrough.
- [ ] Complete Classic, Adaptive, Targeted, and every Benchmark duration.
- [ ] Verify negative and decimal input with the current locale.
- [ ] Verify sleep interruption and recovery after forced termination.
- [ ] Verify empty, sparse, and mature analytics states.
- [ ] Export all history and one session as both CSV and JSON.
- [ ] Delete one session, then delete all data.
- [ ] Check light, dark, and system appearances.
- [ ] Check compact 860×620, default 1,100×760, and wide layouts.
- [ ] Check Reduce Motion and Reduce Transparency.
- [ ] Complete a keyboard-only pass and a VoiceOver smoke test.

### Identity and policy

- [ ] Confirm product name, bundle ID, category, version, and build.
- [ ] Confirm final price, territories, age rating, and availability.
- [ ] Confirm support URL and privacy-policy URL resolve without authentication.
- [ ] Add the privacy-policy link inside Settings or About.
- [ ] Confirm copyright and seller identity.
- [ ] Complete App Privacy answers against the final archive.
- [ ] Complete encryption/export-compliance questions.
- [ ] Review the current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### Build and signing

- [ ] Fill every required macOS icon slot with production artwork.
- [ ] Select the App Store distribution team.
- [x] App Sandbox is enabled.
- [x] Hardened runtime is enabled.
- [x] User-selected file read/write is enabled for export.
- [ ] Review the final archive’s entitlements and embedded frameworks.
- [ ] Confirm Release optimization and no debug-only test seeding.
- [ ] Run unit and UI tests from the release commit.
- [ ] Archive with the final version/build and validate in Organizer.
- [ ] Upload the archive and wait for processing to complete.

Apple requires App Sandbox for Mac App Store distribution. The target already enables it; verify the archive rather than relying only on project text. Reference: [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

### App Store Connect

- [ ] Accept current agreements and create the macOS app record.
- [ ] Confirm the record uses `com.ayush.ZetaMax`.
- [ ] Add description, subtitle, keywords, category, and release notes.
- [ ] Upload final screenshots.
- [ ] Add support and privacy URLs.
- [ ] Select the processed build.
- [ ] Supply App Review contact and notes.
- [ ] Resolve every validation warning or document why it is safe.
- [ ] Submit for review using the intended release option.

References:

- [Create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/)

## Release procedure

1. Freeze V01 scope and update `CHANGELOG.md`.
2. Resolve every blocker in this dossier.
3. Run the full automated suite and manual preflight.
4. Set version/build values and create the release commit.
5. Archive, validate, and upload from Xcode Organizer.
6. Verify the processed build’s metadata, entitlements, privacy answers, and screenshots.
7. Submit to App Review.
8. After approval, publish according to the chosen release mode.
9. Tag the exact commit as `v1.0.0`.
10. Create GitHub release notes from the changelog and replace the README availability text with the live App Store link.

## Rollback and post-release

The Mac App Store does not make a source-control rollback equivalent to recalling an installed build. For a serious issue:

1. remove the version from sale if impact warrants it;
2. publish a concise support notice;
3. fix from the release tag;
4. increment the build and patch version as appropriate;
5. repeat the full privacy, test, archive, and review flow.

After launch, monitor crash reports, App Store reviews, and support issues without adding hidden telemetry. Update support documentation when a recurring question appears.

## Release sign-off

| Area | Owner | Status |
| --- | --- | --- |
| Product behavior | Release owner | Pending |
| Automated tests | Release owner | Pending |
| Accessibility | Release owner | Pending |
| Privacy and policy | Release owner | Pending |
| Icon and screenshots | Release owner | Pending |
| Signing and archive | Release owner | Pending |
| App Store metadata | Release owner | Pending |

Record final sign-off in the release pull request so the submitted archive can be traced to an exact commit.
