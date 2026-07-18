# ZetaMax Privacy Policy

**Effective date:** July 18, 2026<br>
**Applies to:** ZetaMax V01 for macOS

ZetaMax is designed to provide private, on-device mental arithmetic practice. It does not require an account and does not operate an application backend.

## At a glance

- Your practice history stays on your Mac.
- ZetaMax does not send practice data to the developer.
- ZetaMax does not include advertising, tracking, telemetry, or third-party analytics SDKs.
- You decide when and where to export data.
- You can delete all practice data from inside the app.

## Data stored by the app

To provide practice history, adaptive sessions, recommendations, and analytics, ZetaMax stores the following information locally:

- practice configuration, mode, duration, and random seed;
- session start and end times, status, and end reason;
- generated questions and their arithmetic categories;
- answers you submit and whether each submission was correct;
- response times and question positions;
- benchmark identifiers and versions when applicable;
- derived skill estimates such as category timing, uncertainty, and recent slowdown;
- your selected appearance and most recent practice configuration.

ZetaMax does not ask for your name, email address, phone number, location, contacts, payment details, or account credentials.

## How data is used

Local data is used only to:

- run and recover practice sessions;
- show session history;
- calculate on-device analytics and benchmark projections;
- identify practice categories that may benefit from more attention;
- prepare adaptive and recommended sessions;
- create an export when you request one;
- remember local appearance and practice settings.

## Data collection and transmission

ZetaMax V01 does not transmit practice or personal data off the device. The app contains no ZetaMax network service, account system, advertising network, tracking technology, or third-party analytics SDK.

Apple may independently process information related to downloading, purchasing, updating, diagnostics, or use of the Mac App Store under Apple’s own terms and privacy policy. That processing is controlled by Apple and is not received through a ZetaMax backend.

## Storage and retention

Session data is kept in the app’s sandboxed SwiftData container until you delete it or remove the app and its associated container through macOS.

Appearance and recent configuration preferences are stored locally using system preferences.

Derived skill estimates are rebuildable from retained completed sessions. When a session is deleted, ZetaMax recalculates those estimates from the remaining history.

## Exporting data

You can export all practice history or an individual session as CSV or JSON. Export happens only after you choose the action and a destination through the macOS file picker.

After export, the copy is outside ZetaMax’s managed data store. You are responsible for its storage, sharing, and deletion. Exported files may contain question and answer history, timestamps, response times, and session identifiers.

## Deleting data

Open **Settings → Data and privacy → Delete all practice data** to remove all stored sessions, question attempts, answer submissions, and skill estimates.

Individual sessions can be deleted from History. Deleting a session also removes its attempts and submissions and rebuilds estimates from the remaining data.

Export first if you want to keep a copy.

## Security

The Mac App Store target uses App Sandbox and the hardened runtime. File access for export is limited to destinations you select through macOS.

No software can guarantee absolute security. Please report suspected vulnerabilities through the private process in [SECURITY.md](../SECURITY.md).

## Children’s privacy

ZetaMax does not knowingly collect or transmit personal information from children or adults. The app’s arithmetic practice may be used without creating an account or providing identity information.

## International use

Because V01 stores practice data locally and does not transmit it to the developer, ZetaMax does not operate a server-side practice-data transfer. Laws and platform services applicable to your device or App Store account may still vary by location.

## Changes to this policy

This policy will be updated before a release changes how data is stored, used, collected, transmitted, or shared. Material changes will be reflected in this document’s effective date and in the project changelog.

## Contact

For privacy questions, open a support request through the project’s [support page](../SUPPORT.md). Do not attach an unredacted ZetaMax export to a public issue.

For security vulnerabilities, use [private vulnerability reporting](https://github.com/Ayush-Singh-31/ZetaMax/security/advisories/new).

## Open-source verification

The behavior described here can be inspected in:

- `ZetaMax/Persistence/DataStore.swift` for local storage and deletion;
- `ZetaMax/Persistence/ExportService.swift` for user-requested exports;
- `ZetaMax/Analytics` for on-device derived calculations;
- `ZetaMax.xcodeproj/project.pbxproj` for sandbox and file-access build settings.

This policy describes the official, unmodified ZetaMax V01 build. Forks and unofficial builds may behave differently.
