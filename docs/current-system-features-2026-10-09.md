# SecurePark — current system feature report

Date: October 9, 2026. Application reviewed: commit `e8fc23f` on `feature/realtime-sync-mobile-20261009`.

This report describes the code currently in the repository. It distinguishes implemented features, tested behavior, configuration-dependent services and remaining gaps. A GitHub branch push does not update the cloud server or an installed mobile app.

## 1. Purpose and system parts

SecurePark manages campus vehicle registration, gate passes, entry/exit records, visitors, security cases and related payments. Administrators manage registrations and policy. Guards check passes and record movements. Vehicle owners see their own passes, activity and cases.

| Part | Main users | Purpose | Source |
|---|---|---|---|
| Admin/guard web portal | Security administrators and guards | Monitoring, vehicles, gate checks, visitors, cases and administration | `web-app-admin/` |
| Owner web portal | Registered students and employees | Own QR passes, activity, payments, cases and account | `web-app-student/` |
| Mobile gate app | Guards | Camera/manual QR checks, movement confirmation, visitor passes, evidence and duty | `mobile-app/` |
| Shared PHP API | All applications | Authentication, authorization, shared data and gate rules | `backend/` |
| Shared database | Server | Persistent records for the entire system | MySQL deployment or local SQLite fallback |

`backend/` is canonical. The PHP files under `web-app-admin/` are its deployment mirror. All applications must connect to the same updated API/database to share changes. Independently running both copies with different SQLite files creates separate systems.

## 2. Users and access

| User | Main permitted work | Important boundary |
|---|---|---|
| Administrator | Vehicle/staff/owner account management, payments, policy, approvals, case closure and monitoring | Sensitive changes require the relevant server permission, reason and sometimes another administrator's approval |
| Guard | Pass checking, permitted movements, visitors, case contact/notes, violations/incidents, evidence and duty | Cannot perform administrator-only changes or bypass a hold from the phone |
| Vehicle owner | Own profile, vehicles, signed passes, gate history, cases/notices and online payment/renewal | Cannot read another owner's records or confirm staff gate movements |
| Scanner device identity | Selected legacy scanner API operations using a configured device key | Does not replace a named staff session for signed movement prepare/confirm; an invalid bearer is rejected |

“Guard 1” and “Guard 2” identify staff/checkpoint assignments, not independent vehicle databases. The current mobile workflow allows both guards to handle both IN and OUT at their own authenticated checkpoint. Some older web gate UI restrictions still need alignment with that workflow.

### Authentication features

- Separate staff and owner sign-in through the shared API.
- Password verification, invalid-login handling and login lockout.
- Temporary staff passwords and required first-sign-in password change.
- Password changes/resets and session revocation rules.
- Active/inactive account status and current role checks on the server.
- Current public account/profile information supplied through the update feed.
- Mobile 401 handling ends the API session without retrying anonymously.
- Owner reads are scoped using the authenticated owner identity, not an arbitrary owner ID supplied by the browser.

Natural session expiration on a real long-running device and actual guard-shell navigation after disable still need runtime verification. Backend revocation and the mobile API session-ending path have executed coverage.

## 3. Vehicle registration and pass management

### Registration records

The system stores vehicle plate, vehicle type/class, description, owner identity/contact, registration standing, pass validity and authorized driver records. It supports listing, search/lookups, detail views, edits and driver/vehicle photos.

Operational controls include:

- Registering a vehicle and its authorized drivers.
- Enforcing vehicle-class/owner limits and recording justified extra-vehicle overrides.
- Replacing an old vehicle registration and retiring the earlier vehicle.
- Recording retirement reasons and preserving existing history.
- Restricting deletion when a registration has history; deletion requires an appropriate reason.
- Separating payment/registration standing from actual physical presence on campus.

### QR passes

- Registered passes are signed on the server with HMAC-SHA256. A client cannot generate a legitimate signature without the server secret.
- Pass verification checks the signature and current database record; the QR is not an unconditional permission to enter.
- Reissuing creates a new pass identity and invalidates previously issued codes, including older supported formats.
- Unpaid/retired registrations do not receive an active usable QR through the current registration flow.
- Validity, hold, suspension, payment and retirement rules are checked at the gate. Already-inside exit eligibility is handled separately from new entry eligibility where policy permits.
- The server retains compatibility with supported older QR/pass formats; that does not permit invented or revoked pass identities.

