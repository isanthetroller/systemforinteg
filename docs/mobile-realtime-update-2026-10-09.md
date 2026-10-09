# Mobile synchronization update — October 9, 2026

Branch: `feature/realtime-sync-mobile-20261009`.
Base: local integration commit `075e8f3`, which includes the earlier flexible QR workflow and the merged web/mobile changes. This branch contains the mobile update and the backend/web counterparts required to share updates. Publishing the branch does not deploy the server or update an installed phone app.

## What changed in the mobile app

### Shared data updates

- A signed-in foreground app checks authenticated `GET /api/updates.php` approximately every five seconds. Domain fingerprints identify changed vehicles, movements, cases, visitors, settings, shifts and the current account.
- Changed snapshots trigger live vehicle/log reads and relevant visitor/settings refreshes. Unchanged fingerprints avoid another full data fetch. A minute clock fingerprint causes time-dependent screens to reevaluate.
- A successful empty log response clears old records. Failed vehicle, log or required settings reads do not acknowledge the changed revision or advance the successful-sync time; the worker retries the snapshot.
- VisitorRepository replaces remote records with server data and notifies open lists. Local unsent visitor records are retained separately until accepted.

This uses polling, not an always-connected push service. Five seconds is a target interval, not a guaranteed delivery deadline; slow reads, scheduling and connectivity can delay reconciliation. Full-table fingerprinting and broad cache reloads need later scale optimization.

### Current account and security

- A 401 ends the API session and notifies the guard shell to return to sign-in. The app does not retry the request anonymously or treat an authorization refusal as a network failure to queue.
- The shell applies current account/profile/checkpoint information supplied by the feed. Server permission checks remain authoritative for every action.
- The backend rejects an invalid bearer before considering a scanner device key. Disabling a guard restricts further server requests immediately, independently of the next client poll. Reactivation requires a new session; revoked tokens do not revive.
- The anti-bot challenge solver no longer prints its solved cookie value.

### Scans and open visitor passes

- Open movement previews listen for updates and use side-effect-free preparation to compare current data. A changed vehicle/pass/current movement disables the old preview and asks for another scan. Unrelated unchanged data does not invalidate the mobile preview.
- The existing signed prepare/confirm workflow remains explicit and idempotent. Both guards can process IN and OUT at their authenticated checkpoint. An uncertain result retains its original ticket and client reference for retry; it does not queue a fresh direction toggle.
- Visitor confirmation screens now follow their pass by server ID/pass code instead of retaining the initial object. An already-open enlarged QR also updates.
- Blocked, expired, used and removed server passes show an explanation and no QR. Listeners are removed when the screen closes.
- The visitor card header/caption/metadata wrap correctly, and action buttons stack with usable width. The regression covers 320, 390, 440 and 900-pixel viewports at text scales 1.0, 1.5 and 2.0.

### Lifecycle and shifts

- The worker pauses on app background and restarts with an immediate refresh request on resume.
- The guard shell applies fresh logs even when the new list is empty.
- Shift/handover information refreshes after live revisions, with listener cleanup on disposal. Shift fetches remain a separate optional UI read.

## Main components

| Area | Files |
|---|---|
| API/session/strict reads | `mobile-app/lib/services/api_service.dart` |
| Polling, queue and acknowledgement | `mobile-app/lib/services/sync_queue_service.dart` |
| Visitor list reconciliation | `mobile-app/lib/repositories/visitor_repository.dart` |
| Session/profile/log display | `mobile-app/lib/features/guard/screens/guard_shell_screen.dart` |
| Scan freshness | `mobile-app/lib/features/scanner/screens/qr_scanner_screen.dart` |
| Open visitor card and enlarged QR | `mobile-app/lib/features/visitor/screens/visitor_pass_confirmation_screen.dart` |
| Shift updates and lifecycle | `mobile-app/lib/features/guard/widgets/shift_banner.dart`, `mobile-app/lib/main.dart` |
| Shared authenticated feed/security | `backend/api/updates.php`, `backend/lib/auth.php`, their admin deployment mirrors |
| Web synchronization counterparts | admin `live.js`, API/auth/core and feature subscriptions; owner API/app polling |

Some Dart files were also formatted. Tests' mock endpoints were updated to match the authenticated revision contract; production authorization assertions were retained.

## Verification performed

All backend mutations below used disposable PHP/SQLite sandboxes, generated fixture credentials and local external-service simulations. The working database and cloud server were not used for destructive tests.

