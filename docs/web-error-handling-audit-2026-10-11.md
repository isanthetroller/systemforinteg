# Web error handling audit (11 October 2026)

Scope: `web-app-admin/`, `web-app-student/`, and the canonical `backend/` API used by both. The mirrored PHP API in `web-app-admin/` is deployment output. Findings below come from source inspection; runtime scenarios are reported separately in the final verification section.

## Existing behavior and coverage map

| Area | Normal behavior | Existing failure handling |
|---|---|---|
| Staff sign-in, roles, password, session | Bearer session, server role checks, forced password change | Inline login/password errors; 401 event returns to sign-in; most forms disable their submit button |
| Fleet registration, edit, pass, status | Admin creates/updates records and the server issues or revokes signed passes | Mixed optimistic local mutation and server calls; server can request an audited reason or class-limit decision |
| Gate, visitor, cases, cashier, staff, settings | Guards/admins perform permission-bound operations against PHP API | Feature-specific dialogs/toasts and some inline errors; actions are generally server-confirmed |
| Admin monitoring and synchronization | Revision polling refreshes fleet, movements, cases and related panels | Offline banner and retry with backoff; stale cache can be used for selected reads |
| Owner sign-in, passes, activity, cases, payments, account | Owner reads scoped data and starts checkout; revision polling updates open screen | Inline authentication errors, offline banner and payment-status polling |
| Backend | Auth, validation, permissions, transactional movement and payment state | JSON errors with HTTP codes; movement confirmation has ticket/idempotency logic |

## Confirmed findings

| Page / feature | User action | Current behavior | Identified problem | Expected behavior | Proposed solution | Severity |
|---|---|---|---|---|---|---|
| Admin fleet | Register vehicle | `app.js` adds a row and reports enrollment before `registerVehicle` resolves; it resets the form immediately. On a network/server failure it may leave the local row and say it was saved locally. | False success, lost form input, possible duplicate retry. | Keep form and input until confirmed; show server refusal or uncertain network outcome; refresh before retry when outcome is uncertain. | Await POST, disable submit while pending, update list only from server result and reset after success. | Critical |
| Admin fleet | Register another vehicle for an owner | `app.js` rejects any owner ID already in the local fleet; `backend/api/vehicles.php` enforces one active vehicle **per vehicle class** and can request an audited override. | Valid registrations for a different class are blocked before the server can apply its rules. | Let the server decide by class and reason requirement. | Remove the broader local rejection while retaining duplicate plate feedback. | High |
| Admin fleet | Edit vehicle | `app.js` mutates the displayed object, closes edit modal, then sends PUT. On failure it rolls the object back but the entered edits are gone. | False current state and lost work. | Preserve modal input until server confirmation; keep original row on failure. | Await PUT before applying the saved state and closing. | High |
| Admin fleet | Activate/suspend pass | `app.js` changes status and shows success before PUT; failed API call is console-only. | False pass standing, dangerous gate decisions. | Show success only after server confirms; preserve old standing on failure. | Await PUT and render the server state. | Critical |
| Web gate | Deny vehicle and create a case | `gate.js` sends separate log and incident requests. A case failure after the log succeeds is reported as if the whole denial failed. | Partial save is hidden; retry can make another denial log. | Explain the partial result and direct the guard to review records and cases. | Track which write succeeded and report the stage accurately; an atomic backend operation remains a separate improvement. | High |
| Web gate | Approve or deny, then refresh list | `afterDecision()` is called without awaiting it. | A refresh failure can become an unhandled rejection after a saved decision. | Keep the confirmed decision and tell the guard that the list is stale. | Await the refresh separately from the write result. | Medium |
| Admin and owner API | Any API request | `api.js` has no timeout; admin non-JSON error includes endpoint, HTTP status and response excerpt in a user-visible exception. | Endless pending operations and possible internal text exposure. | Bound waiting time and explain connection/server failure in plain language. | Add request timeout and safe response classification without automatic POST retry. | High |
| Owner app | Initial page load after sign-in | `enterApp()` displays Loading your pass, then a failed `Promise.all` rejects. Boot hides the error; login displays it on the login form even though the token exists. | Blank/stuck page and confusing sign-in feedback. | Stay signed in, show a page-level retry control, preserve available data. | Render recoverable load state and retry without another login. | High |
| Owner payment return | Return from checkout | Payment-status or data refresh errors are swallowed and payment return parameters are removed immediately. | Owner may see an unconfirmed status without a clear retry route. | State that confirmation is pending and check again safely. | Keep payment context until resolved and poll the read-only status endpoint. | Medium |
| Owner live updates | Foreground revision poll | Errors set an offline banner, but there is no immediate retry on reconnect; next interval may be delayed. | Stale pass/hold information remains longer than necessary. | Recheck on connection recovery and tab visibility. | Wake polling on `online`/visibility. | Medium |
| Admin live updates | Revision poll | `live.js` has an offline banner and backoff, but does not distinguish server errors from disconnection. | Inaccurate user feedback. | Explain that live information may be outdated without claiming connectivity was lost. | Use neutral sync wording. | Low |

