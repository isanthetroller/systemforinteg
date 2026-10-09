# Real-time transport, implementation plan and system validation

> Historical baseline before the subsequent mobile corrections. The user later authorized confirmation and publication on a new branch. See [current mobile update and test results](mobile-realtime-update-2026-10-09.md). Earlier failures and freeze/publication statements below describe that earlier phase, not the current state.

Date: October 9, 2026. Local integration branch. No push or deployment.

## A. Executive summary

The user requested two sequential phases: finish the previously discussed transport update, then perform the attached planning and baseline validation task. The transport changes were made locally first. Application code was then frozen with a SHA-256 manifest of 238 source files. The proposed follow-up fixes below were not applied during the planning/validation phase.

The new transport uses authenticated automatic polling, not WebSockets, SSE or instantaneous server push. Five-second foreground revision checks invalidate reads. Backend authorization remains independent of client notifications. A minute clock revision covers time-dependent displays. The admin transport single-flights requests, pauses hidden tabs and backs off failures. Mobile and owner polling need additional efficiency/recovery work. Full-table fingerprints preserve compatibility but require optimization at scale.

The strongest evidence covers real PHP/SQLite transactions, account-scoped revision APIs, Flutter mocked tests and JavaScript transport unit tests. Real browser E2E was blocked by automatic approval/security review when opening the isolated test portal; no alternate automation workaround was used. No Android device/emulator was available. A successful API test does not certify a rendered cross-platform workflow.

## B. Consolidated issue list

Classification is based on current source and executed evidence. “Resolved” applies to the stated layer, not all devices. Prior UI audit IDs R001–R008 and synchronization IDs RT001–RT010 are retained. New findings are N001–N012.

| ID | Current classification | Priority | Feature / affected application |
|---|---|---|---|
| RT001 | Already resolved at API/transport layer; device-key policy needs review | Critical | Invalid bearer fallback / backend, mobile |
| RT002 | Partially resolved; real navigation needs testing | High | Session/UI mismatch / mobile |
| RT003 | Partially resolved | High | Open details, pass cards and scan snapshots / web, mobile |
| RT004 | Partially resolved; rendering unverified | High | Owner same-count edits / owner web, backend |
| RT005 | Partially resolved; subscriptions added | High | Independent admin tables / admin web |
| RT006 | Partially resolved; repository refresh added | High | Remote visitor updates / mobile |
| RT007 | Partially resolved | High | False synced status and stale empty logs / mobile, web |
| RT008 | Partially resolved | High | Current role/profile / all clients |
| RT009 | Partially resolved | High | Overlapping refresh responses / web |
| RT010 | Partially resolved | High | Reconnect and foreground recovery / web, mobile |
| R001 | Confirmed and unresolved | Medium | Repeated dashboard tables / admin web |
| R002 | Confirmed and unresolved | High | Historical denials counted as active alerts / admin web |
| R003 | Confirmed and unresolved | High | Clear & Unblock versus case closure / admin, backend |
| R004 | Confirmed and unresolved | Medium | Historical/current facts mixed / admin web |
| R005 | Confirmed and unresolved | Medium | View versus View Details / admin web |
| R006 | Confirmed and unresolved | Low | Hidden legacy modules still active / admin web |
| R007 | Confirmed and unresolved | Medium | Repeated owner status and VIP instructions / owner web |
| R008 | Confirmed and unresolved | Medium | Pending versus actionable approval badge / admin web |
| N001 | Confirmed and unresolved | High | Web Guard 2 still restricted by username/gate / web guard |
| N002 | Confirmed and unresolved | High | Release CTA hides held vehicles physically inside / admin |
| N003 | Confirmed and unresolved | High | Bounded history used as complete totals/exports / web, mobile |
| N004 | Confirmed and unresolved | Medium | Case-row keyboard access and redundant columns / admin |
| N005 | Requires further testing | Medium | Counter selector/color mismatch / sidebar |
| N006 | Requires further testing; dirty-form protection added | Medium | Settings booleans/conflicting drafts / admin |
| N007 | Confirmed and unresolved | High | Full-domain hashing per client / backend, database |
| N008 | Confirmed and unresolved | Medium | Unrelated updates reset gate result / web guard |
| N009 | Confirmed and unresolved | Medium | Duplicate timers and broad refetching / all clients |
| N010 | Requires further testing | High | Historical queue identity across account switches / mobile |
| N011 | Cannot currently be verified | High | MySQL, browsers and physical devices / whole system |
| N012 | Debug logging confirmed; deployment exposure needs testing | High | Sensitive cookie logging and device-key scope / mobile |
| N013 | Confirmed by failed analyzer | Low | Duplicate import and brace diagnostics / mobile source |
| N014 | Confirmed by failed widget rendering | Medium | Visitor pass QR-caption overflow / mobile |

## C. Detailed implementation plan

Each issue card specifies the problem/root cause, expected behavior, technical steps, components, dependencies, risks, tests and acceptance criteria. Priority, affected application and feature are in section B. Proposed follow-ups require approval. Edit canonical backend files and then synchronize deployment mirrors with `python sync_backend.py`.

### RT001 — Invalid bearer fallback

- **Problem/root cause:** Invalid sessions previously fell back to device/anonymous scanner access; mobile retried without its bearer.
- **Expected behavior:** A revoked bearer is rejected immediately, regardless of device key.
- **Solution/steps:** Keep the added rejection before scanner-key evaluation, one-request 401 handling and refusal rather than offline queuing. Inventory every device-key-only endpoint and document legitimate device operations; narrow privileges separately after policy approval.
- **Components:** `backend/lib/auth.php`, `mobile-app/lib/services/api_service.dart` and legacy scanner endpoints.
- **Dependencies:** Existing current-account authorization and device-key contracts.
- **Risks:** Breaking legitimate scanner devices; preserve explicitly approved device operations while never accepting invalid staff credentials.
- **Tests/acceptance:** Invalid bearer plus valid device key returns 401; no anonymous retry or saved movement. Existing API and mobile unit checks pass; add an endpoint-by-endpoint regression matrix.

### RT002 — Session state diverges

- **Problem/root cause:** ApiService token and AuthService displayed user were independent; worker could stop while the shell still appeared signed in.
- **Expected behavior:** Server refusal ends the visible session and disables actions.
- **Solution/steps:** Keep sessionError/currentSessionUser notifications. Add a mounted-shell test for a polling 401, listener disposal and login navigation. Clear protected route content; preserve pending events under their original identity for review.
- **Components:** `api_service.dart`, `guard_shell_screen.dart`, `auth_service.dart`.
- **Dependencies:** RT001 and N010.
- **Risks:** Navigation using a disposed context; duplicate listeners or loss of legitimate pending history.
- **Tests/acceptance:** Disable a foreground guard, observe API rejection and login transition by the next session check; reactivation requires a new login. Real-device navigation remains unverified.

