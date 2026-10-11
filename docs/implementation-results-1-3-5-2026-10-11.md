# Implementation and verification — recommendations 1, 3 and 5

Date: 11 October 2026. Scope follows the approved implementation plan in `implementation-plan-1-3-5-2026-10-11.md`. This report supplements the earlier analysis; its original findings describe the system before these repairs.

## Outcome

Implemented custody/audit repairs, shared normal/event gate permissions, and corrections to operational displays. Existing unrelated working-tree changes were preserved. The application was tested with isolated data, actual PHP requests, real Chrome sessions, the actual Dart transport, Flutter widgets and an Android build.

Passing tests support the specific workflows below. They do not establish that every possible runtime error has been eliminated. An installed-phone acceptance run and deployment-specific MySQL validation remain necessary.

## 1. Custody and audit correctness

### Case resolution and physical presence

Creating a security incident no longer replaces a registered vehicle's physical location with a hold label. Closing a violation no longer changes an inside vehicle to outside. Legacy `Blocked / Alert` records are restored from recorded movement evidence rather than given a fabricated exit.

Shared standing output reports physical presence, remaining held incidents/pending violations, applicable registration/payment/expiry restrictions, and eligibility for a one-time exit release. Case responses and owner guidance describe remaining restrictions instead of promising unrestricted entry and exit.

Regression evidence includes an inside vehicle with an independent security incident plus a violation: closing one preserves inside status and reports the other hold; closing the last restores ordinary exit eligibility without recording departure. A deliberately seeded legacy blocked status is also covered.

### Visitor checkout

The legacy online checkout endpoint now requires a signed-in staff account and uses the validated movement transaction. It checks the selected pass, matching plate, previous entry, active status, security restrictions, declared items and gate direction. Successful checkout saves the exit audit and pass change together. Retrying that checkout returns the existing result.

Direct gate-log writes also enforce visitor checks, preventing a caller from bypassing them through an older route. Scanner credentials alone cannot use the named-staff checkout endpoint.

Historical offline checkout synchronization now records an attributable exit audit and deduplicates an already recorded departure. Historical facts are treated differently from permission to perform a new online movement: an already-performed departure is retained, and missing item confirmation or a currently known hold produces review flags and an incident. This does not authorize a new offline operating policy.

## 3. Shared gate operation

| Mode | Gate 1 | Gate 2 |
|---|---|---|
| Normal, the default | Entry | Exit |
| Administrator-authorized event | Entry and exit | Entry and exit |

Administrators change **Admin Center → Settings → Gate operation**, supply a reason and save. Each mode change has an authorization audit record committed with the setting. Guards cannot change this setting.

The physical checkpoint comes from the authenticated staff assignment, accepting existing Gate/Checkpoint 1 and 2 labels. It does not come from the username. Unrecognized guard assignments receive an explicit assignment error. Administrators assigned across gates can select the physical checkpoint in the web monitor.

The server checks direction during verification and immediately before saving. A mode reversal invalidates an uncommitted scan that is no longer permitted. A retry of a movement already committed still recovers its original result. Gate logs retain actual checkpoint, direction and named operator.

Web direction controls and the mobile policy banner use the same server policy. The web's fixed guard2 restrictions were removed. The mobile scanner continues to propose direction from recorded presence; the server decides whether that direction is allowed at that checkpoint. Normal/event changes do not bypass pass, driver, item or security restrictions.

## 5. Truthful operational interfaces

- Mobile KPIs use server aggregates for current occupancy, today's approved entries and today's denied attempts, instead of deriving totals from the latest 100 activities. Unavailable values are not displayed as zero; retained values are labelled stale after refresh failure.
- The web dashboard also uses authoritative server totals. Daily aggregation uses the campus day and separates approved entries from denied attempts.
- Historical movement labels describe the state after that event. An old exit-denial log alone no longer creates a current-hold badge in the web fallback renderer.
- A completed visitor departure displays **Completed**, rather than cancellation merely because the single-use pass was revoked internally.
- Security-only holds on an inside vehicle expose the one-time release control. Its dialog reads the configured duration; Chrome verified a seven-minute setting.
- Mobile no longer reports that an unsupported print job was queued. Camera previews are labelled demonstrations and no longer claim that a recording was attached to a passage.
- Mobile preserves password whitespace in both sign-in and the temporary-password change handoff.
- Incident and violation resolution controls lead to the Cases workflow, with current remaining-restriction guidance.

## Verification evidence

Tests used temporary fixture copies and disposable SQLite databases. They did not target the working or hosted campus database.

