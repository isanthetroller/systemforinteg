# Web and mobile integration — October 9, 2026

## A. Git integration

- Original branch: `feature/web-ui-redesign-and-table-actions-v2`, HEAD `1498f03c8fc2221de5d839137e85416938504c18`.
- Fetched GitHub `origin/main`: `0908333` (immediate owner passage emails).
- Common ancestor: `1498f03`. The committed web redesign is already in the GitHub history.
- Recovery branch: `backup/local-flexible-qr-20261009`, local snapshot commit `74fa117`.
- Integration branch: `integration/web-mobile-20261009`.
- Strategy: preserve the uncommitted QR work in a local commit, then merge fetched main with both parents retained.
- Conflicts: canonical `logs.php`, `verify.php`, guard shell, and the two PHP deployment mirrors. Both intended behaviors were combined.
- File backup: `../integration-backups/20261009-135748/project-recovery.zip`; includes local config and data, plus separate consistent SQLite backups. Keep this private because it includes secrets.
- No push, remote deployment, database reset or history rewrite was performed. Original feature branch is retained.

## Feature comparison and decisions

| Component | Local work | Incoming GitHub work | Integrated behavior |
|---|---|---|---|
| QR scanner | Automatic suggested IN/OUT, explicit confirmation, signed snapshot and idempotent retry | Capacity/case notices, release warning, OCR/evidence and larger photos | One active scanner route for both guards, with upstream features on the confirmation screen |
| Guard identity/navigation | Both checkpoints process entry and exit; removed unauthenticated local role switch | Duty shifts and handover notes | Keep authenticated checkpoint and IN/OUT navigation; preserve shifts and handover |
| Mobile API service | New staff-only movement endpoint; no offline queue for uncertain confirmations | Updated host, evidence, notices, release/case support | Preserve new host and all existing service methods; flush notices and attach evidence after acknowledged save |
| Web portals | Existing committed UI redesign | Unified cases, Admin Center, cashier/renewals, owner portal and record photos | Keep incoming HTML, CSS and JS; use their existing history/campus/owner APIs for mobile movements |
| Gate backend | Signed preview ticket, row locking, revision checks and unique client reference | Paid registrations, retired vehicles, exit releases, owner notices | Revalidate under lock, consume releases and queue notices atomically; preserve authorization and driver/item checks |
| Database | Uses existing migration 006 client reference | Migrations 007–011: payments/notices/operations/cases/visitor photo | Preserve migrations and data; no second movement table or mobile database |
| Existing offline events | Lock vehicle when replaying historical events | Updated historical flag/case behavior and lookup method | Keep historical sync separate from new online confirmations, preserving both behaviors |

## B. Mobile application

### Preserved local work

Both Guard 1 and Guard 2 can process either movement at their own authenticated checkpoint. Scan preparation does not save a movement. Confirmation checks shared state again. Repeated tickets return the original result; competing snapshots get a stale rejection. Uncertain confirmations retain the same payload and lock navigation until retry resolves the outcome. Standard passes require an authorized driver; VIP exemptions and visitor item checks remain.

### Incoming features retained

Cloud host/presets, real visitor QR display and vehicle photo, compressed photos, vehicle/driver photo panels, plate OCR and evidence, violations-only workflow, capacity and case information, single-use exit releases, guard duty and shift handover, lookup method and owner notice delivery.

### Integration files

- `mobile-app/lib/features/guard/screens/guard_shell_screen.dart`
- `mobile-app/lib/features/scanner/screens/qr_scanner_screen.dart`
- `mobile-app/lib/features/scanner/widgets/movement_confirmation_card.dart`
- `mobile-app/lib/features/scanner/widgets/scan_rejection_view.dart`
- `mobile-app/lib/features/scanner/widgets/scanned_person_card.dart`
- `mobile-app/lib/models/user_model.dart`
- `mobile-app/lib/services/api_service.dart`
- Tests: `movement_workflow_test.dart`, `qr_scan_state_validation_test.dart`, `widget_test.dart`.

The confirmation card now shows upstream notices, photos and selected driver details, supports evidence and inspection/incident reporting, and locks related actions during uncertain saves. Obsolete three-strike wording was removed.