### RT003 — Open records retain snapshots

- **Problem/root cause:** Details, visitor confirmation and QR dialogs capture objects separately from refreshed lists. Cases can skip refresh while another dialog is open; history may fall outside the loaded page.
- **Expected behavior:** Read-only views show current data; draft edits are preserved with conflict warnings.
- **Solution/steps:** Keep record-ID tracking in web drawers and side-effect-free mobile prepare comparison. Subscribe visitor confirmation/full-screen QR by pass ID; show used/revoked/unavailable states. Fetch missing history by ID before assuming deletion. Reconcile a case after its action dialog closes. Use record revision checks before draft save.
- **Components:** `web-app-admin/js/{app,cases,visitors}.js`, `qr_scanner_screen.dart`, `visitor_pass_confirmation_screen.dart`, read-by-ID APIs.
- **Dependencies:** Stable IDs, RT007 and RT009.
- **Risks:** Lost drafts, accidental verification writes, truncated-list deletion assumptions.
- **Tests/acceptance:** Edit/revoke/delete the currently open record in another client; show fresh data or an explicit unavailable state. Preserve drafts; stale movement confirmation cannot save. Real open-card tests remain required.

### RT004 — Owner misses same-count changes

- **Problem/root cause:** Summary-only comparisons missed vehicle/driver/photo edits, case progress and profile changes.
- **Expected behavior:** Owner receives own field changes even when counts stay equal.
- **Solution/steps:** Retain scoped fingerprints and fresh authoritative reads followed by one state assignment. Keep enlarged QR open for unrelated clock changes, closing it for relevant pass changes. Add account-generation checks and recovery after initial-load failure.
- **Components:** `backend/api/updates.php`, `web-app-student/js/{api,app}.js`.
- **Dependencies:** RT008/RT009 and scoped owner APIs.
- **Risks:** Previous-account delayed responses or unnecessary eight-query refreshes.
- **Tests/acceptance:** Two owners, same-count edits, drivers/photos/case timeline and rapid logout/relogin. Own changes invalidate; unrelated owner changes do not. API scope passes, full rendering needs browsers.

### RT005 — Independent admin tables

- **Problem/root cause:** Users, visitors, payments and Admin Center used separate loaders/badge-only polling.
- **Expected behavior:** Visible tables follow relevant changes without losing filters/drafts.
- **Solution/steps:** Keep added subscriptions. Add per-view request generations, reload newly selected tabs from current revisions and propagate freshness errors only from read loaders. Audit mutation catches affected by the global fresh-read context.
- **Components:** `web-app-admin/js/{users,visitors,payments,center,cases,api}.js`.
- **Dependencies:** RT007/RT009.
- **Risks:** Concurrent mutation error handling, stale pagination and overwriting a dirty form.
- **Tests/acceptance:** Delay old tab/filter reads behind newer requests; mutate every domain in a second browser. Only the active request/session renders; filters and drafts survive.

### RT006 — Visitors update only locally

- **Problem/root cause:** VisitorRepository previously changed through local operations rather than authoritative remote refresh.
- **Expected behavior:** Both phones see issuance, revocation, usage and edits.
- **Solution/steps:** Keep list replacement/notifier publication; preserve unsent local records separately. Merge accepted offline records by stable ID/client reference and refresh confirmation screens using the same repository.
- **Components:** `visitor_repository.dart`, `sync_queue_service.dart`, visitor list/confirmation screens.
- **Dependencies:** RT003, RT007 and N010.
- **Risks:** Duplicating an acknowledged pending pass or replacing a revoked server record with local state.
- **Tests/acceptance:** Issue/revoke/use/delete across clients; reconnect with pending passes. Exactly one server record is shown, with explicit pending state for unsent records.

### RT007 — False synced status and empty results

- **Problem/root cause:** Fallback caches counted as live; empty log responses were ignored. Settings still return null on failure and shifts use separate fetches.
- **Expected behavior:** Acknowledge only complete required live reads; successful empty lists clear records.
- **Solution/steps:** Keep strict vehicle/log fetches and empty-list publication. Give settings/shifts explicit success contracts. Gather required reads before publishing/acknowledging a revision. Replace global freshness context with per-request options.
- **Components:** `api_service.dart`, `sync_queue_service.dart`, `guard_shell_screen.dart`, `shift_banner.dart`, admin `api.js`.
- **Dependencies:** Domain/query dependency map (N009).
- **Risks:** Partial cache publication or swallowed failures.
- **Tests/acceptance:** Fail each required domain separately, including settings/shifts. No successful-sync timestamp/ack on failure; unchanged revision retries and recovers. Vehicle/log failure and empty-log checks pass; settings/shift cases remain to implement.

### RT008 — Current role/profile stale

- **Problem/root cause:** Login-time user objects persisted after role/status/checkpoint changes.
- **Expected behavior:** Labels/routes follow current capabilities; server checks apply immediately.
- **Solution/steps:** Keep public session revision and user propagation. Reconcile current route and temporary-password state. Add staff/owner disable and role-change UI tests without exposing credentials.
- **Components:** `updates.php`, admin `auth.js`, `guard_shell_screen.dart`, owner `app.js`.
- **Dependencies:** RT001/RT002 and authoritative role checks.
- **Risks:** Privileged route remnants or old cache exposed to a different identity.
- **Tests/acceptance:** Promote/demote, reassign checkpoint, rename and disable an owner during an open action. Removed permissions are denied before notification. Role/profile API tests pass; UI tests remain.

### RT009 — Out-of-order web responses

- **Problem/root cause:** Legacy timers, filters and manual loads can overlap feature loaders despite core generation protection.
- **Expected behavior:** Only newest active-session request renders.
- **Solution/steps:** Extend core generation checks to every feature loader; key state by session. Cancel obsolete fetches where supported, retain generation checks, and remove duplicate timers after subscription coverage is proven.
- **Components:** `live.js`, `app.js`, `cases.js`, `payments.js`, `center.js`.
- **Dependencies:** RT005 and N009.
- **Risks:** Aborting an intended mutation or leaving a view permanently loading.
- **Tests/acceptance:** Controlled delays, fast filter changes, manual/automatic overlap and logout during reads. Core transport overlap/logout tests pass; each feature must also reject older results.

