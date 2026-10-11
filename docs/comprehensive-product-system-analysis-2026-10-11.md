# SecurePark — Comprehensive Product and System Analysis

**Assessment date:** October 11, 2026, Asia/Manila  
**Scope:** NCST campus vehicle access and custody product; administrator/guard web portal, owner web portal, Flutter guard application, shared PHP backend, database, operational documentation, and existing verification evidence.  
**Phase:** Analysis and reporting only. No application implementation changes were made for this report. Earlier changes already present in the working tree were assessed as the current baseline.

## 1. Executive evaluation

**SecurePark solves a real and coherent problem, but its current implementation is not sufficiently consistent to be considered ready for unrestricted campus operations.**

Its strongest product idea is the connection between registration, authorized drivers, gate decisions, physical presence, and security case resolution. An owner portal and a focused guard mobile app are appropriate complements to an administrative web portal. A shared PHP application and relational database are proportionate to a campus system; a platform rewrite or microservice architecture is not warranted by this assessment.

The central weakness is that the system does not consistently distinguish **permission to move**, **recorded physical location**, **pass validity**, and **case status**. Older and newer workflows can produce different outcomes. This matters more than cosmetic consistency: guards must be able to trust who is inside, what they may approve, and which action actually happened.

New isolated runtime checks during this assessment confirmed:

1. Closing a violation after a separate security incident changes an entered vehicle to `Outside` without any exit log. Another incident remains Held, but the response says the vehicle can enter and leave again.
2. The legacy visitor checkout endpoint accepts checkout before entry, without declared-item verification, and creates no gate movement log. It also accepts checkout for a revoked visitor whom the normal movement workflow refuses.
3. The backend accepts a password with leading/trailing spaces; mobile login trims it and therefore submits a different password.

These findings remain unfixed because this phase is expressly limited to analysis. Earlier broad passing tests demonstrate substantial functionality, but they did not cover these combinations. A passing suite is evidence about its scenarios, not evidence that the product has no bugs.

### Readiness by area

| Area | Assessment |
|---|---|
| Purpose and core concept | Coherent and useful for campus gate security and custody records |
| Platform division | Appropriate overall; guard rules differ across web and mobile |
| Routine registration and online movement | Substantially implemented and tested in isolated environments |
| Exceptions, holds, visitor checkout, and recovery | Material inconsistencies remain |
| Operational policy | Partially established; departure holds, VIP privileges, visitor reentry and outage authority need confirmation |
| Reporting and monitoring | Useful views, but some operational totals and historical labels are inaccurate |
| Architecture | Suitable basic structure; state duplication, legacy write paths and polling cost need correction |
| Native camera/OCR and production integrations | Not certified by the available evidence |
| Overall | Suitable for continued supervised evaluation; unrestricted operational reliance is premature |

## 2. Evidence, method and boundaries

This assessment examined the active entry points, feature modules, backend business helpers and endpoints, schema/migrations, current documentation, older documentation, and the previous runtime audit. It is a system-level assessment of the major product domains, not a claim that every line, every screen state, or every possible input combination was executed.

Evidence labels used below:

- **Runtime-confirmed defect:** observed against real PHP in a disposable SQLite fixture during this assessment.
- **Source-confirmed defect/inconsistency:** directly supported by the active source; full device/deployment reproduction may still be outstanding.
- **Source-identified risk:** an unsafe interleaving or failure path exists; production frequency/impact is unmeasured.
- **Design recommendation:** a contextual product judgment, not proof of an implementation bug.
- **Unresolved requirement:** campus policy or operational intent is not established by the available evidence.

The new results are preserved in [analysis probe results](../artifacts/product-analysis-probes-2026-10-11.json). They used disposable local databases and local PHP processes. They did not access production data, deploy changes, or modify application code. The password probe reproduces the backend contract and the effect of mobile's source-confirmed trimming; it does not claim an installed-phone login test.

### Previously executed verification, carried forward explicitly

The [October 11 technical audit](deep-system-audit-2026-10-11.md) records 678 backend assertions, PHP/JavaScript syntax checks, clean Flutter analysis, 189 Flutter tests with two environment-gated skips, an Android debug build, real Chrome/PHP error-recovery tests, Dart/PHP synchronization checks, and a visitor/mobile-transport/web-audit roundtrip. Those broad suites were executed earlier; they were **not rerun as part of this product-analysis phase**.

The roundtrip establishes API/service integration and browser visibility for the tested paths. It does not establish native mobile camera behavior. Physical Android/iOS camera/OCR, actual MySQL concurrency, live payment callbacks, real mailbox delivery, host performance and phone process suspension remain unverified.

### Documentation authority

The October 9 feature inventory is useful but still requires comparison with source. The root README contains both current movement descriptions and historical terminology. The owner README describes a retired three-strike meter. `USER_FLOW_LOGIC_AUDIT_REPORT.md` contains older assumptions. `system_functional_behavior_documentation.md` describes an unrelated GNCP enrollment/LMS product, including registrar, tuition and class workflows.

None of those historical or unrelated descriptions should be adopted as campus requirements. Source shows what the software does; it does not by itself authorize the business rule.

## 3. System overview and intended purpose

### 3.1 Problem addressed

SecurePark aims to help NCST security staff answer:

- Is this vehicle registered, paid where applicable, and using a current campus pass?
- Is this person an authorized driver of that vehicle?
- Is the vehicle recorded inside or outside campus?
- Who approved its passage, at which checkpoint, and when?
- Are there unresolved security matters affecting movement?
- Which visitors and declared items entered, and have they left?

This is principally an **access verification and vehicle custody record system**. It also includes registration administration, fee collection, owner communication and exception management. The source does not establish a parking-space reservation service, comprehensive traffic-management platform, or integrated physical barrier controller.

### 3.2 Intended users

| User | Main job | Appropriate product access |
|---|---|---|
| Security administrator | Register vehicles, manage accounts and rules, resolve cases, authorize exceptions, review records | Administrative web portal |
| Gate guard | Verify passes and people, inspect visitor items, confirm physical passage, capture evidence, report exceptions | Mobile terminal and operational web views |
| Student/employee vehicle owner | Present pass, understand eligibility, pay/renew when available, review own activity and cases | Owner web portal |
| Visitor | Supply visit details and present a temporary pass | Guard-assisted issuance; no separate visitor account is inherently necessary |

Cashier functionality currently belongs to administrators. A dedicated cashier role is not an established requirement. Authorized drivers are associated with a vehicle, but do not automatically receive their own owner account.

