# Security Policy

ZetaMax is an offline-first macOS application. Security work focuses on protecting local practice history, preserving sandbox boundaries, producing safe exports, and preventing untrusted input from affecting app integrity.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` / V01 development | Yes |
| Older snapshots or unofficial builds | No guaranteed support |

Security fixes are made against the current codebase until a stable release branch exists.

## Report a vulnerability

Please do **not** open a public issue for a suspected vulnerability.

Use GitHub’s private vulnerability reporting flow:

[Report a vulnerability privately](https://github.com/Ayush-Singh-31/ZetaMax/security/advisories/new)

Include:

- a clear description and potential impact;
- affected commit, version, or build;
- reproducible steps or a proof of concept;
- relevant macOS and hardware details;
- any suggested mitigation;
- whether the issue is already public.

Do not include real user practice data, credentials, or unrelated personal information.

## What to expect

The maintainer will make a best effort to:

1. acknowledge a complete report;
2. reproduce and assess severity;
3. coordinate a fix and disclosure plan;
4. credit the reporter if requested and appropriate.

Response time is not guaranteed for this independently maintained project. Please allow a reasonable remediation window before public disclosure.

## In scope

Examples include:

- unintended access to or disclosure of the local SwiftData store;
- sandbox or file-access boundary bypasses;
- malicious CSV or JSON export behavior;
- crashes, corruption, or code execution caused by crafted persistent data;
- privacy claims contradicted by executable behavior;
- unsafe handling of submitted answer text or file destinations;
- vulnerabilities introduced by build or distribution configuration.

## Usually out of scope

- issues that require physical access to an already unlocked Mac and provide no additional privilege or data access;
- denial of service through extremely large, manually generated local datasets without a security boundary impact;
- social engineering, phishing, or attacks against GitHub accounts;
- unsupported macOS versions or modified unofficial builds;
- general bugs, feature requests, or theoretical concerns without a plausible security impact.

When uncertain, report privately and explain the potential boundary you believe is affected.

## Current security posture

The V01 target enables:

- App Sandbox;
- hardened runtime;
- user-selected read/write file access for explicit exports;
- automatic code signing configuration;
- no network client, account system, embedded web content, or third-party runtime dependencies.

These properties reduce the attack surface but do not replace review, testing, signing, or responsible disclosure.