### RT010 — Reconnect/foreground gaps

- **Problem/root cause:** Lifecycle paths differed; mobile/owner still lack adaptive failure backoff.
- **Expected behavior:** Recover missed changes on foreground/reconnect without duplicate writes.
- **Solution/steps:** Keep web visibility/online wakes and mobile resume refresh. Add capped exponential backoff with jitter to mobile/owner; reset on success. Use authenticated snapshots for recovery. Do not promise delivery while Android suspends the process.
- **Components:** `live.js`, owner `app.js`, mobile `main.dart`, `sync_queue_service.dart`.
- **Dependencies:** RT007/RT009 and N010.
- **Risks:** Retry storms, delayed recovery and duplicate worker timers.
- **Tests/acceptance:** Hidden/online unit checks pass. Add airplane mode, process suspension, slow network and multi-hour soak. Resume reconciles automatically and does not duplicate writes.

### R001 — Dashboard repetition

- **Problem/root cause:** Wide dashboard lists repeat operational detail from On Campus/history rather than prioritize overview decisions.
- **Expected behavior:** Clear occupancy, today IN/OUT, active holds and recent activity.
- **Steps:** Define those metrics; use authoritative aggregates for cards/charts; retain a short recent list and links to full searchable views; remove fields repeated in actions.
- **Components:** admin `app.js`, `index.html`, styles; metrics APIs. **Dependencies:** N003.
- **Risks:** Hiding needed detail or misleading aggregates. **Tests/acceptance:** Responsive/keyboard checks with empty/large fixtures; metrics equal database totals and full details remain reachable.

### R002 — Denial history treated as active alerts

- **Problem/root cause:** Historical denied log rows inflate or duplicate active alerts after case closure.
- **Expected behavior:** One actionable alert per current open case; history remains intact.
- **Steps:** Key alerts by case ID, use authoritative open state, link history to the case and remove the active alert when closed.
- **Components:** admin `app.js`, `cases.php`, `incidents.php`. **Dependencies:** R003 and consistent case IDs.
- **Risks:** Dropping unresolved holds. **Tests/acceptance:** Repeat denial, close case, compare active counts/history; closed case disappears from active alerts without deleting its denied event.

### R003 — Two closure workflows

- **Problem/root cause:** Legacy Clear & Unblock and unified case closure use different APIs/outcomes.
- **Expected behavior:** Identical intent has identical case/hold/audit results.
- **Steps:** Route both entry points through the unified action, require outcome/reason, preserve unrelated holds, then deprecate the legacy shortcut.
- **Components:** admin `app.js`, `cases.js`, backend `incidents.php`, `cases.php`. **Dependencies:** Case policy and RT001.
- **Risks:** Unblocking a vehicle with another active violation. **Tests/acceptance:** Close through both views with another hold present; case history agrees and remaining holds still block.

### R004 — Event facts mixed with current profile

- **Problem/root cause:** Historical detail combines event snapshots and current owner/vehicle fields without labels.
- **Expected behavior:** Immutable event facts remain distinct from current information.
- **Steps:** Prioritize event time/checkpoint/action/officer; label current vehicle data explicitly; use saved event fields and remove repeated labels.
- **Components:** admin `app.js`, backend `logs.php`. **Dependencies:** Snapshot fields/read-by-ID.
- **Risks:** Invented historical facts from current data. **Tests/acceptance:** Edit owner/driver after movement; original facts remain unchanged and current facts are identified.

### R005 — Ambiguous/compressed actions

- **Problem/root cause:** View/View Details overlap and crowded action cells repeat visible row information.
- **Expected behavior:** One clear primary detail action with meaningful secondary operations.
- **Steps:** Consolidate detail entry, place distinct secondary actions in More actions, preserve expanded state/focus/Escape/outside-click behavior and adequate touch targets.
- **Components:** admin `app.js`, `index.html`, styles. **Dependencies:** Defined inspection versus detail workflow.
- **Risks:** Lost quick operations or inaccessible menus. **Tests/acceptance:** Keyboard/touch/viewport-edge checks; actions fit without cramped wrapping and every operation has a distinct purpose.

### R006 — Hidden legacy modules

- **Problem/root cause:** Redirected views still retain listeners/loaders; shared `SPViolations.openFlagModal` prevents simple removal.
- **Expected behavior:** One active case workflow without duplicate background work.
- **Steps:** Inventory shared references, extract flag action, migrate callers, remove dead routes/timers and retain bookmark redirects.
- **Components:** `violations.js`, `app.js`, `index.html`. **Dependencies:** R003 and caller inventory.
- **Risks:** Breaking flags. **Tests/acceptance:** Existing presentation tests before removal plus shared-modal/redirect tests; flags work and hidden loaders stop.

### R007 — Owner repetition/VIP instructions

- **Problem/root cause:** Repeated pass status/help and generic driver language conflict with VIP exemption.
- **Expected behavior:** Instructions match actual pass policy.
- **Steps:** One current status summary; standard driver rules only for standard passes; VIP/visitor/held/expired guidance based on authoritative class/eligibility.
- **Components:** owner `app.js`, `index.html`. **Dependencies:** Backend pass-class contract.
- **Risks:** Incorrect gate expectations. **Tests/acceptance:** Standard/VIP/held/expired fixtures agree with prepare requirements and QR display rules.

### R008 — Approval badge semantics

- **Problem/root cause:** All pending requests differ from requests the current admin may decide.
- **Expected behavior:** Navigation count communicates actionable work.
- **Steps:** Return total pending and current-user-actionable counts separately; show actionable badge and label total inside; retain second-admin rules server-side.
- **Components:** `center.js`, `approvals.php`. **Dependencies:** Current user RT008.
- **Risks:** Self-approval or hidden pending requests. **Tests/acceptance:** Two admins/requesters see correct different counters and cannot decide their own request.

### N001 — Web guard parity

- **Problem/root cause:** `gate.js` infers direction from username/gate text and blocks Guard 2 visitors; `app.js` also hides routes.
- **Expected behavior:** Checkpoint location is independent of permitted IN/OUT action.
- **Steps:** Move web prepare/confirm to the same automatic movement endpoint as mobile; remove username-based blocks after permission checks; preserve item/driver confirmation and idempotent references.
- **Components:** admin `gate.js`, `app.js`, `movements.php`. **Dependencies:** RT001, RT003 and signed movement contract.
- **Risks:** Legacy verification side effects or bypassed checks. **Tests/acceptance:** All four guard combinations through real browser UI, visitors, cancellation and concurrent stale scans; both guards process either direction at their own checkpoint.