## Potential risks requiring runtime or broader review

| Area | Evidence / uncertainty | Verification needed |
|---|---|---|
| Concurrent fleet edits | Fleet update API does not visibly pass a version token from the form. | Two-admin edit session against a shared backend, including server conflict policy. |
| Background detail panels | Several detail loaders in `app.js` catch and ignore failures (`.catch(() => {})`). | Exercise each detail panel with API faults; determine whether an empty result is mistaken for no data. |
| Admin cached reads | `ApiClient.getVehicles/getLogs/getIncidents/getStats` may return cache after non-auth failures. | Verify stale indication on each consuming page while offline. |
| Full desktop/mobile behavior | Chrome runtime checks now cover a desktop staff viewport and a narrow owner viewport. | Keyboard focus, screen reader announcements, physical devices and broader navigation remain to be checked. |

## Priority

Correct false success and lost work in fleet mutations first, then bound and clarify API failures, then owner startup and live refresh recovery. Keep server validation and permission checks authoritative. Never automatically retry a write whose outcome is uncertain.

## Implementation and verification

The fleet now waits for confirmed registration, edit and pass status writes. The registration and edit forms remain intact on failure, and their buttons block repeat submissions while a request is running. The owner registration rule is left to the backend's per-class validation. Server duplicate-plate responses appear beside the plate input. A partial owner-login failure after successful registration is named accurately.

Both browser API clients bound reads to 30 seconds and writes to 60 seconds. They classify transport, malformed-response and service failures without displaying returned HTML or server excerpts. Writes are not automatically retried. The admin's offline cache announces stale data through the existing live status banner. The owner app offers a page-level retry if its initial data load fails and checks again on reconnect/foreground. Checkout return keeps its payment reference until the read-only status endpoint confirms Paid or Cancelled.

The web gate now separates a saved decision from a subsequent list-refresh failure. For a denied passage, it reports when the denial log succeeded but case creation did not. A stable `client_ref` is sent for each decision stage, using the backend's existing duplicate protection when a guard retries after an uncertain response. The two writes remain separate requests; a transaction across both still requires backend work.

| Verification | Result | Limit |
|---|---|---|
| JavaScript syntax checks for changed scripts | Passed | Parser only |
| `tests/web_api_failure_test.cjs` | Passed | Controlled fetch, no browser or database |
| `tests/live_transport_test.cjs` | Passed, 12 checks | Simulated transport |
| `tests/test_violations_ui.cjs` | Passed | Fake DOM |
| `git diff --check` | Passed | Whitespace only |
| `tests/web_error_runtime.py` | Passed: browser + real PHP/SQLite in a disposable sandbox | Staff desktop viewport and owner mobile viewport; failed and confirmed fleet writes, rapid double-click, partial gate denial/retry, session revocation, owner load recovery |
| Two-user concurrency and payment provider checkout | Movement concurrency passed in the broader system suite; external checkout not exercised | Provider credentials and callback environment unavailable |

Regression conclusion: the executed JavaScript and browser/PHP tests passed. The browser runtime run verified the changed fleet forms, a partial gate denial followed by a safe retry, and the owner load failure/retry path. Gate camera scanning and external payment checkout were not exercised. No backend files were changed.

### Changed files

| File | Purpose |
|---|---|
| `web-app-admin/js/api.js` | Bounded requests, safe errors, stale-cache announcement |
| `web-app-admin/js/app.js` | Server-confirmed fleet actions, form preservation and accurate account feedback |
| `web-app-admin/js/gate.js` | Idempotent decision references and accurate partial-save/refresh feedback |
| `web-app-admin/js/live.js` | Neutral stale-data status wording |
| `web-app-student/js/api.js` | Bounded requests and safe errors |
| `web-app-student/js/app.js` | Initial-load retry, reconnect refresh and payment confirmation recovery |
| Both portal `index.html` files | Script cache-version updates |
| `tests/web_api_failure_test.cjs` | Controlled failure and expired-session checks |
| `tests/web_error_runtime.py` | Disposable real PHP/SQLite and Chrome browser regression checks |
| This report | Findings, implementation and verification record |