### 3.3 Confirmed gate operating rule from the user

**Normal days:** the two physical gates have dedicated entry and exit functions.  
**School events:** entry may be allowed at both gates; guards must be able to support this arrangement.

The user's clarification establishes flexible capability with a normal operating pattern. It does not establish that both directions should always be available at every checkpoint. Which gate handles event exits, who activates the exception, and outage admission authority remain unspecified.

## 4. Overall concept evaluation

### What fits the purpose

Signed vehicle passes, authorized-driver checks, visitor passes, physical-presence monitoring, named guard attribution and durable movement history directly support the purpose. Cases, owner contact and one-time exit release are reasonable supporting features if campus policy authorizes the restrictions they implement. Payment/renewal is appropriate if campus registration genuinely carries the coded fees and validity periods.

The owner portal reduces dependence on the security office for routine pass display and status explanation. Mobile supports the gate's physical work: camera, OCR assistance and photo evidence. Administrative tasks benefit from desktop tables and longer review workflows. These platforms should share rules and data without sharing every screen.

### Where the concept needs boundaries

The current product combines access control, financial activation, discipline, custody and police-referral recording. That breadth can be justified, but each responsibility needs explicit rules. Payment failure is not necessarily a reason to prevent departure. An ordinary parking violation is not automatically a custody dispute. Recording a police referral does not itself prove vehicle removal. The software currently handles some distinctions correctly, such as allowing an unpaid vehicle already inside to exit, but general violation holds are much broader.

The right next step is to clarify and simplify those boundaries, not add new modules. There is no demonstrated need for reservations, an owner native app, automatic license-plate recognition hardware, complex event scheduling, or a separate approval service.

## 5. Feature-by-feature assessment

| Feature | Why it exists / fit | Current assessment | Recommendation |
|---|---|---|---|
| Staff login and temporary passwords | Establish accountable operators | Appropriate; enforcement improved in earlier work. Mobile password whitespace mismatch remains | Preserve server authority and exact password semantics; explicit errors for expired/changed sessions |
| Vehicle registration | Establish eligibility and ownership information | Core feature; creates owner login, defaults owner as driver, tracks class/fee | Make account-creation failure and unpaid next steps unmistakable; confirm campus identity-check procedure |
| One active vehicle per class | Manage campus allocation | One four-wheel, two/three-wheel and bicycle class per owner, with reasoned admin override | Keep only if it reflects campus policy; describe the actual per-class rule rather than implying one vehicle overall |
| Authorized drivers | Prevent unauthorized vehicle release | Core to custody concept; human selection validates a database relationship | Clearly require visual/person verification. A dropdown selection or OCR result is not proof of identity |
| Signed QR and reissue | Validate pass origin and revoke older copies | Appropriate; signature plus current backend record/pass ID | Explain replacement invalidates saved/printed older QR. Static QR can be copied; human vehicle/driver checks remain essential |
| Automatic mobile IN/OUT | Reduce direction-selection errors | Good preview/confirm/retry design; direction inferred from recorded presence | Add checkpoint operating rules for normal/event use and a supervised correction path for missing movements |
| Web Gate Monitor | Support fixed terminal/scanner workflows | Useful; explicit direction and legacy guard restrictions differ from mobile | Share direction permissions and movement rules across clients; avoid username-based operational policy |
| Visitor issuance | Admit nonregistered vehicles temporarily | Appropriate; today for guards, future dates for admins, optional photo/items | Clearly separate pass issuance from actual entry; clarify single-visit versus repeated-entry policy |
| Visitor declared items | Support equipment custody checks | Useful for events/deliveries; Boolean confirms the entire list | Keep optional where irrelevant; define discrepancy handling rather than forcing a misleading “all checked” confirmation |
| Visitor checkout | Close physical visit and prevent reuse | Main scanner logs/checks it; legacy endpoint bypasses those protections | Use one validated movement operation; distinguish completed visit from administrative revocation |
| On Campus Now | Show physical presence and attention needs | Core operational view; shared helper reconstructs some blocked states | Preserve presence independently of security standing and use complete aggregates |
| Capacity warnings | Inform guards during crowding/events | Configurable warning, zero unlimited; no proven refusal/barrier behavior | State that capacity is advisory unless campus requires a hard rule; use accurate registered-plus-visitor occupancy |
| Overtime/overnight attention | Identify vehicles needing follow-up | Useful; thresholds and curfew, VIP exclusion; maintenance tied to staff activity | Treat as review prompts, with legitimate overnight-use policy and escalation criteria |
| Violations/security cases | Coordinate investigation and clearance | Useful central Cases view; overlapping older resolution controls and state defects | One case process with clearly computed remaining holds and physically accurate status |
| One-time exit release | Permit departure while preserving investigation | Good exception concept; limited time and one use | Fix discoverability and duration text; establish emergency availability and visitor treatment |
| VIP class | Implement approved exceptions | Bundles driver, fee, violation and overtime exemptions | Confirm necessity and narrow privileges to justified exceptions; title alone should not imply every exemption |
| Second-admin approvals | Reduce unilateral sensitive changes | Requester cannot self-approve; single-admin environment can act directly | Explain when dual control applies and display actionable requests; confirm clearance cannot substitute for reviewed dismissal |
| Payments/receipts | Activate paid campus registration | Cash/admin and owner online paths; duplicate payment recorded with refund note | Resolve concurrency and define refund follow-up; validate live provider and campus receipt expectations |
| Annual renewal/replacement | Preserve registration over time and vehicle changes | Calendar-year renewal, pass rotation, retirement and fee credit | Confirm calendar-year versus school-year policy and explain lost/changed QR and credit balances |
| Owner activity/cases/notices | Tell owner what happened and what to do | Appropriate scoped portal; case guidance assumes case closure restores access | Derive next steps from all eligibility blockers, not one closed case |
| Evidence/photo/OCR | Help guards compare actual vehicle/person with records | Appropriate assistance; native recognition not certified | Human-review OCR, honest hardware failure states, explicit upload success and retention behavior |
| Guard shifts/handover | Preserve operational context across staff changes | Useful if handovers are actually used; gate attribution sources can disagree | Tie duty checkpoint and movement checkpoint together; determine whether duty start is required |
| Audit/export/dashboard | Accountability and operational awareness | Movement logs are strong on main path; totals, labels, limits and admin audit durability need work | Complete server-side totals/exports, historical wording and mandatory audit records |
| Foreground live updates | Keep open clients aligned | Approximately five-second authenticated polling, with stale/retry handling | Describe latency honestly and replace full-table fingerprints as history grows |
| Offline caching/queues | Continue visibility and retain certain historical actions | Online confirmation and legacy offline events are distinct; durability/origin risks remain | Define manual outage procedure, durable queues and rejected-event reconciliation |
| Branded launch animation | Provide recognizable opening experience | Custom assets/transition implemented; Android build verified previously | Retain restrained animation; it must not imply server readiness or slow urgent restart unnecessarily |
| CCTV/clip placeholders and print action | Presentation/demo support | UI claims media attachment/printing without implementing those operations | Remove misleading operational claims; add actual integrations only if needed |