### N002 — Release CTA/expiry

- **Problem/root cause:** CTA requires `Inside Campus`, but held vehicles may show `Blocked / Alert` while physically inside; prompt uses fixed duration.
- **Expected behavior:** Eligible held-inside vehicles have a release control with configured expiry.
- **Steps:** Expose physical-inside/release eligibility; use those fields in both detail locations; display `exit_release_minutes`; preserve one-time consumption and hold afterward.
- **Components:** `cases.js`, `app.js`, `ops.js`, `releases.php`, `campus.php`. **Dependencies:** Authoritative custody state.
- **Risks:** Releasing outside/ineligible vehicles. **Tests/acceptance:** Held-inside browser CTA plus cross-checkpoint one-time exit; server workflow passes but UI availability still needs correction/testing.

### N003 — Incomplete counts/filtering/exports

- **Problem/root cause:** Bounded recent log/payment arrays feed totals or local report filters; mobile KPI is not a full aggregate.
- **Expected behavior:** Complete totals and exports independent of recent-page limits.
- **Steps:** Add scoped aggregate metrics and server paging/filter totals; export full filtered queries; mobile uses authoritative occupancy/today totals; define campus-timezone day boundaries.
- **Components:** admin `app.js`, `payments.js`, backend `logs.php`, `payments.php`, mobile guard dashboard/shell. **Dependencies:** Read contracts and role scope.
- **Risks:** Expensive exports and timezone discrepancies. **Tests/acceptance:** Seed beyond 100/200/300 limits, compare counts/export IDs to database; recent-page length never represents all history.

### N004 — Case accessibility

- **Problem/root cause:** Pointer-only clickable rows and low-value uniform/closed columns.
- **Expected behavior:** Accessible useful rows for each filter.
- **Steps:** Real focusable View details control, keyboard activation, active/closed-specific columns and labelled expanded menus.
- **Components:** `cases.js`, `index.html`, styles. **Dependencies:** Stable detail action.
- **Risks:** Changed focus order. **Tests/acceptance:** Keyboard-only, screen-reader naming and narrow layouts; every operation remains reachable.

### N005 — Sidebar severity colors

- **Problem/root cause:** New `.sp-sidebar-count` markup may not match earlier ID selectors; opacity/inherited colors require computed-style verification.
- **Expected behavior:** Readable warning/danger counts with supplementary text meaning.
- **Steps:** Inspect real computed styles; apply solid semantic variants to actual markup; retain labels and avoid applying severity to unrelated counts.
- **Components:** `index.html`, admin styles, `cases.js`. **Dependencies:** Browser access and current counters.
- **Risks:** Poor contrast or color-only meaning. **Tests/acceptance:** Contrast, collapsed/active sidebar and reduced motion; warning/blocked counts remain readable. Source inspection alone cannot prove the visual defect.

### N006 — Settings types/drafts

- **Problem/root cause:** Numeric/string booleans need consistent parsing; external changes conflict with drafts. Dirty-form auto-refresh protection was added.
- **Expected behavior:** Consistent typed values and explicit conflicts.
- **Steps:** Normalize booleans at API boundary; warn on revision conflict, require reload/merge before saving and reset dirty state after save.
- **Components:** `center.js`, `settings.php`. **Dependencies:** Settings revision/read contract.
- **Risks:** Silent overwrite or invalid values. **Tests/acceptance:** 0/1/true/false/invalid fixtures and two-admin edits; drafts survive and stale writes require a decision.

### N007 — Fingerprint cost

- **Problem/root cause:** Each poll hashes complete domain rows, including large fields; cost scales with clients/history/photos.
- **Expected behavior:** Low-cost complete invalidation at target scale.
- **Steps:** Measure first; add transactional domain/account revision counters, bump with all writes in the same transaction, version/hash large fields and define external DB edit reconciliation. Apply migrations only after approval.
- **Components:** `updates.php`, write handlers, database migrations. **Dependencies:** Complete write inventory, N011 and performance targets.
- **Risks:** Missed invalidations, rollback counter changes and migration incompatibility. **Tests/acceptance:** Every write/rollback/direct-edit policy, concurrent counters, SQLite/MySQL and realistic client/data load; no missed changes and agreed latency/CPU budget.

### N008 — Unrelated gate resets

- **Problem/root cause:** Any changed movement/case/vehicle domain conservatively clears the web gate result.
- **Expected behavior:** Only changes affecting this pass interrupt confirmation.
- **Steps:** Compare record revision/eligibility through side-effect-free prepare/read; never automatically invoke legacy verify if it logs denials. Invalidate only relevant pass/movement/settings changes.
- **Components:** `gate.js`, `movements.php`. **Dependencies:** N001/RT003.
- **Risks:** Automatic verification writes or accepting a changed pass. **Tests/acceptance:** Unrelated movement keeps the confirmation; changed pass disables it immediately; backend remains authoritative.

### N009 — Excessive refresh work

- **Problem/root cause:** Minute timers coexist with transport; mobile reloads all vehicles/logs for any changed domain; owner reloads eight endpoints for clock ticks.
- **Expected behavior:** One scheduler and only dependent query/render work.
- **Steps:** Map domain dependencies, reload affected queries, render time changes locally, remove covered timers, jitter polling and suppress identical renders.
- **Components:** `cases.js`, `payments.js`, `center.js`, `ops.js`, `sync_queue_service.dart`, owner `app.js`. **Dependencies:** RT005/RT007/N007.
- **Risks:** Missing expiry or cross-domain effects. **Tests/acceptance:** Count idle/change/clock requests and renders; idle clients use one lightweight feed request and changed domains reload only dependent data.

### N010 — Queue authorship/order

- **Problem/root cause:** Historical offline queue persists across logout, independently of signed uncertain-confirmation retries; different-account replay needs testing.
- **Expected behavior:** Original authorship retained; history never reverses newer custody.
- **Steps:** Bind queue items to originating staff identity, prevent silent replay by a different session, expose pending/rejected review and define late-event ordering. Keep original payload/reference for uncertain online confirmation.
- **Components:** `sync_queue_service.dart`, `local_cache_service.dart`, `sync.php`. **Dependencies:** RT001/RT002 and queue migration policy.
- **Risks:** Legitimate history loss or officer impersonation. **Tests/acceptance:** Queue as A, log in as B, revoke A, reconnect; verify refusal/review and authorship. This exact scenario is NOT TESTED, not a proven exploit.

### N011 — Runtime evidence gaps