Main components: `api/vehicles.php`, `api/passes.php`, `lib/vehicles.php`, `lib/vehicle_ops.php` and the pass/QR helpers.

## 4. Normal vehicle entry and exit

### Current mobile workflow

1. A guard scans a QR or enters a code manually.
2. The server prepares a read-only movement preview.
3. Shared physical status determines the suggestion: OUTSIDE → IN; INSIDE → OUT.
4. The screen shows the vehicle/pass, current status, suggested action and the guard's checkpoint.
5. Ordinary registered vehicles require an authorized driver selection; visitor item checks apply when declared items exist.
6. The guard confirms or cancels. Preparation/cancellation does not save a movement.
7. Confirmation rechecks the current session, pass and eligibility under a database lock.
8. A successful transaction writes the movement/history and related state/notices together.
9. Other signed-in foreground clients detect the changed revision and refresh relevant data.

### Reliability and security controls

- Both guards can enter and exit the same vehicle in all four combinations.
- Signed confirmation tickets are bound to the staff/pass/checkpoint/current snapshot and expire after five minutes.
- Changed passes, holds or movement revisions invalidate an outdated preview.
- A competing guard cannot reuse another guard's confirmation ticket.
- Retrying the same confirmed request returns its original result instead of recording another movement or toggling direction.
- Competing confirmations are rechecked under lock; one cannot silently overwrite the other.
- Failed database transactions roll back related writes.
- A lost response retains the original ticket/request for retry. The current online flow does not queue a fresh toggle while the result is uncertain.
- A blocked/stale/refused screen cannot authorize a save solely from cached data.

Main components: `api/movements.php`, `lib/movements.php`, mobile `qr_scanner_screen.dart` and `movement_confirmation_card.dart`.

### Web gate monitor

The web portal also provides QR/camera/scanner/manual lookup, displayed eligibility, driver confirmation and approve/deny actions. Its legacy direction controls and Guard 2 restrictions are not fully aligned with the newer automatic mobile flow. The web UI should not be described as already providing complete flexible-guard parity.

## 5. Visitors and day passes

- Guards can issue a visitor pass for the current day. Administrators can issue supported future-day passes within the allowed scheduling window.
- Records include visitor name/contact, plate, vehicle details/photo, purpose/person to visit and declared items.
- Server-issued visitor QR payloads can be displayed at normal size or enlarged for the visitor to photograph.
- Passes are valid for their specified calendar day; they are not the same as a permanent vehicle registration.
- A future pass is refused before its date. Used/revoked/invalid passes are checked against server state.
- Guards verify declared items for the relevant entry/exit action. The check is recorded with the movement.
- A visitor already inside after the date ends is handled by the exit/overstay policy, preserving physical custody information.
- Visitor list records refresh from the server. Open mobile confirmation cards and enlarged QR dialogs follow the same pass by identity.
- Blocked, expired, used or removed records no longer display a usable QR on that mobile confirmation screen.

Offline visitor issuance and historical synchronization remain separate legacy capabilities. An offline code is not a newly generated server signature and should not be assumed available to another device/server before successful synchronization. Pending/refused records and cross-account queue authorship still need further review.

The mobile “Print Physical Decal / Ticket” action currently shows a notification; it is not a verified print service. Do not count it as successful physical printing.

## 6. VIP passes

- VIP is a server-stored pass class, with grant information, not a privilege trusted solely from QR text.
- VIP passes remain signed, revocable and recorded in gate history.
- The current policy provides exemptions including ordinary driver confirmation and the standard violation/overtime treatment where the server defines them.
- Granting/changing VIP status can use second-administrator approval when that policy is active.
- Gate displays include the VIP class and relevant notices.

A VIP display is not a general bypass for authentication or a tampered/revoked QR. Owner help text still needs cleanup so standard driver instructions are not shown as if they apply to every VIP pass.

## 7. On-campus monitoring and history

### On Campus Now

The web view combines registered vehicles and visitors physically inside. It displays arrival order, entry time, duration, vehicle/owner/driver information, checkpoint/officer and contact/hold information. Staff can inspect details, contact the owner and open relevant violation/incident actions.

Physical presence and security standing must remain distinct: a vehicle can be physically inside while its display standing is `Blocked / Alert`. The backend supports that distinction. Some release buttons still check a narrower text status and need correction.

### Gate records

- Entry, exit and refused attempts with timestamps/checkpoints/staff identity.
- Driver identity/relationship and relevant visitor-item checks.
- QR versus manual lookup method where recorded.
- Recorded event time versus later synchronization information for historical offline events.
- Detail views and related cases/evidence.
- Search/filter/report/export interfaces where implemented.