## 6. Business logic and complete journeys

### 6.1 Staff onboarding and duty

**Current:** administrator creates staff with role/checkpoint and temporary password. Staff changes password and uses operational routes. Mobile can start/end a shift and see handover notes. Movement checkpoint comes from account assignment, while the shift endpoint accepts a gate name.

**Expected:** staff identity, current duty location, allowed directions and movement attribution agree. A guard restarting the app should recover a known duty/session state with honest connectivity information.

**Assessment:** reasonable onboarding, but checkpoint and shift can become parallel sources of truth. No demonstrated requirement makes shifts an attendance system or mandatory movement prerequisite. Confirm that requirement before imposing a new guard step.

### 6.2 Owner registration, account and activation

**Current:** an admin registers a vehicle, authorized drivers and owner ID. Class quotas can be overridden with a reason. A paid category starts unpaid and has no usable QR until cash/online settlement. A free/waived category can activate directly. Owner account creation follows vehicle commit and may fail independently; recovery exists through the dossier.

**Expected:** the administrator receives a clear outcome for vehicle creation, pass availability and account creation separately, then can give the owner their credentials and next step. Issuing a receipt or pass must not imply an account was created when it was not.

**Assessment:** deferred account provisioning is defensible; representing the whole journey as one undifferentiated success is not. No evidence establishes independent verification against an NCST identity register. This may be an intentional manual office procedure, not a missing integration requirement.

### 6.3 Routine registered-vehicle entry and exit

**Current mobile:** scan/manual lookup → side-effect-free preview → server suggests IN/OUT from shared presence → guard checks vehicle/driver → confirm ticket → transaction rechecks and records passage. Tickets bind operator, checkpoint, pass and observed movement revision. A lost response is retried using the same ticket, preventing a reversal caused by double submission.

**Expected:** passage direction matches both physical gate intent and recorded state. A changed pass/hold/driver record is reevaluated before approval. Recording occurs when the guard confirms the actual passage, not merely when the camera recognizes a QR.

**Assessment:** the confirmation design is a strong foundation. It handles retry and concurrent confirmation more carefully than a local status toggle. However, a physically entering vehicle incorrectly recorded inside will be offered OUT. The confirmation screen is mitigation, but it is not an operational correction process. Gate mode and anomaly handling must prevent staff from “fixing” state by approving a movement that did not happen.

### 6.4 Event entry at both gates

**Current:** mobile permits both guards to confirm both directions at their assigned checkpoints. Web hides ingress for `guard2` or assignments containing `2`/`exit`. The exposed settings do not define a shared normal/event direction mode.

**Expected from the user's rule:** normal gate assignments remain clear; authorized event operation permits ingress at the usual exit gate; both platforms apply the same temporary allowance. Checkpoint identity remains stable even when direction changes.

**Assessment:** neither permanently flexible mobile nor fixed username-based web restrictions fully expresses the normal/event distinction. A small administrator-controlled set of checkpoint direction permissions, with a clear event override and audit reason, is sufficient. A large event-management module is unnecessary. Event exit routing still needs confirmation.

### 6.5 Visitor issuance, entry, items and checkout

**Current:** guard/admin creates a calendar-date pass containing contact, destination/purpose, optional items and photo. Creation does not establish physical entry. The normal movement path verifies declared items at entry and exit. First exit records `exit_time` and marks the pass Revoked, preventing reuse. An already-entered visitor may leave after the validity date if no security hold applies.

**Expected:** issuance, admission, departure, expiry and cancellation are recognizable distinct states. Item discrepancy should have an honest reporting option. A legitimate completed visit should not be presented like a canceled or suspicious pass.

**Assessment:** sensible ordinary visit flow, but “all day” can imply repeated entry while implementation is single visit. The legacy direct checkout endpoint contradicts the main movement rules. Administrative revocation while inside opens a hold; comments say the visitor may still leave, but normal verification refuses it. A visitor-specific authorized escort/release rule is unresolved.

### 6.6 Denial, incident, violation and clearance

**Current:** guards can deny passage/report incidents or issue a registered-vehicle violation. Violations suspend registration, open linked incidents and block both directions. Cases combine violation and standalone incident timelines. Admin closes with outcome/notes; dismissal can require a second admin. Separate “Clear & Unblock” interfaces remain. Web denial creates log and incident in two requests.

**Expected:** refusal, investigation and proven violation have explicit meanings. An unresolved case must not disappear merely because another case closes. Clearing a case must not imply physical departure or removal of unrelated payment/expiry restrictions. Required denial/case records should agree even if the connection fails halfway.

**Assessment:** a unified Case view is appropriate. The underlying transitions and overlapping action paths need consolidation. Police referral and confirmed removal are separate real-world facts, although one close outcome combines them. A generic parking violation should not automatically be treated as authority to retain a vehicle unless campus policy expressly defines that rule.

### 6.7 Payment, renewal and replacement

**Current:** settlement records payment, activates registration and rotates pass identity. Renewals extend to December 31 of the target year. Replacement retires the old vehicle, preserves history and applies eligible credit. Concurrent settlement remains a source-identified risk. A late duplicate payment is recorded Paid with a refund note.

**Expected:** one financial outcome per charge, one corresponding activation, clear outstanding balance/receipt, invalidated older pass, and a responsible person who handles a duplicate refund. Payment success and case clearance remain independent eligibility decisions.

**Assessment:** reasonable registration support if the campus uses the coded fee/calendar rules. A refund note is detection, not refund completion. Do not expand into a general accounting system; establish a small manual reconciliation procedure if that meets campus needs.

### 6.8 Outages, uncertain writes and return to service