- **Problem/root cause:** SQLite test environment, no disposable MySQL/device and rejected browser access.
- **Expected behavior:** Same workflows verified on deployment database and real clients.
- **Steps:** Provision dedicated disposable MySQL, two browsers and two Android clients; apply migrations only there; run transaction and UI pipelines, physical scans, reconnect/background, TLS/email.
- **Components:** backend config/migrations, Android build/runtime, integration harness.
- **Dependencies:** Authorized test environment/devices, no production data.
- **Risks:** MySQL deadlocks, hosting worker limits or device-only faults. **Tests/acceptance:** Same role/transaction checks plus every rendered cross-client pipeline pass before deployment certification.

### N012 — Sensitive debug logs

- **Problem/root cause:** Challenge solver prints solved anti-bot cookie in debug output; release transport/device-key scope needs environment review.
- **Expected behavior:** No sensitive cookie/bearer/password in logs.
- **Steps:** In approved follow-up remove cookie material, log only outcome/request ID, inspect release logs and review HTTPS/device key scope/rotation. Do not include production secrets in artifacts.
- **Components:** `api_service.dart`, `api_constants.dart`, secret examples, auth policy.
- **Dependencies:** Release configuration and device policy.
- **Risks:** Credential exposure or breaking host challenge handling. **Tests/acceptance:** Authenticate/solve challenge, scan logs for generated known secrets and check protected HTTPS; no sensitive values logged.

### N013 — Analyzer does not pass

- **Problem/root cause:** Frozen source has one duplicate import in the scanner and 19 missing-brace style diagnostics in scanner/API/queue code. The local transport additions were not fully lint-clean before the freeze.
- **Expected behavior:** `flutter analyze --no-pub` exits successfully with no diagnostics.
- **Steps:** In the approved follow-up remove the redundant import and wrap each flagged conditional body; format only changed files and rerun analyzer/full tests/build. No behavior change is intended.
- **Components:** `qr_scanner_screen.dart`, `api_service.dart`, `sync_queue_service.dart`.
- **Dependencies:** None beyond the frozen baseline. **Risks:** Accidentally changing a conditional scope; check each hunk.
- **Tests/acceptance:** Zero analyzer diagnostics, unchanged transport behavior, full regression suite and APK build. Evidence: `artifacts/realtime-flutter-analysis.log`, analyzer exit 1. This is a real failed check, not a runtime compilation error.

### N014 — Visitor confirmation caption overflow

- **Problem/root cause:** The QR-caption horizontal Row at `visitor_pass_confirmation_screen.dart:405` sizes its text beyond the available width. The executed fixture produced a 110-pixel right overflow with a 382-pixel Row constraint.
- **Expected behavior:** Every caption remains readable inside the card at phone/tablet widths and large text settings.
- **Steps:** Make the text flexible/wrapping (or use a vertical/Wrap layout), keep the QR itself correctly sized and readable, and add width/text-scale tests including long validity strings.
- **Components:** `visitor_pass_confirmation_screen.dart` and visitor widget tests. **Dependencies:** RT003 changes should preserve layout while subscribing to the current pass.
- **Risks:** Clipping the caption or shrinking the QR below a useful scan size.
- **Tests/acceptance:** No layout exception at 320/390/440/900 viewport widths and supported large-text scales; QR/photo actions remain reachable. Current baseline test reports a layout failure as well as the stale-name assertion; both are documented separately, not counted as two failed test cases.

## D. Full-system testing architecture

1. Python starts two PHP workers in a temporary directory sharing a new disposable SQLite database. Backend code is copied; production secrets/data are excluded. QR/device keys and account credentials are generated for fixtures. Local SMTP capture tests avoid real recipients. Context cleanup stops servers and removes test data.
2. Movement tests assert actual status, log IDs/counts, release consumption and notice counts, concurrent requests and forced transaction rollback. Separate authenticated staff/owner/device clients verify scope.
3. Node `vm` runs actual `live.js` with a minimal fake DOM, API doubles and controlled timers. It tests automatic invalidation, retries, visibility, online and session-generation behavior. It is not browser E2E and does not execute complete SP rendering against live PHP.
4. Flutter existing model/widget/API/queue tests use mocked HTTP and local cache. Existing “Web roundtrip” test names describe mocked contracts, not real web-to-phone E2E. New tests exercise strict fetch, empty logs and one-request 401 handling.
5. Static/build checks include PHP lint, JavaScript syntax, Flutter analyzer/debug APK and backend mirror parity. Builds demonstrate compilation only.
6. Frozen production-source hashes are compared after baseline. Test harness, reports and ignored artifacts may change. Never run `api_smoke.py --fresh` against the working database or standalone legacy scripts against the user's running server.

### Transport and consistency

User action → authenticated API → authorization/transaction → database commit → scoped fingerprint changes → next foreground client poll → fresh dependent reads → ID/list reconciliation → acknowledgement.

Feed responses include fingerprints and public current user, not underlying sensitive records. Owner scope is their vehicles/drivers/logs/cases/payments/notices; guards exclude admin-only staff/approval/payment domains. Server account checks deny disabled sessions immediately; reactivation does not revive a revoked token.

Snapshots recover missed changes. Opaque hashes are not monotonic event sequence numbers, and there is no durable event delivery/replay promise. Single-flight/generation checks prevent stale client acknowledgement. Multi-table hashing can straddle commits; next polling recovers, but coherent snapshots or transactional monotonic revisions are needed for stronger guarantees. Movement client references and DB constraints prevent duplicates independently of UI transport.

Mobile background suspension pauses polling; foreground/resume recovers. Cached state is not permission to confirm an online movement. Uncertain saved operations retain the same retry payload; legacy offline history needs N010 identity review. No new dependency installation was required.

## E. End-to-end simulation results

### Executed frozen-source results

