# ZetaMax Support

ZetaMax V01 is being prepared for release. This page covers source builds and, once published, the Mac App Store edition.

## Start here

- Review the setup and usage sections in the [README](README.md).
- Check [open issues](https://github.com/Ayush-Singh-31/ZetaMax/issues) for a matching report.
- Read the [privacy policy](docs/PRIVACY.md) for data-handling questions.
- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability.

## Report a bug

Use the [bug report form](https://github.com/Ayush-Singh-31/ZetaMax/issues/new?template=bug_report.yml) and include:

- ZetaMax version and build;
- macOS version and Mac model or processor;
- whether the app came from Xcode or the Mac App Store;
- the smallest reliable set of reproduction steps;
- expected and actual behavior;
- screenshots or a short recording when the issue is visual;
- relevant crash text with personal paths or practice data removed.

Never post private answer history or exported practice data unless you have reviewed and intentionally redacted it.

## Request a feature

Use the [feature request form](https://github.com/Ayush-Singh-31/ZetaMax/issues/new?template=feature_request.yml). Describe the practice problem first, then the proposed behavior. This makes it easier to consider simpler alternatives and protect the app’s focused scope.

## Frequently asked questions

### Where is my practice data stored?

ZetaMax stores sessions in its sandboxed local SwiftData container. The exact system-managed path can vary. The app does not upload that store to a ZetaMax server.

### Can I back up my data?

Yes. Open **Settings → Data and privacy** and export CSV or JSON. History also supports exporting all sessions or an individual session.

### How do I delete everything?

Open **Settings → Data and privacy → Delete all practice data** and confirm. This removes sessions, question attempts, submissions, and derived skill estimates from the app’s store.

### Why is a session marked interrupted?

A session is interrupted when you end it early, the Mac sleeps, or ZetaMax recovers an unfinished session on its next launch. It remains in History, but it is excluded from comparable analytics.

### Why is a projection or recommendation missing?

ZetaMax avoids presenting estimates from insufficient evidence. Recommendations require enough samples in a question category. Benchmark projections require multiple comparable sessions and completed attempts near the selected duration.

### Does ZetaMax need the internet?

No. V01 practice, persistence, analytics, recommendations, history, and export run locally without an application account or backend.

### Which macOS versions are supported?

The current deployment target is macOS 14 Sonoma.

## Source-build troubleshooting

### Signing prevents the app from running

In Xcode, select the ZetaMax target, open **Signing & Capabilities**, enable automatic signing, and select your own development team.

### UI tests cannot control the app

Keep the desktop session unlocked and grant Accessibility permission to Xcode when macOS asks. UI tests interact with a real macOS window rather than a simulator.

### Analytics are empty

Complete at least one session and open Analytics again. Some views intentionally need more history before they can calculate a meaningful comparison or projection.

## Response expectations

ZetaMax is independently maintained. Reports are reviewed on a best-effort basis; complete, reproducible issues receive the quickest attention.