**Current:** cached records can be viewed, automatic signed movement confirmation requires online server checks, and older visitor/historical-event queues remain. Retrying an uncertain online confirmation preserves its ticket. Queue events older than the configured limit can be rejected; rejected records lack a complete review UI.

**Expected:** guards know whether they are viewing stale information, confirming online, or documenting a physical movement under an approved manual outage procedure. An event is not described as saved durably until storage succeeds. Reconnection requires review of discrepancies, not silent assumption that all terminals agree.

**Assessment:** online-only authoritative confirmation is defensible for holds/pass revocation. It does not itself answer how the gate operates when connectivity fails. The user's answer clarified gate direction but did not define outage admission authority. Offline issuance on one phone is not proof another terminal can validate that pass immediately.

## 7. Major confirmed findings

Priority meanings: **P1** before operational reliance; **P2** before broad rollout or as the next stabilization work; **P3** polish/maintainability after integrity issues. Severity reflects impact on this product, not a universal security score.

### F01 — Clearing a violation can erase recorded presence and claim false clearance

**P1 · Runtime-confirmed defect.**

- **Current:** enter vehicle → create independent security incident → issue violation → close that violation. The fixture returned `Outside`, `is_banned = 0`, `registration_status = Active`; one Held incident remained and zero exit logs existed. Response: “Case closed. PRD100 can enter and leave campus again.”
- **Problem:** the vehicle is physically recorded as having entered, yet disappears from the simple presence state without departure. The remaining incident may still block backend verification, so this is not proof every gate check bypasses the hold. It is proof that custody state and clearance messaging are inconsistent.
- **Expected:** closing one case preserves physical location, recomputes all remaining restrictions, and reports the actual standing.
- **Recommend:** separate presence from standing; centralize effective eligibility and remaining-hold evaluation; preserve passage-derived location; add the mixed incident/violation scenario to regression coverage.
- **Evidence:** `backend/lib/violations.php:130` (`liftHold`), `:139` (`resolveViolation`), `backend/api/incidents.php:140`, `backend/api/cases.php:182`, analysis probe results.

### F02 — Legacy visitor checkout bypasses movement integrity

**P1 · Runtime-confirmed defect.**

- **Current:** `POST visitors.php?action=exit` accepted an unused pass with declared equipment: entry remained null, exit became nonnull, status became Revoked and gate-log count remained zero. It also accepted a revoked visitor checkout refused by normal verification. The endpoint is reachable with staff/scanner authentication; it is not an unauthenticated bypass claim.
- **Problem:** visitor presence can change without entry, item inspection, named movement audit or the normal hold checks. Normal scanner correctness does not protect an alternative writer.
- **Expected:** every physical checkout follows the same eligibility, item, prior-entry, idempotency and audit rules, including appropriately documented emergency exceptions.
- **Recommend:** route checkout through a single movement service or retire the endpoint after checking legacy callers; do not silently break old queued events. Preserve original exit time on retry and return the saved result.
- **Evidence:** `backend/api/visitors.php:38`, `:302`, `mobile-app/lib/services/api_service.dart:958`, `mobile-app/lib/repositories/visitor_repository.dart:188`, analysis probe results. The repository helper remains present; this report does not claim it is the active automatic scanner route.

### F03 — Gate direction rules do not express the confirmed normal/event workflow

**P1 · Source-confirmed requirement mismatch.**

- **Current:** web restrictions are inferred from guard username/checkpoint text; mobile suggests movements from vehicle state and supports both directions. No shared normal/event permission exists in exposed policy settings.
- **Problem:** a guard at the usual exit gate may use mobile for event ingress but cannot perform the equivalent web action. Mobile also does not represent the ordinary direction restriction as an explicit shared rule.
- **Expected:** checkpoint direction permissions reflect normal operations and an authorized event exception consistently.
- **Recommend:** configure checkpoint identity and allowed directions independently of usernames, expose the current mode clearly, and validate it server-side for both clients. Confirm event exit routing before implementation.
- **Evidence:** user clarification; `web-app-admin/js/gate.js:621`, `backend/lib/movements.php:20`, `backend/lib/settings.php:8`.

### F04 — Printed/media success messages describe operations that did not occur

**P2 · Source-confirmed defects.**

- **Current:** “Print Physical Decal / Ticket” displays a snackbar saying the receipt was shared/sent to the campus print queue. Its handler does not print or enqueue. Web movement success says “5 s CCTV clip attached” irrespective of a real recording.
- **Problem:** a guard can believe a required ticket or evidence exists when it does not. Simulated assets are particularly misleading in a custody/audit product.
- **Expected:** only actual printing, sharing or recording yields that success claim; unavailable media is explicitly unavailable.
- **Recommend:** remove or honestly relabel these controls/messages. Implement real printing or media capture only if campus operations require it.
- **Evidence:** `mobile-app/lib/features/visitor/screens/visitor_pass_confirmation_screen.dart:711`, `web-app-admin/js/gate.js:455`, `web-app-admin/js/cctvclip.js`, asset README.

### F05 — Mobile dashboard labels are not supported by their calculations

**P2 · Source-confirmed defects.**

- **Current:** inside/blocked/entry metrics derive from recent audit records, normally the last 100. “Entries today” uses action text containing entry, allowing denials and older entries; it lacks a Manila-day filter.
- **Problem:** historical sample activity is presented as current occupancy or today's totals. Event staffing/capacity decisions may be based on incorrect numbers.
- **Expected:** server aggregates cover all currently inside vehicles/visitors and exact approved movements/denials within the named date range.
- **Recommend:** use authoritative aggregates, keep the recent feed separate, and mark stale/unavailable totals visibly.
- **Evidence:** `mobile-app/lib/features/guard/screens/guard_shell_screen.dart:164`, `:175`, `:176`; `backend/api/logs.php:33`.

### F06 — “Cleared” messages are broader than actual eligibility

**P2 · Source-confirmed inconsistency; runtime-confirmed example in F01.**

- **Current:** case closure or older “Clear & Unblock” messaging says the vehicle can pass. Case closure does not necessarily repair expired/unpaid/retired registration or another hold. Standalone incident closure sets the local `$lifted` response flag true without an aggregate eligibility result.
- **Problem:** owners/guards receive permission language for an action that only resolves one matter.
- **Expected:** “This case is closed” plus actual remaining blockers and next step.
- **Recommend:** return effective entry/exit eligibility and active-case summary from one backend rule; render that result in both portals.
- **Evidence:** `backend/api/cases.php:173`, `:182`, `backend/lib/cases.php:170`, `web-app-admin/js/app.js:2091`.