Some list/history/payment queries are bounded. A recent page length is not an authoritative all-time or daily total. Current mobile KPI calculations and some reports need server aggregate/paging improvements.

## 8. Dashboard and parking operations

The admin dashboard provides an overview of campus activity, current parking/security information, recent movements and operational attention areas. Charts/cards use the project's dashboard components, alongside links to detailed working views.

Parking capacity is configurable; zero represents no configured limit. The system supplies occupancy/capacity notices, including near-full/full warnings. A capacity warning should not be mistaken for an independently verified automatic barrier controller.

Overtime/overnight checks identify vehicles for staff attention around the configured curfew/thresholds. Staff can contact the owner, issue an appropriate violation or pursue the case process. The current case model does not rely on an automatic “three strikes” punishment system, even where older wording/element names remain.

Current UI gaps include repeated wide dashboard tables, historical denial counts that can appear as active alerts, and some incomplete totals/export behavior. These are documented findings, not features claimed to be fully polished.

## 9. Security cases, holds and one-time releases

The Cases view brings violations and security/overnight incidents into one working process while preserving their underlying records.

| Action | Purpose | Access/condition |
|---|---|---|
| Issue violation/report incident | Record a reason and apply relevant security standing | Authorized staff; current policy applies |
| Contact owner | Record method, result and note | Guard/admin |
| Await clearance | Record that the owner will attend to the issue | Guard/admin |
| Add note | Extend the case timeline | Guard/admin |
| Refer to police | Record referral reason/reference | Admin, with required prior contact attempt |
| Close case | Record an allowed outcome and written notes | Admin; sensitive dismissal may require another admin |
| View/export cases | Review status, type, dates, outcome and history | Scoped staff reads; export admin-only |

Closing one case must not automatically remove unrelated active holds. The older “Clear & Unblock” entry points are still present and need unification with the case workflow.

### One-time exit release

An administrator can grant a reasoned, time-limited release for a held vehicle physically inside. It permits one exit, is consumed as part of the transaction, and does not clear the hold or authorize another entry. Unused releases can be canceled. Server behavior is tested; some web CTA visibility and displayed expiry wording still need correction.

## 10. Payments, receipts and renewals

### Registration payments

- Registration fee calculation based on the defined vehicle/class policy.
- Administrator cashier flow for cash collection, tendered amount/change and payment records.
- Owner online checkout for eligible own unpaid registrations.
- Server-side payment-status confirmation; the browser does not independently declare a payment paid.
- Payment history and receipt information for administrators and scoped owners.
- Payment completion activates the appropriate registration/pass state under server rules.

### Renewal

- Renewal eligibility window and approaching-expiry notices.
- Administrator cash renewal, free eligible renewal and supported bulk renewal.
- Owner online renewal for eligible records.
- Updated validity/payment/pass state after successful completion.

PayMongo checkout/webhook code and development simulations exist. Automated tests use simulated provider responses; live merchant configuration, real payment delivery and callbacks have not been certified here. Cashier functionality belongs to administrator access, not a separately verified cashier user role.

## 11. Administration, audit and guard duty

### Staff and owner accounts

Administrators manage staff identities, role/checkpoint assignment, active status and temporary/reset passwords. Owner-account management/reset features support the separate owner portal. Account changes are checked by the backend, not only by hidden navigation controls.

### Admin Center

- Activity log: who acted, what record was affected, when and the reason/details.
- Approval queue: pending/approved/rejected sensitive changes; requester cannot approve their own request.
- Duty overview: current guard shifts and activity reports within selected dates.
- Settings: validated campus policy values, with changes written to the audit log.

Where only one active administrator exists, specified sensitive actions can be applied directly and logged. Adding another administrator activates the relevant second-admin approval process. The navigation badge still needs a clear distinction between all pending requests and work the current admin can decide.

### Mobile duty

Guards can start a shift, choose the permitted checkpoint and end it with a handover note. Duty/handover displays refresh after live revisions. Optional shift reads have their own failure semantics and need additional coherent-recovery tests.

## 12. Evidence, photos, OCR and notices

