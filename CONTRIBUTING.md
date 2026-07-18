# Contributing to ZetaMax

Thank you for helping make deliberate mental arithmetic practice better on the Mac.

ZetaMax values focused changes, measurable behavior, native platform conventions, and honest analytics. This guide describes the path from an idea to a reviewable pull request.

## Before you begin

Please:

- read the [Code of Conduct](CODE_OF_CONDUCT.md);
- search existing [issues](https://github.com/Ayush-Singh-31/ZetaMax/issues) before opening a new one;
- use a feature request for user-facing or architectural proposals;
- use the private process in [SECURITY.md](SECURITY.md) for vulnerabilities.

Small fixes can go directly to a pull request. For a broad change—especially one affecting the data model, analytics definitions, adaptive behavior, export schema, or release scope—open an issue first so its behavior can be agreed before implementation.

## Development setup

You need:

- macOS 14 Sonoma or later;
- Xcode 15 or later;
- Git.

Clone and open the project:

```bash
git clone https://github.com/Ayush-Singh-31/ZetaMax.git
cd ZetaMax
open ZetaMax.xcodeproj
```

Select the **ZetaMax** scheme and **My Mac**. If signing prevents a local run, choose your development team under the app target’s **Signing & Capabilities** settings.

There are no external package dependencies.

## Build and test

Build from Terminal:

```bash
xcodebuild build \
  -project ZetaMax.xcodeproj \
  -scheme ZetaMax \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

Run the unit suite:

```bash
xcodebuild test \
  -project ZetaMax.xcodeproj \
  -scheme ZetaMax \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:ZetaMaxTests
```

Run all unit and UI tests by removing `-only-testing:ZetaMaxTests`. UI tests require an unlocked desktop session and may prompt for Accessibility permission.

## Repository map

| Path | Responsibility |
| --- | --- |
| `ZetaMax/App` | Application composition, commands, and scene setup |
| `ZetaMax/Domain` | Practice configuration, operations, presets, benchmarks, and shared value types |
| `ZetaMax/Engine` | Question generation, adaptive weighting, and live session orchestration |
| `ZetaMax/Models` | SwiftData entities and relationships |
| `ZetaMax/Persistence` | Repository operations, recovery, deletion, and exports |
| `ZetaMax/Analytics` | Immutable analytics inputs, calculations, caching, and UI-facing state |
| `ZetaMax/Views` | SwiftUI screens, components, responsive behavior, and visual theme |
| `ZetaMaxTests` | Unit and integration tests |
| `ZetaMaxUITests` | End-to-end, responsive-layout, appearance, and visual-state tests |

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing a boundary between these areas.

## Design principles

### Keep results honest

- Interrupted sessions can appear in history but must not silently enter comparable metrics.
- A metric label must describe the filtered value actually being shown.
- Sparse data should produce an explicit empty or unavailable state, not an implied result.
- Benchmark profiles and export schemas are versioned contracts.
- Changes to statistical behavior need tests that exercise empty, sparse, normal, and filtered datasets.

### Keep practice responsive

- The answer field must remain focused and keyboard friendly.
- Correct-answer auto-advance must happen exactly once.
- Timing uses a monotonic clock; do not derive response duration from wall-clock time.
- Heavy analytics work belongs off the main actor.
- Cancellation and revision invalidation are part of analytics correctness, not optional optimization.

### Preserve privacy by design

- New data remains local unless a proposal explicitly changes the product’s privacy model.
- Do not add telemetry, tracking, advertising, accounts, network services, or third-party SDKs without prior discussion.
- Exports must remain explicit user actions through a system file picker.
- Avoid logging submitted answers or other user-generated practice data.

### Feel at home on macOS

- Prefer SwiftUI and system controls.
- Verify compact, medium, and wide window sizes.
- Verify light, dark, Reduce Motion, and Reduce Transparency behavior where relevant.
- Add meaningful accessibility labels or identifiers to custom interactive and chart content.
- Reuse `ZetaTheme` primitives rather than creating isolated visual styles.

## Making a change

1. Create a focused branch from `main`.
2. Add or update tests before relying on manual verification.
3. Keep generated files, build products, credentials, and local Xcode state out of the commit.
4. Update documentation when behavior, data, build instructions, privacy, or release status changes.
5. Add a concise entry under `V01` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
6. Run the relevant suite and inspect `git diff` before opening a pull request.

## Test expectations

| Change | Minimum verification |
| --- | --- |
| Question generation | Deterministic unit tests with a fixed seed and operation-specific invariants |
| Session behavior | `SessionEngineTests`, including deadline and duplicate-submission cases |
| Persistence | In-memory tests; use an on-disk temporary store for relationship or migration behavior |
| Analytics | Empty, sparse, filtered, prior-period, and representative fixtures as applicable |
| Analytics service | Cache, cancellation, revision, and concurrency behavior |
| UI or theme | Relevant UI tests at compact and regular sizes in both appearances |
| Export schema | CSV quoting/order and JSON encode/decode assertions |

Screenshot artifacts are useful for review, but assertions should carry the behavior wherever practical.

## Commit and pull-request style

Use short, imperative commit subjects. Conventional prefixes such as `feat:`, `fix:`, `docs:`, `test:`, and `refactor:` are welcome but not required.

A pull request should explain:

- the user or engineering problem;
- the chosen behavior and any trade-offs;
- the tests run;
- screenshots or a recording for visible changes;
- data, privacy, accessibility, migration, or App Store implications.

Keep unrelated cleanup out of the same pull request. Review is faster when one change tells one clear story.

## Data model and export compatibility

SwiftData model changes can affect existing on-device history. Before changing a stored property or relationship:

- state the migration impact;
- verify launch with an existing store when possible;
- preserve cascade and inverse relationship behavior;
- update recovery, deletion, and estimate rebuilding if necessary.

The export envelope and CSV rows carry their own schema versions. Additive fields are preferred. A breaking semantic change requires a schema version increment and documentation.

## Documentation style

- Use plain, direct language.
- Describe current behavior rather than aspirations.
- Keep headings scannable and examples executable.
- Use sentence case.
- Avoid unsupported performance or privacy claims.
- Link to source-of-truth files instead of duplicating volatile detail.

## License

By contributing, you agree that your contribution will be licensed under the repository’s [MIT License](LICENSE).