### F07 — One-time release controls miss eligible holds and misstate duration

**P2 · Source-confirmed defects.**

- **Current:** some web buttons require `isBanned && status === 'Inside Campus'`. The backend also recognizes other active security holds and reconstructs inside status for `Blocked / Alert`. The release dialog always says 30 minutes although policy allows other durations.
- **Problem:** an admin can fail to find a permitted emergency action or promise the wrong validity window.
- **Expected:** eligibility comes from the backend's held/inside result; expiry text uses the configured/saved value.
- **Recommend:** expose release eligibility and exact expiry consistently in case/vehicle views.
- **Evidence:** `web-app-admin/js/cases.js:173`, `web-app-admin/js/app.js:2970`, `web-app-admin/js/ops.js:121`, `backend/lib/releases.php:23`, `backend/lib/campus.php:48`.

### F08 — Successful completion and revocation share the same visitor status

**P2 · Source-confirmed semantic inconsistency; reuse policy unresolved.**

- **Current:** ordinary completed exits become Revoked; schema/API also recognize Used. “Day pass” is valid on a date but cannot be reused after exit.
- **Problem:** staff cannot infer whether a record completed normally or was canceled from status alone. Visitor/event expectations may differ from single-visit behavior.
- **Expected:** distinct completed, revoked, expired and physically inside states; explicit single-visit or reentry policy.
- **Recommend:** choose the campus policy first, then align status, UI and history. Reentry support should not be added without that requirement.
- **Evidence:** `backend/lib/movements.php:165`, `backend/api/logs.php:348`, `backend/api/verify.php:225`, visitor schema.

### F09 — Revoked-visitor departure policy contradicts implementation

**P1 · Source-confirmed contradiction with runtime evidence; intended rule unresolved.**

- **Current:** visitor API comments say an already-inside revoked visitor may leave. Revocation opens a Held incident; main verification returns `accepted: false`, result REVOKED. Legacy checkout returns 200 for that same record.
- **Problem:** neither staff nor callers can predict which supported workflow governs an escorted departure. Registered vehicles have one-time releases; the reviewed visitor flow lacks an equivalent coherent rule.
- **Expected:** one documented rule for revoked visitor custody and escorted departure, applied by all endpoints.
- **Recommend:** decide whether revocation blocks entry only or also departure, and how an authorized escort is recorded. Resolve the contradiction without using legacy bypass as an exception mechanism.
- **Evidence:** `backend/api/visitors.php:16`, `:282`, `backend/api/verify.php:194`, `:320`; analysis probe results.

### F10 — Mobile login changes a valid password

**P2 · Source-confirmed defect with runtime contract reproduction.**

- **Current:** change-password accepts ` SpacePassword2026 `; exact login returns 200; the mobile-trimmed value returns 401.
- **Problem:** a legitimate credential created elsewhere can fail in mobile, causing avoidable gate access/support problems.
- **Expected:** clients submit the exact password; username normalization is separate.
- **Recommend:** remove password trimming from live authentication and test cross-platform creation/login semantics.
- **Evidence:** `mobile-app/lib/repositories/auth_repository.dart:36`, `:57`, `backend/api/auth.php:33`, `:93`; analysis probe results.

### F11 — Historical logs and capped searches can appear current or complete

**P2 · Source-confirmed defects/limitations.**

- **Current:** web audit detail labels an entry snapshot “Currently on campus,” even after a later exit. Case search fetches at most 1,000 rows from each source before further filtering/pagination and computes totals from that collection; CSV uses the same search. Other dashboards derive alerts from historical denials.
- **Problem:** historical state is mistaken for current state; matching older cases can be omitted while a total/export appears complete. The source comment that the cap exceeds campus needs is not workload evidence.
- **Expected:** event-state labels say “State after this event”; current status is separately queried. Totals and exports cover the requested range or disclose a limit.
- **Recommend:** correct historical labels; use database filtering/counting/pagination; expose export truncation until complete queries exist.
- **Evidence:** `web-app-admin/js/app.js:2392`, `:426`, `backend/lib/cases.php:196`, `backend/api/cases.php:65`.

### F12 — Conflicting documentation creates conflicting product rules

**P2 · Source-confirmed governance defect.**

- **Current:** unrelated enrollment documentation and retired strike/demo/guard-rule descriptions coexist with current feature reports.
- **Problem:** developers, testers and campus reviewers may “fix” the product to incompatible specifications. It also makes acceptance criteria unreliable.
- **Expected:** one current product policy/workflow description, with historical documents labeled and unrelated material excluded from the specification.
- **Recommend:** create a concise authoritative role/rule/state matrix approved by campus stakeholders; retain old audits as dated evidence. Do not delete historical records blindly.
- **Evidence:** root README, owner README, `system_functional_behavior_documentation.md`, `USER_FLOW_LOGIC_AUDIT_REPORT.md`, October 9 feature report.

## 8. Architectural and integration risks carried forward

These are still open in the current source. Details and earlier verification limits are in the [technical audit](deep-system-audit-2026-10-11.md).

| ID / priority / evidence | Current behavior and consequence | Expected behavior and recommendation |
|---|---|---|
| R01 · P1 · Source-identified risk | Mobile cache/queue keys are global while server URL is changeable. Events/cached data from server A can be used against B; in-flight requests can finish after a switch | Namespace durable storage and requests by backend identity; preserve/migrate pending events; reject stale-generation updates |
| R02 · P1 · Source-confirmed storage failure behavior | Preference persistence can fall back to memory and ignore write failure; rejected list is capped at 100 | Durable transactional local queue; report storage failure before claiming saved; review/export unresolved rejected events |
| R03 · P1 · Source-identified concurrency risk | Visitor plate/date duplicate check precedes transaction; only pass code has unique constraint | Serialize normalized plate/date issuance or enforce active-pass uniqueness, including offline sync; test on MySQL |
| R04 · P1 · Source-identified concurrency risk | Payment settlement reads payment/vehicle without explicit row locks; competing settlement can observe the same pending state | Lock in consistent order and recompute financial/pass outcome under lock; test simultaneous cash/provider/retry paths |
| R05 · P2 · Source-confirmed failure behavior | Admin audit insertion errors are caught/logged; sensitive business action can commit without its required audit row | For mandatory accountability, persist audit/outbox in the business transaction; notification delivery can follow separately |
| R06 · P2 · Source-confirmed implementation cost | Five-second revisions select/hash full relevant tables, including large inline values | Durable domain revisions updated with mutations, metadata feeds and on-demand photo loading; measure realistic history/load |
| R07 · P2 · Source-confirmed split operation | Web denial saves movement log, then incident in another HTTP call; failure can leave only one saved | One server operation for the intended denial/case outcome, with idempotent reference and clear retry result |
| R08 · P2 · Source-identified coupling | Global `lastResponseData`, errors and last-created values can be overwritten by concurrent service operations | Typed per-call results and explicit repository injection; don't rely on global response slots |
| R09 · P2 · Source-confirmed test limitation | Test-environment auth automatically uses mocks; native camera is not exercised by widgets/services | Explicitly inject mocks; maintain real API tests and add installed-device operational acceptance |

