# Implementation plan — recommendations 1, 3 and 5

## Authorized scope

Implement custody/audit correctness, shared gate direction rules, and truthful operational interfaces from the comprehensive product report. Preserve previous working-tree changes. Queue durability, payment concurrency, new VIP/hold policies and unrelated features remain outside this iteration.

Confirmed operating rule: normal mode uses Gate 1 for entry and Gate 2 for exit; administrator-authorized event mode allows entry and exit at both gates. Existing security holds remain enforced. This change does not invent a visitor emergency-release policy.

## 1. Custody, cases and visitor audit

- Preserve recorded physical presence when an incident or violation is created/resolved; calculate remaining holds independently.
- Return current standing and remaining registration/payment/expiry restrictions after case resolution. Use that result in staff and owner guidance.
- Route legacy online visitor checkout through the validated movement transaction, requiring prior entry, item confirmation and applicable hold/direction checks. Retrying a completed checkout must return its existing movement instead of creating another exit.
- Keep all movement writers consistent, including historical visitor checkout synchronization; historical events must retain actual event time and audit attribution.
- Add regression scenarios for mixed cases, no-entry checkout, held visitor checkout, item checks, repeat requests and presence preservation.

## 2. Shared gate operation

- Add a normal/event policy setting and administrator control with a required reason for mode changes.
- Resolve physical checkpoint from staff assignment, independently of username. Recognize existing Gate/Checkpoint 1 and 2 assignments; report unrecognized assignments explicitly.
- Enforce direction during verification and immediately before saving. A prepared confirmation cannot bypass a later mode/assignment change; a retry of an already committed movement returns that committed result.
- Display current mode/checkpoint/allowed directions in web and mobile. Remove fixed guard2 UI restrictions that prevent event operation.
- Preserve named guard, physical checkpoint and actual direction in audit records.
- Test both gates, both directions, normal/event transitions, stale confirmations and unauthorized setting changes.

## 3. Truthful interfaces

- Replace mobile activity-derived KPIs with server aggregates for current occupancy, today's approved entries and today's denied attempts; show unavailable/stale data honestly.
- Correct historical movement labels and clearance messages.
- Derive one-time release visibility from actual hold and physical presence; display configured/saved expiry instead of a fixed 30 minutes.
- Remove unsupported print/CCTV success claims.
- Preserve exact passwords in mobile authentication.
- Consolidate resolution guidance around Cases while retaining compatible underlying APIs.

## 4. Verification and delivery

1. Run targeted failing regressions, then verify fixes against isolated PHP/SQLite fixtures.
2. Run the full existing backend validation, Flutter analysis/tests and Android debug build; maintain the generated backend mirror.
3. Exercise real Chrome/PHP workflows and Dart/PHP integration, including visitor creation/movements and updates in an already-open web portal.
4. Run focused browser end-to-end checks for mode switching, normal/event gate behavior, cases/releases and corrected messages, checking browser errors.
5. Inspect available devices and database runtime. Execute native/device or MySQL checks where available; report unavailable coverage explicitly. Camera/OCR hardware cannot be certified by service/widget tests.
6. Publish a local implementation/verification report listing changed behavior, exact results and remaining limits. No deployment is included.

Acceptance requires preserved presence, accurate remaining restrictions, one audit per successful passage, consistent gate rules across platforms, truthful UI outcomes and passing applicable regressions. Testing cannot establish the absence of every possible runtime error.

## Completion record

Implementation steps 1–3 and all locally available verification were completed. The full API/Flutter suites, focused backend checks, real Chrome workflows, actual Dart/PHP integrations, analyzer and Android debug build passed. Native phone/camera and MySQL deployment acceptance remain unverified because those runtimes were unavailable. See `implementation-results-1-3-5-2026-10-11.md` for exact evidence and migration requirements.