## Cross-surface runtime verification

The later end-to-end run used a disposable PHP/SQLite database and a real Chrome session. It created a guard through the staff API, signed in with the mobile app's Dart `ApiService`, issued a visitor pass with declared items, then recorded entry and exit using the mobile service. The already-open web portal refreshed its visitor list and audit automatically after each write. The test checked the pass and its items, Inside and closed states, exactly one entry audit and one exit audit, and no uncaught browser exception. A duplicate mobile issuance and entry without checking declared items were rejected without extra records. The web visitor form was also exercised with an invalid contact number, a successful correction, and a duplicate plate attempt; it retained the invalid form and showed the server's duplicate refusal.

| Suite | Result | Scope and limit |
|---|---|---|
| `python tests/system_validation.py` | Passed: 678 backend assertions, movement concurrency, revision and live transport checks, 110 PHP and 33 JavaScript syntax checks | Disposable backend; includes a separate two-worker movement race |
| `python tests/mobile_php_integration.py` | Passed | Real mobile Dart sync worker observes remote fleet change and revoked session against PHP |
| `flutter test --no-pub --reporter compact` | Passed: 186 tests, 2 environment-gated skips | Mobile widgets, service, offline queue and mock roundtrip scenarios; includes visitor, camera and OCR interaction tests |
| `python tests/visitor_web_roundtrip.py` | Passed on repeated runs | Real mobile Dart HTTP service, disposable PHP/SQLite, Chrome live visitor and audit views, web visitor form |
| `python tests/web_error_runtime.py` | Passed again | Staff and owner browser failure/retry flows |

No Android device or emulator image was available: `adb devices` returned no device and `flutter emulators` found no emulator source. The mobile app's actual Dart service ran under Flutter's test runtime, so native camera scanning and device OS behavior were not exercised; phone viewport layouts were simulated in widget tests. An exhaustive combination of all inputs and external services is not feasible; these runs cover the high-risk state transitions and the existing backend's broad scenario matrix. No additional cross-surface server or browser defect surfaced in these runs.

### Mobile screen follow-up

Flutter widget tests now tap through the visitor registration checklist at a 390 px phone viewport, check that it sends one visitor pass and one gate audit, and check that a server refusal keeps the entered details and gives a visible reason. A layout matrix checks 320, 390 and 440 px widths at normal and 1.5× text sizes. The first run revealed `RenderFlex` overflows in the section heading, long field label and missing-fields message. Those rows now allow text to wrap, and the matrix passes without Flutter exceptions. `flutter analyze --no-pub lib test/visitor_registration_ui_test.dart` passed with no issues. These widget tests execute the actual registration screen with a controlled HTTP responder; the separate Dart/PHP/Chrome roundtrip tests the backend contract and live web result.

The UI test also exposed an inaccurate partial-success state: if the pass was issued but the separate gate-entry audit was refused, the registration screen proceeded to the pass card without telling the guard. It now presents an explicit warning and asks the guard to check the audit before admitting the visitor. The test confirms the warning and that the pass still opens after acknowledgment.

The Android debug APK also built successfully with `flutter build apk --debug --no-pub`. This confirms Android compilation but does not replace installation, camera/OCR checks or interaction on a physical device.

### Camera and OCR follow-up

The visitor camera screen had a false success path: it marked the security photo as captured even when no camera was initialized or taking/compressing the photo failed. It now marks capture only after valid image bytes have been compressed into a JPEG data URL, warns on failure, and removes the camera's temporary photo file after processing. Unreadable bytes are rejected by `PhotoCompress`. The photo success message now fits a phone viewport.

Manual OCR reports camera or recognition failure instead of silently doing nothing. Recognition results are ignored if the screen was disposed or the guard switched scan modes while processing. The plate fallback no longer accepts arbitrary OCR words as a plate. Focused widget tests cover absent camera, valid simulated photo bytes attached to a pass, an ID-name → plate → photo flow driven by sample OCR text, and noise rejection. The native camera plugin and ML Kit recognition still require an Android device or emulator with camera input for final hardware verification.