R01 is a traced cross-backend scenario, not a claim that two production databases were contaminated. R03/R04 were not reproduced under production MySQL isolation. Distinguishing those limits matters.

### 8.1 Architecture that should be retained

The canonical `backend/` plus generated admin deployment mirror is understandable for this hosting arrangement, provided synchronization remains a release gate. Role-scoped backend checks, owner isolation, signed passes and transactionally recorded main movements are appropriate. Serving web/mobile against the same API/database is essential; separate SQLite files do not constitute a shared system.

The modular PHP monolith is a reasonable design for one campus. Improvements should be concentrated in shared domain services: eligibility, physical movement, visitor lifecycle, case resolution, payment settlement and mandatory audit. Microservices, event-streaming infrastructure and a framework replacement would add complexity without resolving the underlying rules.

### 8.2 State and database consistency

Presence is represented partly by `vehicles.status`, partly by movement history and `last_entry_time`; security standing uses status, ban flags, registration status and incidents/violations. `vehicleRecordedInside` already compensates for overloaded Blocked/Alert state. F01 demonstrates the limits of that compensation.

Prefer explicit independent concepts, even if introduced incrementally:

```text
Physical presence: Outside / Inside / Needs reconciliation
Registration: Active / Inactive / Retired
Payment: Unpaid / Paid / Waived
Pass validity: Current / Expired / Replaced / Revoked
Security standing: Derived from unresolved relevant cases
Movement permission: Direction + above rules + any valid exception
```

“Needs reconciliation” is a proposed handling state for contradictory evidence, not a currently implemented value. A case resolution changes standing, and a recorded physical movement changes presence. An administrative location correction must be a reasoned, auditable correction rather than a fabricated passage.

Legacy unsigned-pass/device-key/offline compatibility increases the number of write paths and attribution models. It should have explicit scope and eventual retirement criteria. Compatibility should not exempt movement writers from common domain invariants.

### 8.3 Live integration and background work

The implemented update sequence is commit → scoped revision change → next foreground poll → fresh reads → rendering/cache. Approximate five-second polling can reasonably support campus operations; it is not instantaneous push, guaranteed delivery when the phone is suspended, or a barrier-control signal. The prior browser roundtrip demonstrates the tested audits appear automatically in an already-open web portal.

Maintenance and notice delivery depend on staff activity/request handling in the reviewed arrangement. They are not proof that reminders/retention run at a fixed time when no staff application is open. Define the required service level before adding a scheduled job or changing hosting.

## 9. Web and mobile responsibilities

| Responsibility | Admin web | Guard web | Guard mobile | Owner web |
|---|---|---|---|---|
| Registration, staff administration, policy | Primary | Read relevant records | Read relevant records | Own details |
| Physical pass/driver verification | Operational fallback | Primary fixed-terminal route | Primary camera/portable route | Present own pass |
| Visitor issuance | Today/future administration | Today | Today with OCR/photo assistance | No general issuance |
| Direction permissions | Configure/review proposed shared policy | Follow policy | Follow policy | None |
| Security cases | Resolve/authorize exceptions | Report/contact/notes | Report/evidence and operational context | Own status/next steps |
| Payments/renewals | Cash/admin reconciliation | No ordinary cashier authority | No ordinary cashier authority | Own eligible online actions |
| Fleet monitoring/audit/export | Primary | Operational scope | Concise current context | Own records |
| Evidence capture | Review/capture where useful | Optional terminal capture | Primary portable capture | No general evidence review requirement |

Separate interfaces are justified. Equivalent actions must have equivalent backend rules, while administration need not be copied into mobile. Owners do not need guard scanning, global occupancy or staff approval tools. Visitors do not require accounts solely to receive a temporary pass.

## 10. UX and usability findings

### Task clarity and speed

The mobile Dashboard / Scan / Visitor structure fits guard work. The main scan screen has overlapping header/status/control areas, and the camera frame is high in the portrait viewport. Existing geometry measurements found approximately 144–160 logical pixels above the available area's midpoint in representative layouts. That earlier test measured simulated texture geometry, not physical-camera behavior. Current source retains the unbounded scroll/center structure.

**Recommendation:** simplify duplicate scan controls and center the usable scanning frame within the actual remaining viewport, with short-screen/large-text support. Keep manual entry and honest camera-error recovery. This is a UX recommendation; off-center geometry alone is not proof QR scanning fails.

The desktop portal repeats dense vehicle/incident/history content. Organize information around tasks: verify passage, see who is inside, investigate case, administer registration. Keep recent activity contextual instead of duplicating large tables across dashboards. Confirm changes with guards doing real timed work; table density is not universally bad for trained office staff.

### Status and language

“Banned,” “suspended,” “blocked,” “held,” “revoked,” and “closed” need consistent meanings. Red should not be the sole explanation. Display separate physical presence, reason for restriction, allowed next action and responsible office/person. Historical audit records need event-time wording. Completed visitors need completion wording. Approval requests should distinguish pending work from requests the signed-in administrator can decide.

### Errors and recovery

Earlier changes preserve form input on server refusal, protect repeated submissions and show partial-success recovery. These are useful improvements. Remaining problems include false success for printing/media, queue durability, optional duty-data recovery and global response/error state. An uncertain movement should continue to offer the same confirmation retry, not encourage a new scan that could reverse the recorded state.

### Camera, photos and OCR

QR verifies the pass token; OCR suggests text; neither proves the person/vehicle matches the authorization. Guards should inspect and correct OCR results before issuance, and plate mismatches should have a clear reasoned escalation. Prior parser/photo fixes improve input handling but do not establish recognition accuracy in poor light, orientation changes or damaged IDs.