| Check | Result / evidence |
|---|---|
| Broad real PHP API regressions | 678 assertions passed; `artifacts/baseline-backend-suite.log` |
| Movement integration | 85 checks passed; `artifacts/baseline-movement.log` |
| Added product integrity checks | 41 passed; `artifacts/product-integrity-results.json` |
| Flutter regression suite | 190 passed; two environment-dependent integration cases skipped here and executed separately below; `artifacts/product-flutter-suite.log` |
| Actual mobile dashboard widget | Server totals, mode refresh and labelled stale data passed; `artifacts/product-dashboard-widget.log` |
| Dart analyzer | No issues; `artifacts/product-flutter-analyze.log` |
| Android debug build | Passed; `artifacts/product-android-build.log` |
| Chrome web error/recovery E2E | 24 checks passed, including staff/owner flows; no uncaught browser exceptions; `artifacts/product-web-errors.log` |
| Actual Dart → PHP → open Chrome visitor workflow | 21 wrapper checks passed plus its Dart test: create guard, sign in, create visitor, validate items, enter, exit, observe live web audits/completed status, reject duplicate visitor creation; `artifacts/product-visitor-roundtrip.log` |
| Actual Dart synchronization worker → PHP | Remote vehicle change and session revocation passed; `artifacts/product-mobile-php.log` |
| Three-session Chrome gate/case workflow | 18 checks passed, including saving a release and closing its case without changing presence; no uncaught browser exceptions. See `artifacts/product-browser-results.txt` and `artifacts/product-browser-run.log` |
| Syntax and deployment mirror | PHP and JavaScript syntax, canonical API/lib/database mirror equality and source snapshot checks passed; `artifacts/baseline-results.json` |

Additional existing revision API, browser transport and legacy violation presentation tests passed in the validation runner. The expanded product checks cover both directions at each gate during an event, cross-gate journeys, unauthorized mode changes, stale confirmations, retry recovery, mixed holds, legacy status recovery, visitor refusals, named audits, historical checkout deduplication, and date-correct totals beyond the recent-log window.

The mobile suite also exercises scanner lifecycle/error handling, OCR parsing, visitor forms and responsive layouts. Those are automated software checks, not observations of a physical camera.

### Problems discovered during implementation

- The first broader run found a missing import in direct incident resolution; fixed, then verified by the complete API suite.
- Older tests expected unchecked scanner items and revoked-pass checkout to succeed; their assertions now verify refusal and unchanged presence. This is an intentional behavior correction.
- The small-screen mobile test still expected old KPI labels. Assertions were updated to the accurate daily labels; the layout and full suite pass.
- Browser testing required waiting for the relevant guard session to receive a policy update before starting its next scan. A pending result may correctly be invalidated when shared gate data changes; users must recheck it before approval.

## Rollout requirements and remaining limits

1. **Existing MySQL installations must apply `backend/database/migrations/012_gate_operation.sql` after their existing migrations.** It inserts the normal-mode default without overwriting a configured value. Deploy the mirrored backend and web assets together. SQLite fixtures initialize the setting automatically. The transactional MySQL gate-policy lock refuses operation if the required row is missing.
2. Confirm each guard has the intended Gate 1 or Gate 2 assignment. Demonstrate switching event mode on and off with an accountable reason. The mode is explicitly changed by an administrator; no undocumented schedule or automatic expiry was introduced.
3. No Android device/emulator or iOS device was available. Flutter listed Windows, Chrome and Edge only. Native camera permissions, actual OCR image quality, camera switching, background/resume, the installed splash transition and hardware printing have not been certified. The APK build is not a device test.
4. No running local MySQL/MariaDB process was found. SQL locking/concurrency behavior and migration execution were not tested on the production database engine. SQLite results must not be presented as MySQL acceptance evidence.
5. No deployment or external mail/payment provider acceptance was performed. Queue durability/server isolation and payment concurrency recommendations remain outside this approved implementation batch. Revoked-visitor emergency/escort authority and outage admission procedures still need campus decisions; no new release policy was invented.

The remaining native acceptance exercise is concrete: install the APK on a supported phone, use isolated staff/visitor identities, scan real QR codes and representative plates/IDs under varied lighting, confirm driver/items, record entry/exit at both gates in normal/event modes, and observe the open web audit. Repeat camera denial/recovery and background/resume. Run the concurrency/migration checks against a disposable MySQL instance before deployment.

## Deliverables

- Plan: `docs/implementation-plan-1-3-5-2026-10-11.md`.
- This implementation and verification report.
- New targeted backend/browser/mobile tests and their artifacts.
- Android debug APK: `mobile-app/build/app/outputs/flutter-apk/app-debug.apk`.

These changes improve the integrity and consistency of the approved workflows. Deployment readiness remains conditional on the explicitly unverified native and production-engine checks above.