| Check | Actual result | Evidence |
|---|---|---|
| Broad real PHP/SQLite regression | PASS — 678 assertions, 0 failures | [baseline-backend-suite.log](../artifacts/baseline-backend-suite.log) |
| Signed movement/concurrency integration | PASS — 85 assertions | [baseline-movement.log](../artifacts/baseline-movement.log) |
| Authenticated revision/session API integration | PASS — 19 assertions | [baseline-realtime-api.log](../artifacts/baseline-realtime-api.log) |
| Web transport units with simulated DOM/timers | PASS — 12 checks | [baseline-live-transport.log](../artifacts/baseline-live-transport.log) |
| Real API with independent admin and guard transport clients | PASS — 3 checks; simulated renderers, not browser E2E | [baseline-live-api-clients.log](../artifacts/baseline-live-api-clients.log) |
| Flutter full suite including new stale-card baseline | FAIL — 168 passed, 1 test failed | [baseline-flutter-tests.log](../artifacts/baseline-flutter-tests.log) |
| Flutter analyzer | FAIL — 1 warning, 19 style diagnostics | [realtime-flutter-analysis.log](../artifacts/realtime-flutter-analysis.log) |
| Android debug APK | PASS — build only | [baseline-apk-build.log](../artifacts/baseline-apk-build.log) |
| PHP / JavaScript syntax | PASS — 110 PHP / 33 JS files | [baseline-results.json](../artifacts/baseline-results.json) |
| Mirror parity and source freeze | PASS — no mirror differences; 238 source hashes unchanged | [baseline-results.json](../artifacts/baseline-results.json) |
| Legacy violations presentation | PASS — simulated DOM checks | [baseline-violations-ui.log](../artifacts/baseline-violations-ui.log) |

The earlier transport/regression suite had 168 passing Flutter tests. Adding a targeted, non-skipped open-card baseline produced 168 passes and one failure. That failure is preserved: it demonstrates stale card text and a separate QR-caption layout overflow. No assertions were weakened to obtain a green baseline.

Real movement tests exercise G1→G1, G1→G2, G2→G1 and G2→G2, cancellation, duplicate confirmation, competing guards, lost-response retry, forced rollback, stale/expired/tampered tickets, changed holds/pass eligibility, one-time release, VIP driver exemption and visitor items. They check committed records and shared web/owner API reads. They do not execute real UI navigation or camera scans.

The real transport test starts two separate Node clients, executes actual `live.js`, commits a vehicle through an authenticated API, checks one database row, then waits for each five-second poll to read and publish the new record. Admin and guard clients both reconcile automatically. Its renderer is simulated; this proves the live API/transport connection, not full frontend rendering or mobile-to-mobile behavior.

The debug APK was rebuilt with `--dart-define=API_BASE_URL=http://10.0.2.2:8001/web-app-admin/api`. No install or phone runtime was performed. Default source configuration still points to the existing cloud host, whose backend was not deployed by this task. Select the updated local server when testing local clients; cloud and local databases are not automatically the same system.

### Major feature inventory — executed backend layer

| Feature/workflow group | Actual API assertions | Result | Evidence |
|---|---:|---|---|
| Authentication & first-login password change | 12 | PASS at API/database layer | [baseline-backend-suite.log:2](../artifacts/baseline-backend-suite.log:2) |
| Staff accounts & role enforcement | 14 | PASS at API/database layer | [baseline-backend-suite.log:16](../artifacts/baseline-backend-suite.log:16) |
| Login lockout | 2 | PASS at API/database layer | [baseline-backend-suite.log:32](../artifacts/baseline-backend-suite.log:32) |
| Mobile scanner (device key, no token) | 7 | PASS at API/database layer | [baseline-backend-suite.log:36](../artifacts/baseline-backend-suite.log:36) |
| Signed QR passes & verification | 26 | PASS at API/database layer | [baseline-backend-suite.log:45](../artifacts/baseline-backend-suite.log:45) |
| Legacy (pre-v2) passes | 9 | PASS at API/database layer | [baseline-backend-suite.log:73](../artifacts/baseline-backend-suite.log:73) |
| Gate flow: ingress / egress with driver confirmation | 14 | PASS at API/database layer | [baseline-backend-suite.log:84](../artifacts/baseline-backend-suite.log:84) |
| Violations (hold until resolved, no strikes) | 31 | PASS at API/database layer | [baseline-backend-suite.log:100](../artifacts/baseline-backend-suite.log:100) |
| Overtime & overnight parking list (staff decide, nothing automatic) | 15 | PASS at API/database layer | [baseline-backend-suite.log:133](../artifacts/baseline-backend-suite.log:133) |
| Single-day visitor passes | 25 | PASS at API/database layer | [baseline-backend-suite.log:150](../artifacts/baseline-backend-suite.log:150) |
| Student portal accounts & scoping | 29 | PASS at API/database layer | [baseline-backend-suite.log:177](../artifacts/baseline-backend-suite.log:177) |
| Visitor items & on-campus list | 19 | PASS at API/database layer | [baseline-backend-suite.log:208](../artifacts/baseline-backend-suite.log:208) |
| Scheduled day passes, revoke while inside, retired setting | 41 | PASS at API/database layer | [baseline-backend-suite.log:229](../artifacts/baseline-backend-suite.log:229) |
| VIP passes (permanent vehicles) | 31 | PASS at API/database layer | [baseline-backend-suite.log:272](../artifacts/baseline-backend-suite.log:272) |
| Offline sync (mobile events recorded without a connection) | 78 | PASS at API/database layer | [baseline-backend-suite.log:305](../artifacts/baseline-backend-suite.log:305) |
| Registration fee payments (cashier + online) | 49 | PASS at API/database layer | [baseline-backend-suite.log:385](../artifacts/baseline-backend-suite.log:385) |
| Vehicle classes: limit, override, replace, retire | 33 | PASS at API/database layer | [baseline-backend-suite.log:436](../artifacts/baseline-backend-suite.log:436) |
| Gate loopholes closed (payment, expiry, drivers, deletion, re-pricing) | 34 | PASS at API/database layer | [baseline-backend-suite.log:471](../artifacts/baseline-backend-suite.log:471) |
| Owner notices (portal + e-mail) and on-campus details | 14 | PASS at API/database layer | [baseline-backend-suite.log:507](../artifacts/baseline-backend-suite.log:507) |
| Renewals, exit release, capacity, shifts, evidence, HTTPS | 81 | PASS at API/database layer | [baseline-backend-suite.log:524](../artifacts/baseline-backend-suite.log:524) |
| Cases (one process for violations and security incidents) | 45 | PASS at API/database layer | [baseline-backend-suite.log:607](../artifacts/baseline-backend-suite.log:607) |
| Visitor vehicle photo | 11 | PASS at API/database layer | [baseline-backend-suite.log:654](../artifacts/baseline-backend-suite.log:654) |
| On Campus: a closed case no longer shows as blocked | 8 | PASS at API/database layer | [baseline-backend-suite.log:667](../artifacts/baseline-backend-suite.log:667) |
| Audit log, reasons, second-admin approvals | 50 | PASS at API/database layer | [baseline-backend-suite.log:680](../artifacts/baseline-backend-suite.log:680) |