## C. Web application

All incoming admin and owner portal frontend files are retained. Cases, Admin Center, payments/renewals, approvals, operations, enhanced record details and owner activity remain available. The admin portal uses `./api`, and the local owner portal uses `../web-app-admin/api`. The mobile app must point to that same server.

Only backend deployment mirror integration was needed under `web-app-admin/{api,lib}`. Mobile transactions appear through the existing web history, on-campus and student vehicle/activity endpoints. No independent database was introduced.

## D. Backend and database

Canonical integration files: `api/movements.php`, `api/logs.php`, `api/sync.php`, `api/verify.php`, `api/oncampus.php`, `api/releases.php`, `lib/movements.php`, `lib/campus.php`, `lib/capacity.php`; each is mirrored under the admin deployment.

- Staff-only prepare/confirm endpoint uses signed, five-minute tickets bound to guard, pass, checkpoint, shared status and movement revision.
- Current hold/release, suspension, payment, retirement, expiry, driver and visitor-item eligibility is checked again at confirmation.
- Release consumption, passage record, state update and owner notice are transactional. Duplicate retries do not repeat notices or movement.
- Legacy web/phone gate writes retain the upstream features and check fresh state/revision under lock; visitor writes also check their snapshot.
- Same-second entry/exit records are ordered by ID as well as time, preventing earlier exits from hiding a later entry on the campus list.
- Physical custody is preserved when standing becomes `Blocked / Alert`; an administrator can release an exit for a held vehicle actually inside.
- Existing secrets were compared with recovery copies and are unchanged. Tests only use disposable data.

Keep existing production config. Apply only missing MySQL migrations 001–011 in order, using migration files rather than the destructive fresh-install schema. SQLite adds missing tables/columns on connection. No production migrations were run by this task.

## E. Tests executed

| Check | Actual result |
|---|---|
| Real PHP/SQLite movement and web/owner round trips | 85 checks passed, two separate PHP workers sharing a disposable database |
| Backend regression suite | 678 passed, 0 failed |
| Flutter full test suite | 162 tests passed |
| Flutter analyzer | No issues found |
| Android debug APK | Built successfully; latest build defaults to emulator API on port 8001 |
| PHP syntax | 110 files checked, 0 failures |
| JavaScript syntax | 32 files checked, 0 failures |
| Table presentation logic | Passed pagination, filtering, search, refresh, background sync, empty/loading states |
| Canonical backend/deployment mirror | Up to date |
| Git diff whitespace/conflict review | No whitespace errors or unresolved merge entries |

Initial upstream baseline had 666 passing assertions and 12 failing assertions. Independent tests had inherited security holds from earlier forged/revoked-pass tests, and some expected retired policy behavior (unrestricted suspended exits and one vehicle total per owner). Regression fixtures now clear their test incidents explicitly and assert the current hold/class rules. Current checks pass without relaxing production policies.

Test logs are in ignored `artifacts/`: `integration-backend-tests.txt`, `movement-regression-smoke.txt`, `movement-baseline-smoke.txt`, `integration-flutter-tests.txt`, `integration-flutter-analysis.txt`, `integration-apk-build.txt`, `integration-php-lint.txt`, and `integration-javascript-check.txt`.

### Limits and manual checks

- Browser security policy declined access to the isolated preview. No visual browser walkthrough was completed and no workaround was attempted.
- Physical Android camera/OCR, an actual app launch on a device, production MySQL concurrency and live hosting integration were not tested. SQLite concurrency and mocked mobile widgets/API flows were tested.
- The debug APK is `mobile-app/build/app/outputs/flutter-apk/app-debug.apk`. Its initial endpoint is `http://10.0.2.2:8001/web-app-admin/api` for an Android emulator. For a phone, select the computer's reachable LAN URL in the login screen. A saved previous server selection may override the build default.
- Nothing was deployed to the cloud. The cloud default remains in source; its server needs the integrated PHP and missing migrations before using the new movement workflow there.
- Owner mail logic was exercised by the regression suite with its local fake SMTP sink; no real recipient mail was sent.