Torch failure can leave misleading UI state in the current code; lifecycle paths remain device-sensitive. Verify permissions denied/permanently denied, lens switch, interrupted capture, pause/resume, orientation, low memory, slow uploads and retakes on actual supported phones. Do not market the OCR as automatic identity verification.

### Launch experience and accessibility

The branded shield/P mark and short animated transition provide a more recognizable launch than the Flutter default. Animation progress is decorative, not measured backend readiness. Startup currently initializes storage before `runApp` and the custom animation routes to login. Native launch timing, cold-start failure and actual phone transitions remain unverified.

The launch includes some semantics/reduced-motion handling, but that does not certify all motion transitions or the entire app's accessibility. Use the same priority for readable text, visible focus, keyboard operation, larger text and labels as visual polish. A full accessibility audit has not been executed here.

## 11. Questionable business/design decisions — separate from defects

### D01 — Every ordinary violation blocks both entry and exit

**P1 policy decision · Unresolved requirement.** Current implementation applies this to parking/fire-lane, expiry, driving, unauthorized-driver and other violations. Broad departure restrictions may create an operational conflict: a vehicle in a prohibited location may need to be moved promptly, while an administrator is unavailable. Expected rules should distinguish admission denial, investigation and authorized vehicle retention. Recommend a campus-approved decision table and reachable emergency authority. This report does not make a legal determination or assume departure must always be allowed.

### D02 — VIP grants unrelated exemptions together

**P2 policy/design concern.** VIP exempts fee, driver confirmation, ordinary violations and overtime/curfew logic. That is broader than simply providing convenient access for a senior official. If custody verification is central, skipping driver verification weakens the very problem being solved. Recommend confirming each exemption, retaining safety/security checks where required and making actual privileges explicit. A complex privilege engine is unnecessary if a small set of documented rules suffices.

### D03 — Police referral, clearance and removal are conflated

**P2 design concern.** Case close offers “Referred to police / vehicle removed,” but closure is not a departure log or proof of physical removal. Referral has its own timeline step. Recommend separating referral, case disposition and observed physical departure in language and required evidence. Do not automatically add external police integration.

### D04 — Single versus dual administrator changes authorization guarantees

**P2 policy concern.** Some sensitive operations are direct when only one active admin exists; two admins trigger dual approval. This may be practical for a small office but must be explicit. “Clearance signed” and “Dismissed” also produce similar access effects through different approval paths. Recommend confirming who may clear versus dismiss, what evidence differentiates those outcomes, and how staffing changes affect pending requests. This is not a blanket claim that the existing approval mechanism is bypassed.

### D05 — Calendar-year fees, quotas and ownership are hardcoded assumptions

**P2 unresolved requirements.** Fees are PHP 250 for two/three-wheel categories and PHP 500 for standard categories, with free bicycles/nonplated classifications; validity/renewal is calendar-year based. Quotas are per owner/class, not concurrent parking spaces. Recommend confirming campus policy and the treatment of late-year registration, transfer credit, staff vehicles and synthetic identifiers for nonplated vehicles. These rules are not defective merely because they are fixed in code.

### D06 — Item inspection records only a complete-list assertion

**P2 design concern.** A Boolean is adequate when all declared items match. It is insufficient to honestly describe missing equipment, partial unloading, retained property or disputed quantity. Recommend a concise discrepancy note/exception flow linked to a case, if these event/delivery scenarios occur. Do not turn SecurePark into a full inventory product.

## 12. Redundant or unnecessary functionality

1. **Overlapping case-resolution controls:** Cases, older incident “Clear & Unblock,” and violation paths expose related actions with different guidance. Keep underlying historical records, but give staff one consistent case action vocabulary and shared rules.
2. **Historical entry/exit screen implementations:** Flutter retains older scanner/dashboard classes beside the active guard shell. Their existence is not itself a user-facing duplicate. Mark inactive routes and assess imports before removal; avoid maintaining competing operational logic.
3. **Demo CCTV and unsupported print controls:** these add apparent completeness without operational capability. Remove false claims; retain a clearly labeled demo only for demonstrations.
4. **Repeated dashboard tables and stale strike vocabulary:** they increase scanning effort and specification confusion. Simplify presentation and terminology without discarding audit history.
5. **Multiple backend copies:** a generated deployment mirror can be justified by hosting; independently editable copies cannot. Keep one source of truth and a checked generation/release workflow.

The financial and case modules are not automatically unnecessary: both affect actual registration/admission. Their complexity should be justified by campus practice. A full rewrite to reduce file count would not necessarily simplify the product.

## 13. Missing or incomplete functionality

### Required to make existing promises dependable

- Shared checkpoint/direction rules reflecting normal and event operations.
- Physically accurate custody transitions and a reasoned reconciliation procedure for missed/contradictory movement records.
- One validated visitor checkout path with audit, items, holds and idempotency.
- Accurate full-population operational totals and clearly complete/limited exports.
- Durable server-scoped offline persistence, persistence-failure feedback and rejected-event review.
- Complete eligibility/remaining-blocker responses after case resolution.
- Honest print/media availability and release eligibility/expiry display.
- A coherent rule for revoked visitor departure and emergency release.

### Operational requirements needing definition or acceptance evidence

- Outage/manual admission procedure and reconciliation responsibility.
- Who verifies owner identity and how credentials reach the owner securely; account-provisioning recovery.
- Responsibility for duplicate-payment refund, reconciliation and approved receipt use.
- Expected notification/maintenance timing when no staff client is active.
- Backup/restore ownership and evidence retention/access requirements; source settings alone do not establish recovery readiness.
- Native device/camera/OCR acceptance and deployment-specific MySQL/provider validation.

These are not requests to build a new enrollment system, visitor account portal, complex workflow engine or automated gate controller.

## 14. Real-world scenarios and expected outcomes