This inventory includes accounts, lockout, signatures/legacy QR, vehicles/classes/drivers, gates, violations/overnight, visitors/items/photos, owner scope/notices, historical sync, cashier/online payment contracts, renewals, approvals/audit, settings/capacity/shifts/evidence and unified cases. Local SMTP/provider simulations do not prove live external delivery.


## F. Real-time synchronization results

Content fingerprints detect inserts/edits/deletes rather than only count changes. API checks verify two clients, role changes, owner scope and revocation. Timer tests verify automatic invalidation with controlled responses, not actual browser rendering.

Subscriptions are wired for admin core/feature tables, owner data, mobile vehicle/log caches, visitor repository and current session profile. Remaining gaps: open mobile visitor confirmation/QR, history outside loaded pages, case dialogs, feature-level request ordering, settings/shift failure acknowledgement, offline authorship, over-broad gate invalidation and scale. These are explicit planned follow-ups, not passing end-to-end claims.

## G. Security and data integrity results

Signed movement prepare/confirm remains staff-only and revalidates current eligibility under lock. Checks cover modified/expired tickets, signatures, driver/item requirements, changed holds/reissued passes, releases, duplicate retries, concurrent requests and rollback. Legacy device-key endpoints remain a separate surface needing scope review; an invalid bearer cannot fall back through them. MySQL lock/deadlock parity is unverified.

No production data or credentials are included in this report. Test fixture credentials are used only in disposable environments. Existing mobile cookie debug logging is a separate follow-up N012.

## H. Test coverage matrix

The complete assertion-level CSV records test identifiers, application, feature/scenario, expected/actual behavior, type, result, evidence line and related issue where applicable:

[system-validation-coverage-2026-10-09.csv](system-validation-coverage-2026-10-09.csv) — 992 rows. These are coverage rows, not independent test-case counts. The single failed Flutter test has separate rows for its stale-content and layout symptoms.

| ID / application | Scenario | Type | Expected → actual | Result | Issue |
|---|---|---|---|---|---|
| FLT-ALL / Mobile | All existing tests plus new transport and open-card baseline | Mocked unit/component tests | All 169 tests pass → 168 passed; one new visitor live-card test failed, with stale text and a layout overflow | FAIL | RT003, RT006, N014 |
| FLT-CARD / Mobile | Repository publishes changed/blocked pass while confirmation is already open | Executed widget baseline | Updated fixture visitor replaces original text → Zero matching updated widgets; original pass remains rendered | FAIL | RT003, RT006 |
| FLT-LAYOUT / Mobile | Render confirmation with current validity caption | Executed widget rendering in same test case | No RenderFlex overflow → 110-pixel right overflow at Row line 405 under 382-pixel constraint | FAIL | N014 |
| E2E-WW / Cross-platform | Two administrator browser sessions automatically update rendered views | Required workflow/runtime validation | Two administrator browser sessions automatically update rendered views → Browser access rejected by automatic approval/security review | BLOCKED | RT005, N011 |
| E2E-WM / Cross-platform | Web blocks/edits while real phone renders current account/vehicle | Required workflow/runtime validation | Web blocks/edits while real phone renders current account/vehicle → No Android device/emulator; browser also unavailable | BLOCKED | RT002, RT004, RT008, N011 |
| E2E-MW / Cross-platform | Physical guard scan updates another real browser dashboard | Required workflow/runtime validation | Physical guard scan updates another real browser dashboard → No Android device/emulator and browser access rejected | BLOCKED | RT003, N001, N011 |
| E2E-MM / Cross-platform | Two real phones synchronize movement/pass details | Required workflow/runtime validation | Two real phones synchronize movement/pass details → No Android devices/emulators | BLOCKED | RT003, RT006, N011 |
| E2E-GATES / Cross-platform | All four guard combinations through actual UI and cameras | Required workflow/runtime validation | All four guard combinations through actual UI and cameras → Real APIs pass separately; actual browser/device execution unavailable | BLOCKED | N001, N011 |
| E2E-OWNER / Cross-platform | Pass/activity/cases/payments/notices/profile update visually | Required workflow/runtime validation | Pass/activity/cases/payments/notices/profile update visually → Browser access rejected | BLOCKED | RT004, R007 |
| E2E-ADMIN / Cross-platform | Dashboard/vehicles/campus/history/cases/visitors/payments/Admin Center/settings/approvals/evidence visual flow | Required workflow/runtime validation | Dashboard/vehicles/campus/history/cases/visitors/payments/Admin Center/settings/approvals/evidence visual flow → Browser access rejected | BLOCKED | RT003, RT005, R001–R008 |
| E2E-CAMERA / Cross-platform | Physical camera scanning, OCR and image upload on device | Required workflow/runtime validation | Physical camera scanning, OCR and image upload on device → No Android device/emulator; parser/widget tests are separate | BLOCKED | N011 |
| E2E-LIFECYCLE / Cross-platform | Airplane mode, background suspension and app-resume rendering | Required workflow/runtime validation | Airplane mode, background suspension and app-resume rendering → No real mobile runtime | BLOCKED | RT010 |
| DB-MYSQL / Cross-platform | MySQL migrations, row locks, deadlocks and rollback parity | Required workflow/runtime validation | MySQL migrations, row locks, deadlocks and rollback parity → No configured disposable MySQL test environment | BLOCKED | N011 |
| NET-DB / Cross-platform | Whole database unavailable and subsequent live UI recovery | Required workflow/runtime validation | Whole database unavailable and subsequent live UI recovery → Injected transaction rollback passed; whole DB shutdown recovery not executed | NOT TESTED | RT007, RT010 |
| NET-SOAK / Cross-platform | Multi-hour sessions, very slow network and target-scale soak | Required workflow/runtime validation | Multi-hour sessions, very slow network and target-scale soak → Bounded request/timer tests only; no workload/SLO supplied | NOT TESTED | RT010, N007 |
| QUEUE-IDENTITY / Cross-platform | Queued event from guard A replayed after login as B | Required workflow/runtime validation | Queued event from guard A replayed after login as B → Specific account-switch queue scenario not executed | NOT TESTED | N010 |
| SESSION-EXPIRY / Cross-platform | Wall-clock session lifetime expiration during open UI | Required workflow/runtime validation | Wall-clock session lifetime expiration during open UI → Revocation/reset tested; natural lifetime expiration not separately executed | NOT TESTED | RT002, RT008 |
| MAIL-LIVE / Cross-platform | Actual mailbox delivery and real payment provider callback | Required workflow/runtime validation | Actual mailbox delivery and real payment provider callback → Local SMTP and simulated payment contracts only | NOT TESTED | N011 |
| REV-COUNTERS / Cross-platform | Transactionally persisted domain revision counters | Required workflow/runtime validation | Transactionally persisted domain revision counters → Current implementation hashes row content | NOT IMPLEMENTED | N007 |
| CARD-SUBSCRIBE / Cross-platform | Card subscribes by ID to repository changes | Required workflow/runtime validation | Card subscribes by ID to repository changes → Failed baseline proves existing snapshot remains static | NOT IMPLEMENTED | RT003, RT006 |
| KPI-SERVER / Cross-platform | Mobile dashboard uses full authoritative daily aggregate | Required workflow/runtime validation | Mobile dashboard uses full authoritative daily aggregate → Current display derives data from bounded recent logs | NOT IMPLEMENTED | N003 |
| PHP / Static/build/client units | PHP syntax | Static/build | Check succeeds → 110 PHP files; private config excluded | PASS |  |
| JS / Static/build/client units | JavaScript syntax | Static/build | Check succeeds → 33 files checked | PASS |  |
| ANALYZE / Static/build/client units | Flutter analyzer | Static/build | Check succeeds → 1 duplicate-import warning and 19 brace diagnostics; exit 1 | FAIL | N013 |
| BUILD / Static/build/client units | Android debug APK | Static/build | Check succeeds → assembleDebug built successfully; emulator API override on port 8001 | PASS | N011 |
| LEGACY / Static/build/client units | Legacy violations presentation units | Simulated DOM presentation | Check succeeds → Pagination/filter/search/empty/loading/manual/background checks passed | PASS | R006 |