- Vehicle, driver and visitor photos support visual checks.
- Guards can capture/attach evidence to entries/exits, violations and incidents.
- Photo compression and supported data formats reduce upload size.
- Plate-reading/OCR helpers compare a detected plate with the pass where used; the evidence API stores the comparison result.
- Administrators can view evidence attached to a record.
- Configurable retention removes old photo payloads through maintenance while retaining the evidence record.
- Owner notices include movement, hold/case, payment/expiry/reminder information where the relevant flow generates it.
- Local SMTP capture tests cover message generation. Actual mailbox delivery depends on configured SMTP/hosting and was not verified with real recipients.

Historical gate-clip/CCTV components are simulation or placeholder assets unless real media is provided. They are not an integrated live CCTV/NVR system, and the removed demo dashboard tile should not be described as an active monitoring camera.

## 13. Owner portal

The owner portal is a web application, not a separate native owner mobile app.

| Main view | Available information/actions |
|---|---|
| My Pass | Select own vehicle; see pass/standing/drivers; enlarge QR; save image; eligible payment/renewal |
| Activity | Own movement history, denied attempts, notices and related context |
| Cases | Own unresolved/resolved cases, next steps and relevant progress |
| Account | Profile, own payment/receipt information and supported password/account actions |

An active hold notice is visible across relevant tabs. Authenticated scoped revision polling detects field-only edits even when record counts do not change. The enlarged QR closes when relevant pass standing changes; unrelated clock ticks should not close it. Browser rendering and all open-dialog combinations remain less verified than the scoped APIs.

## 14. Update transport, offline behavior and background work

### Automatic foreground updates

The current update path is:

`User action → authenticated API → database commit → changed scoped revision → next client poll → fresh reads → UI/cache update`.

- Polling target is approximately five seconds while signed in and foregrounded.
- The feed includes only permitted domain fingerprints and public current-user information.
- Owners receive fingerprints for their own related records; guards do not receive administrator-only staff/approval/payment domains.
- A minute-clock revision supports time-dependent rendering.
- Admin transport avoids overlapping polls, pauses hidden tabs, wakes on foreground/online and backs off errors.
- Mobile refreshes on resume and uses strict required reads before acknowledgement.
- Updates are automatic polling, not instant WebSocket/SSE push or guaranteed background delivery.
- Full-table hashing and broad refetching still need performance optimization at realistic scale.

### Offline boundaries

Cached records can remain visible during a connection failure. The signed current IN/OUT confirmation requires online server checks. Uncertain requests retain the original retry payload. Older historical-event and visitor queues exist independently and use client references to prevent duplicate saves. Refused events are retained for review rather than endlessly retried.

Queue authorship across different logins and late-event ordering require further specific validation. Mobile/owner failure backoff is not as complete as the admin transport. Device process suspension is not guaranteed to run timers or deliver updates.

### Maintenance

Staff-triggered, rate-limited maintenance creates expiry notices/hold reminders, closes very old open shifts and applies photo retention. It is designed to run on sign-in/periodic staff activity; it is not proof of a continuously running server cron service when no staff app is open.

Editable settings currently include parking capacity, movement emails, renewal window, expiry warning window, hold reminder interval, exit release duration and evidence retention. Visitor day-pass calendar validity is distinct from legacy mobile hour-based defaults.

## 15. Mobile front-end design and normal QR camera position

### Current UI structure

The active signed-in mobile route is `GuardShellScreen`, with Dashboard, Scan IN / OUT and Visitor navigation. The normal scanner is `QrScannerScreen(automaticMovement: true)`, which uses `CameraViewfinder`. Older entry/exit/dashboard classes remain in the repository; their presence does not mean they are the primary current route.

The scanner has a guard header, its own scanner app bar, a camera status strip, the square camera preview, hold-steady/status instructions and manual/flip controls. Flashlight/manual actions also appear in the scanner app bar. The scan and decision screens display different states intentionally.

The mobile theme defines navy `#1A3B8B`, dark navy `#0F265C`, gold `#F5B800`, crimson `#D92128` and green `#16A34A`, with neutral surfaces. Those definitions establish the palette; they are not a claim that every current component meets all visual/contrast/accessibility requirements.

### Is the normal camera centered?

**Horizontally: yes. Vertically: no in the current portrait scanning layout.** The camera image is centered/cropped inside its own square, but that square sits above the middle of the available viewfinder area.

The relevant layout in `camera_viewfinder.dart:225` is:

```text
Expanded
  SingleChildScrollView (16-pixel padding)
    Center
      Column (mainAxisAlignment.center)
        Camera square
        Status and controls
```