| Scenario | Expected operational outcome | Current evidence / concern |
|---|---|---|
| Paid owner's authorized driver enters Gate 1, exits Gate 2 on ordinary day | Identity/vehicle check, correct gate direction, one audit per passage, presence returns outside | Main online movement supported; normal direction policy differs across clients |
| Event uses Gate 2 for entry | Authorized event ingress at Gate 2, attributable to that physical checkpoint | Mobile permits it; web guard2 ingress restriction obstructs it |
| Guard scans same QR twice after a lost response | Original confirmation result recovered; no reverse movement | Ticket retry tested previously and appropriate |
| Owner already inside becomes unpaid after a fee change | Clear instruction; ordinary fee issue should follow approved entry/exit rules | Entry payment restriction and inside-exit allowance generally sensible |
| Vehicle has independent security case plus a parking violation | Closing one preserves location and remaining hold | New probe reproduces false Outside/clearance response |
| Visiting supplier carries event equipment | Pass issuance, actual entry, inventory assertion, honest discrepancy report, actual exit audit | Boolean all-items verification exists; legacy checkout bypasses it |
| Visitor exits and later returns the same day | Behavior follows explicitly communicated single-visit/reentry policy | Implementation refuses old pass; policy not confirmed |
| Visitor remains after midnight | Preserve inside record, permit or escalate actual exit per standing, record overstay | Ordinary overstay exit supported; revoked/held rule contradictory |
| Guard revokes visitor while inside and escorts to exit | Authorized escorted departure with audit; no ambiguous bypass | Normal scanner refuses; legacy checkout accepts without movement audit |
| Admin needed for held exit cannot be reached | Defined emergency authority/procedure with reason and later review | Registered one-use release exists; availability/outage policy unresolved |
| Phone loses network during confirm | Keep original ticket and uncertainty visible; reconcile saved result | Main retry design appropriate; cannot equate offline cache with clearance |
| Phone has unsynced records, server is changed or app killed | Events remain durable and tied to their originating system | Current queue origin/persistence risks remain |
| Cash is paid while online callback arrives | Single activation, accurate payments, detected duplicate and refund responsibility | Sequential cases tested; MySQL concurrency unverified |
| Campus operates for a year with many images/logs and multiple terminals | Bounded update work, complete reports and usable history | Full-table revision scans and bounded searches need scale validation |
| Guard gets blurry OCR result or denies camera permission | Manual correction/fallback; no false identity match or saved-photo success | Source improvements exist; physical-device acceptance outstanding |

## 15. Prioritized recommendations and acceptance criteria

### Stage 1 — Agree on the smallest authoritative product rules

Approve a concise matrix for normal/event gate directions; which conditions block entry versus exit; emergency and visitor escort authority; VIP privileges; visitor reuse; fee/renewal/quota policy; outage/manual documentation. Tie each rule to a stakeholder decision rather than a comment or old README.

**Acceptance:** web, mobile and backend behavior can be compared to one unambiguous policy matrix. Unanswered rules are visibly pending, not silently implemented as assumptions.

### Stage 2 — Repair integrity before adding functionality

Address F01/F02/F09 first, then server-scoped durable queues and visitor/payment serialization. Centralize movement and eligibility while preserving known-good confirmation retry behavior. Make mandatory audit transactional and denial/case persistence coherent.

**Acceptance:** closing a case never records departure; remaining blockers are truthful; every supported visitor checkout records one validated movement; concurrent retries preserve one outcome; server switching/process interruption do not lose or misdirect pending events. Execute relevant concurrency tests on MySQL, not only SQLite.

### Stage 3 — Align operational interfaces

Apply the approved gate mode consistently; correct totals, historical state text, completion/revocation labels, release CTA/expiry and password semantics. Remove false print/CCTV claims and consolidate resolution guidance.

**Acceptance:** a guard can complete normal and event journeys in either supported client with matching permission/data outcomes, and every status/success message is supported by the saved state.

### Stage 4 — Prove real deployment operation

Run an installed-phone/browser acceptance exercise using test identities and vehicles: account creation → first login/password change → registration/payment → pass display → native scan → driver/item check → physical entry/exit confirmation → open web audit refresh → case/release → outage recovery. Validate real supported phones, MySQL, hosting and configured payment/mail providers.

**Acceptance:** agreed campus scenarios pass with recorded evidence, hardware errors recover honestly, and unresolved events/payments have an accountable review path. A debug APK or mocked OCR test alone does not meet this gate.

### Stage 5 — Improve performance and usability using observed workload

Replace table-hash polling with transactionally updated revisions, reduce inline image traffic, finish complete report queries, simplify crowded scanning/dashboard layouts and retire inactive paths carefully.

**Acceptance:** measured response/update cost remains acceptable with realistic retained history, concurrent terminals, poor connectivity and intended text sizes. Optimize observed bottlenecks without introducing infrastructure the campus cannot operate.

## 16. Unresolved questions for campus review

The user confirmed normal entry/exit gate separation and event entry at both gates. The following are still unanswered and materially affect readiness:

1. Which written rule authorizes blocking departure for each kind of violation/security matter, and who can authorize an emergency exit when an administrator is unavailable?
2. Which VIP exemptions are actually authorized: payment, curfew, driver identity, ordinary parking violations, security investigations?
3. Does a visitor date pass permit one visit or repeated entry? What is the escorted-exit rule for revoked visitors and item discrepancies?
4. During an outage, may guards admit vehicles using manual records, and who reconciles them? Is offline visitor issuance meant to be trusted across both gates before synchronization?
5. During events, how are exits routed, who activates/restores the gate direction exception, and does a duty shift determine the authoritative checkpoint?
6. Are the implemented fees, calendar-year validity, per-class quota and replacement credits the approved campus rules?

This report proceeds without inventing answers. Its confirmed defects remain defects regardless of those answers: fake printing, unlogged unchecked checkout, password mutation and case closure changing presence are not resolved by policy clarification.

## 17. Final evaluation

**Does the system make sense?** Yes. The core connection between registered eligibility, human gate verification, physical movement records and exception handling is appropriate and useful.

**Is every existing feature justified?** No. Demo media/printing claims are inappropriate in operational flows. VIP privileges and broad exit holds need explicit justification. Overlapping resolution interfaces and legacy writers create avoidable inconsistency. Payment, owner access, shifts and visitor items are justified only to the extent they match campus operations; they should be simplified around those operations rather than expanded indiscriminately.

**Is it logically consistent?** Not yet. Normal/event gate behavior is not shared, custody and standing are overloaded, visitor exit paths disagree, and clearance/reporting messages can overstate reality.

**Is it properly implemented?** Many core mechanisms are sound and have useful automated/runtime evidence, especially online confirmation, retry handling, server-scoped permissions and tested browser recovery. The new probes confirm that important exception combinations remain wrong. Native hardware and production dependencies are not yet demonstrated end to end.

**Overall judgment:** SecurePark has a credible foundation and substantial implementation, but it is a developing operational product with unresolved policy and integrity gaps. Prioritize coherent rules, trustworthy custody/audit transitions and real deployment acceptance. Additional visual polish or feature volume cannot substitute for those requirements.