Core recovery coverage: executed Node units pass network failure/backoff, same-revision retry after subscriber failure, single-flight, hidden-tab wake, online wake, logout/in-flight discard and rapid relogin. Flutter units/widgets pass strict failed reads, empty log response, 401 without fallback, offline queue refusal/retry and uncertain movement payload retention. These are controlled simulations, not physical outage tests.

### Reproduction

Run from the repository root: `python -X utf8 tests/system_validation.py`. It uses disposable backend sandboxes and emits `artifacts/baseline-results.json`; it does not run Flutter or claim full-system PASS. Run Flutter separately from `mobile-app`: `flutter test --no-pub --reporter expanded`, `flutter analyze --no-pub`, and `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8001/web-app-admin/api`. The Flutter test/analyzer commands currently fail for the documented baseline findings. `python tests/write_validation_report.py` rebuilds this evidence table from completed logs; it is not a test executor.


## I. Problems discovered during testing

Initial Flutter runs exposed fixture assumptions about anonymous queue processing, missing revision endpoints in HTTP mocks and malformed visitor-create records. Test fixtures were updated before the freeze without removing assertions; the resulting 168-test regression suite passed.

The expanded frozen baseline contains two failed checks:

1. **Open visitor widget test (RT003/RT006, High):** the repository publishes a changed/blocked pass, but the already open confirmation still uses its constructor snapshot. Updated visitor text has zero matching widgets. Add a pass-ID subscription and update the full-screen QR/eligibility display; verify changed, used, blocked and unavailable passes in a mounted screen and on real phones. The same test reports **N014 (Medium)**: the validity/QR caption Row overflows 110 pixels. Wrap/flex its text and rerun a width/text-scale matrix. One failing test case exposes two symptoms.
2. **Analyzer (N013, Low):** one duplicate-import warning and 19 missing-brace diagnostics; exit code 1. Remove the duplicate import and wrap conditional bodies in the approved follow-up, then rerun analyzer, tests and build. The APK compiles, so these diagnostics are not reported as compiler errors.

No application changes were made to suppress either result after the freeze. Additional confirmed source-level workflow/data gaps are in section B/C; unexecuted scenarios remain NOT TESTED or BLOCKED. There is no blanket whole-system PASS.


## J. Prioritized implementation roadmap

1. **Security/identity:** RT001 endpoint inventory, RT002/RT008 session/role UI, N010 queue identity, N012 logs. Depends on current auth and isolated multi-account fixtures. Risks: legitimate scanner disruption, pending history loss. Gate: revocation/scope/role/no-author-switch tests.
2. **Coherent synchronization:** RT003–RT010 remaining work, N008. Strict reads, per-view generations, session-scoped state, open pass subscriptions, draft conflicts and recovery. Depends on stable IDs and side-effect-free reads. Risks: lost drafts, stale acknowledgements. Gate: delayed/partial/empty/logout/reconnect/open-card tests.
3. **Workflow/report parity:** N001/N002/N003 and R002/R003. Flexible web guard flow, physical-inside release, authoritative totals/paging and unified cases. Depends on phases 1–2. Risks: hold/release policy regressions. Gate: four guard UI combinations, held-inside release, repeated denial and large-history totals/export.
4. **UI/accessibility:** R001/R004–R008/N004–N006. Dashboard/actions, historical labels, shared action extraction, VIP guidance, actionable badges/colors/settings conflicts. Depends on correct read contracts. Risks: lost operations/focus and confusing status. Gate: keyboard/touch/contrast/responsive/draft/policy checks.
5. **Reliability/scale/runtime:** N007/N009/N011, N013/N014 and RT010 backoff. Fix analyzer diagnostics and caption overflow in the approved follow-up. Transactional revision counters only after complete write inventory; load/soak and real MySQL/device/browser evidence. Risks: missed invalidations/migration/host exhaustion. Gate: clean analyzer, no layout exceptions, measured budgets, rollback/concurrency parity, two browsers/two phones, foreground recovery and release checks.

## K. Final assessment

The shared transactional backend has extensive automated coverage, with added transport/client tests. Whole-system stability is not certified. Open-screen coherence, web guard parity, complete metrics, release visibility, legacy duplication, queue identity and performance need follow-up. Real browsers, phones and MySQL must pass before declaring the complete pipeline reliable. No push, deployment or further production changes are authorized by this plan.

### Final freeze verification

All 238 recorded application-source hashes still match after testing/build/report generation. Backend deployment mirrors match. No push, commit, deployment or live-database destructive test was performed in this task.

### Temporary browser fixture cleanup

The browser-access attempt was blocked. Automatic approval review also rejected the combined server-stop/temporary-directory-removal command as blocked by policy, without further rationale. A narrower action stopped only the two verified PHP servers created for this task. Their temporary directory `C:/Users/ethan/AppData/Local/Temp/securepark-movement-c2c50xyy` was retained. Other pre-existing test servers were left untouched. Ordinary completed API sandbox contexts cleaned up normally.