A vertical scroll view gives its child unbounded height. The column sizes around its content rather than filling the visible height, so its center alignment has no remaining vertical space to distribute. The scroll content starts near the top. The comment “Central Viewfinder Area” and a `Center` widget therefore do not prove vertical centering.

### Executed layout measurement

A targeted Flutter layout measurement executed the actual `CameraViewfinder` using its simulated camera texture, with guard-style headers and a 72-pixel bottom navigation allowance. These are logical pixels. It tests geometry, not camera hardware or an installed-phone screenshot.

| Viewport | Frame | Horizontal offset from viewfinder midpoint | Vertical offset from viewfinder midpoint |
|---|---|---:|---:|
| 390 × 844 portrait | 220 × 220 | 0 | −160 pixels (above middle) |
| 360 × 800 portrait | 220 × 220 | 0 | −144 pixels (above middle) |
| 844 × 390 landscape | 170 × 170 | 0 | +42 pixels; scroll content extends below the available area |

Evidence: `artifacts/scanner-layout-audit.log`; reproducible test: `mobile-app/test/scanner_layout_audit_test.dart`. The measurement check passed because it accurately records geometry without layout exceptions; **that is not a PASS for vertical centering**. Actual safe-area/navigation sizes on a phone may change the exact offsets, but the source layout cause remains.

### Recommended correction — not applied by this report

1. Decide that the idle camera square, rather than the whole camera-plus-controls group, is the element to center.
2. Use the remaining viewport constraints after headers/navigation, not the full device height.
3. Center the frame in that region and place status/help/actions below it or in a separate lower panel.
4. Use a constrained minimum-height scroll layout, or a bounded center/stack layout with a short-screen scrolling fallback. Do not rely on `mainAxisAlignment.center` inside an unbounded scroll child.
5. Size the frame from available width/height so landscape and larger text remain usable. Preserve manual input, flashlight/flip, steady-hold and camera error handling.
6. Reduce duplicate headers/actions if they crowd the scanning area; keep clear accessible labels.
7. Verify frame center coordinates, short-screen scrolling and large-text layout, then test a real phone/camera. This report does not change the scanner position.

## 16. Verification evidence and remaining limits

The most recent update verification is documented in [mobile synchronization update](mobile-realtime-update-2026-10-09.md):

| Evidence | Actual result / scope |
|---|---|
| Flutter regression | 177 passed; the real-PHP check is skipped without its isolated fixture variables and passed separately |
| Real mobile service/worker ↔ PHP | Passed automatic vehicle-cache update and session revocation, using actual HTTP against disposable PHP/SQLite |
| PHP regression | 678 API assertions passed |
| Signed movement/concurrency | 85 checks passed, including all guard combinations, retry, stale rejection and rollback |
| Scoped revision/session API | 19 checks passed |
| Web transport units | 12 controlled-timer/DOM checks passed |
| Two independent real-API transport clients | 3 checks passed, using simulated renderers |
| Analyzer / debug build | Analyzer clean; Android debug APK built |
| This report's camera geometry check | Executed; confirms portrait frame is high rather than vertically centered |

These counts describe different test types and must not be presented as one fully executed phone/browser end-to-end suite.

Not certified here: actual physical camera/OCR, deployed MySQL races/deadlocks, real multi-phone UI delivery, browser E2E, production-scale load, real provider payments/email delivery and Android process suspension. Existing source-level issues also remain in web gate parity, case-action duplication, complete KPI/export queries, release CTA visibility, approval badge semantics, optional shift reads and offline queue identity.

Older README text may mention strikes, demo camera capabilities or less flexible guard behavior. Current active routes and server rules take precedence over those older descriptions. The [historical baseline audit](realtime-plan-and-system-validation-2026-10-09.md) retains its original failures; subsequent visitor-card/analyzer fixes are recorded in the newer update document.

## 17. Overall assessment

The system has a shared, substantially tested gate/registration/case backend and implemented admin, owner and guard workflows. The new update transport is connected and tested at the service/API level. The mobile visitor-card refresh and earlier analyzer/layout failures were corrected in the published branch.

The normal QR camera **has not been vertically centered by those changes**. Its current portrait layout confirms the concern raised in this request. UI cleanup, complete reporting metrics and real-runtime verification remain necessary before describing the entire product as finished or fully deployment-tested.

No application implementation was changed while creating this feature report. The report and geometry test are included with the current project on branch `feature/system-features-scanner-audit-20261009`, created for the requested GitHub publication.