| Check | Actual result | Evidence generated locally |
|---|---|---|
| Full Flutter regression suite | 177 passed, 0 failed; 1 real-PHP test skipped in this invocation and passed separately below | `artifacts/mobile-update-flutter-tests.log` |
| Mobile worker against real PHP | Passed: another authenticated client creates a vehicle, the actual Dart worker polls and updates its cache; disabling that guard immediately returns 401 and then ends the mobile API session | `artifacts/mobile-update-real-php.log` |
| Flutter analyzer | No issues | `artifacts/mobile-update-flutter-analysis.log` |
| Debug Android APK | Built with emulator API override on port 8001 | `artifacts/mobile-update-apk-build.log` |
| PHP/SQLite regression | 678 assertions passed, 0 failed | `artifacts/baseline-backend-suite.log` |
| Signed movement/concurrency | 85 checks passed | `artifacts/baseline-movement.log` |
| Revision/session/owner scope API | 19 checks passed | `artifacts/baseline-realtime-api.log` |
| Actual web transport with controlled DOM/timers | 12 unit checks passed | `artifacts/baseline-live-transport.log` |
| Two independent real-API web transport clients | 3 checks passed; renderers simulated | `artifacts/baseline-live-api-clients.log` |
| PHP/JavaScript syntax | 110 PHP and 33 JavaScript files passed; private config excluded | `artifacts/baseline-results.json` |
| Backend deployment mirror / source stability | No mirror differences; 238 application files unchanged during the current backend validation run | `artifacts/baseline-results.json` |

The real PHP mobile check executes the actual Dart ApiService and SyncQueueService without mocking HTTP. It does not mount a real phone UI or operate a camera. Flutter component tests separately verify card/QR rendering, notification updates and layout.

The earlier baseline had one failing visitor-card test and 20 analyzer diagnostics. The open-card subscription/layout and analyzer corrections in this update resolve those failures. The baseline report and CSV are retained as historical evidence; their older FAIL rows are not the current result.

## Reproduce safely

From repository root (Python, Node, PHP and Flutter installed):

```powershell
python -X utf8 tests/system_validation.py
python -X utf8 tests/mobile_php_integration.py
python sync_backend.py --check
```

`system_validation.py` captures a source manifest at the beginning of its own run and compares it afterward; it does not need a private pre-existing artifact. It starts temporary backend/database fixtures and does not run `api_smoke.py --fresh` on the working database. Set `SP_TEST_PHP` when PHP is outside the existing Windows XAMPP path. Set `SP_TEST_FLUTTER` if the Flutter executable cannot be found on PATH or at the local fallback path.

From `mobile-app/`:

```powershell
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8001/web-app-admin/api
```

Run `flutter pub get` first in a fresh checkout. The real-PHP check lives in `test/integration_checks/`; the ordinary Flutter suite skips that one check without fixture variables. Launch its Python wrapper separately to run it against disposable PHP. It passed in the dedicated execution above. Generated logs/APKs, local databases and secret configuration are ignored and are not pushed.

## Local use and backend requirements

1. Serve the updated `web-app-admin` deployment mirror and use that same API/database for admin, owner and mobile clients. `backend/` is canonical; do not independently run both copies against separate SQLite databases.
2. Keep existing private server configuration. The new revision endpoint uses the existing authentication, QR secret and schema; no new migration is introduced by this transport update. Existing missing migrations still need normal review before deployment. Never reset a live database using the fresh-install schema.
3. For an Android emulator, use `http://10.0.2.2:8001/web-app-admin/api`. On a phone, use the computer's reachable LAN IP; `127.0.0.1` on a phone points to the phone itself. The app's selected server is persisted, so verify it on sign-in even after installing a new APK.
4. The default source configuration still points to the existing cloud host. A Git branch push does not deploy `updates.php` there. A mobile build using this update must connect to an updated compatible backend before synchronization is expected to work.

## Does it work properly?

The tested mobile transport, API behavior, visitor-card UI and movement logic pass the checks above. This supports publishing a reviewable feature branch, not claiming complete deployment certification.

Not confirmed in this environment: physical Android camera/OCR, actual guard-shell navigation after disable on a device, multi-phone UI updates, Android process suspension, browser E2E, deployment MySQL concurrency and production-scale load. Browser access was previously rejected and no Android device/emulator was available.

Remaining audit work is documented in the [implementation plan](realtime-plan-and-system-validation-2026-10-09.md): web guard-direction parity, authoritative large-history KPI/reporting, historical offline-queue authorship across account switches, per-feature web response ordering, optional shift failure semantics, mobile/owner adaptive backoff and efficient revision storage. Existing placeholder actions, such as the visitor print notification, are not a verified physical printing pipeline. These have not been represented as fixed or fully tested.

## Publication scope

The branch includes documentation, automated tests, mobile changes and required backend/web counterparts. It also retains the earlier integration history. It does not include local secrets, data, generated logs or APK binaries. It is a new branch; no main-branch merge or server deployment is part of this publication.
