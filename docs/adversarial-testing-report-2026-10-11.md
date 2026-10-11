# Adversarial input, concurrency and recovery testing

Date: 11 October 2026

## Verdict

**The system does not yet satisfy “unexpected inputs and failures always save and display correctly.”** Expanded tests reproduced invalid data being accepted, broken response contracts, duplicate visitor/payment records, and mobile queue recovery/isolation problems.

The new suites executed **965 checks: 864 passed and 101 failed**. These are test cases, not 101 distinct defects; many failures are variants of the same cause. The earlier workflow tests covered useful scenarios but did not expose these conditions. Passing ordinary workflows is therefore insufficient evidence for unconditional reliability.

This pass added tests and evidence, and did not change application source. The failing regression tests remain reproducible. No campus records or hosted databases were used. The temporary MariaDB instance was shut down and its temporary data directory removed.

## Method and scope

- Actual PHP requests against disposable SQLite fixtures. Each malformed-input probe restores a known fixture and compares business-table contents before and after the request.
- Fixed random seed `20261011` for 150 unusual-text round trips and 120 movement sequences. The movement model checks that custody matches successful unique audits after each step.
- Two PHP workers sharing a database for competing requests and duplicate confirmations.
- Injected database failures at audit insertion, custody update, visitor-item insertion and mode-authorization audit insertion.
- A local proxy disconnects before forwarding or after the backend commits, then retries the same confirmation.
- A **new, isolated MariaDB 10.4.32/InnoDB instance** on a random loopback port, with its own temporary data directory and credentials. No Windows service was installed and the existing XAMPP data directory was not used.
- For visitor/payment races, a 200 ms pause was inserted **only in the temporary PHP copies**, after the precondition check. This forces a valid adverse scheduling window; the branch logic was unchanged. The same duplicate failures occurred on SQLite and MariaDB. These checks prove the race is possible, not its normal-frequency probability.
- Real Chrome tests for unusual text, executable-looking text, validation, lost-save responses and live list updates.
- Actual mobile queue code with controlled HTTP responses and preferences. Storage-full and corrupted-data conditions were injected; this was not a physical-device process-kill test.

## Results

| Suite | Passed | Failed | Scope |
|---|---:|---:|---|
| Input/permission/Unicode matrix | 547 | 81 | 628 probes across write routes, field shapes, query shapes, authorization, dates, quantities and text |
| Recovery, concurrency and movement model | 266 | 2 | Rollback, lost replies, competing scans, visitor/payment races, seeded transitions |
| Isolated MariaDB | 7 | 3 | Schema/migration, PHP integration, InnoDB confirmation/rollback/policy, duplicate writes, column limits |
| Real Chrome adversarial workflows | 18 | 0 | Literal text/XSS rendering checks, invalid contact, lost reply, retry, live saved-record visibility |
| Credential boundaries | 7 | 2 | Exact whitespace, Unicode and long-password distinction |
| Payload edges | 12 | 9 | Item-confirmation types, corrupted/oversized images, production-style error responses |
| New mobile queue regressions | 7 | 4 | Transport errors, acknowledgements, storage failures, corrupt queues, server isolation |
| **New checks total** | **864** | **101** | Multiple cases can expose the same defect |

The original backend regression runner was rerun: **678 broad API assertions and 85 movement checks passed**, along with revision/transport tests, syntax checks and backend mirror checks. The final full Flutter run had **197 passed, four failed, two skipped**; all four failures are the newly added queue regressions. The two skipped integration cases require their separate fixture wrappers and were not rerun during this pass. Dart analysis reported no issues.

Raw summary: `artifacts/adversarial/summary.json`. Detailed per-case outputs are the adjacent `*-results.json` files. Full Flutter output is `artifacts/adversarial-full-mobile.log`.

## Confirmed findings and recommended repairs

### A01 — Invalid scalar fields can save incorrect data — P1

**Current behavior:** Arrays/objects supplied where text or IDs are expected can be coerced into values such as `Array`/`ARRAY` or integer `1`. Examples include visitor name/plate, registration fields, incident notes, movement notes/driver selection and the gate-mode reason. The matrix recorded **42 invalid-shape cases that mutated business data**. An array-valued reason can authorize a mode change with a meaningless reason.

**Expected:** Validate each known field's type and permitted bounds before reading or saving it. Invalid scalar shapes should return structured 400/422 responses and make no business change.

**Recommendation:** Add explicit request schemas/shared scalar validators, including nested driver/item structures. Do not repair these inputs by silently stringifying them. Preserve any deliberately supported scalar compatibility only when documented and tested.

**Locations:** `backend/api/visitors.php:137`, `backend/api/vehicles.php:115`, `backend/api/users.php:45`, `backend/api/settings.php`, `backend/api/logs.php`.

### A02 — Some malformed fields crash instead of returning validation JSON — P1

**Current behavior:** There were **39 broken-response cases** in the initial matrix: 27 body-field variants and 12 query-array variants. Examples: an array username passed to `trim()`, or `vehicles.php?plate[]=x`. Some debug fixture responses carried HTTP 200 with PHP error output. Repeating representative cases with `SP_DEBUG=false` still failed the structured validation contract.

**Expected:** An invalid input must produce a predictable error response that the web/mobile client can display safely.

**Recommendation:** Validate query/body types before calling string functions, and add a final JSON exception boundary with server-side logging. The exception boundary supplements validation; it does not make garbage inputs acceptable.

**Locations:** `backend/api/auth.php:36`, `backend/api/users.php:45`, `backend/api/vehicles.php:31`, `backend/api/logs.php`, `backend/api/incidents.php`.

### A03 — Non-boolean item confirmation can authorize passage — P1

**Current behavior:** `items_verified: "false"`, `"no"`, `{"verified":false}` and `[false]` were accepted and saved movements. The implementation uses `empty()` rather than checking explicit confirmation.

**Expected:** Only the documented positive confirmation value should authorize the item check. All false or malformed representations must preserve custody and logs.

**Recommendation:** Require JSON boolean `true`, or a narrowly defined compatible representation if needed by an existing client. Enforce this consistently on every online movement writer.

**Location:** `backend/lib/movements.php:200`.

### A04 — Overlapping visitor issuance creates duplicate active passes — P1

**Current behavior:** Two requests for the same plate/day both returned 201 and created two active passes on SQLite and MariaDB. The duplicate query happens before the insert transaction and does not reserve the relevant plate/day.

**Expected:** One active pass for the applicable plate/day rule; the other request should recover the same result or receive a clear conflict.

**Recommendation:** Enforce the active-pass invariant at the database boundary, with appropriate serialization and a stable issuance idempotency key. Account for the existing completed/revoked-pass rules rather than adding a naive uniqueness rule that forbids legitimate history.

**Location:** `backend/api/visitors.php:180`.

### A05 — Overlapping cash submissions create duplicate payment records — P1

**Current behavior:** Both requests can pass the unpaid check and create payment records. The fixture produced two paid rows; the second can carry a duplicate/refund note. That note does not prevent the duplicated accounting operation.

**Expected:** Retrying or overlapping the same cash collection should produce one receipt/payment outcome. Separate genuine collections require distinct, explicit operations.

**Recommendation:** Lock and recheck the vehicle/payment obligation within the same transaction as payment creation/settlement, and use an idempotency key for the collection. Keep separate reconciliation for an external provider that actually collected money twice.

**Locations:** `backend/api/payments.php:98`, `backend/api/payments.php:111`, `backend/lib/payments.php:119`.

### A06 — Mobile persistence failure can be silently acknowledged — P1

**Current behavior:** When preferences writing throws a simulated disk-full error, enqueue completes normally. Clearing the memory copy then loses the event. The persistence helper swallows the failure after placing the value in memory.

**Expected:** The app must not claim a durable queued save until persistence succeeds. If storage fails, it must show an actionable failure and retain/retry the operation where possible.

**Recommendation:** Give essential queued writes an explicit success/failure contract and a durable storage strategy. Avoid treating a memory fallback as a saved offline event.

**Location:** `mobile-app/lib/services/local_cache_service.dart:84`.

### A07 — Corrupt queue data can look empty and synchronized — P1

**Current behavior:** Invalid queue JSON is returned as an empty queue and can produce `SyncStatus.synced`. One malformed element in an otherwise valid list also hides the valid event alongside it.

**Expected:** Corruption must be visible as a recovery problem; recoverable records must not silently disappear from the worker's view.

**Recommendation:** Parse and validate records individually, quarantine invalid entries, preserve the raw failed store for recovery and expose an error state rather than “synced.” Avoid overwriting corrupt pending data with an empty list.

**Location:** `mobile-app/lib/services/local_cache_service.dart:273`.

### A08 — Pending events can be delivered to a different server — P1

**Current behavior:** An event queued while configured for server A was submitted to server B after changing the server and signing in with B's account. Queue storage lacks its originating server/account context.

**Expected:** Pending events must remain associated with their original destination and attribution context.

**Recommendation:** Partition durable queues by normalized server identity and appropriate account/context metadata. Make unresolved events visible when switching; never silently submit them to the new server.

**Locations:** `mobile-app/lib/services/local_cache_service.dart:18`, `mobile-app/lib/services/sync_queue_service.dart:174`.

### A09 — Overlong staff names break MySQL responses — P2

**Current behavior:** A 1,000-character staff name reached a bounded MySQL column and caused an uncaught database exception rather than a validation response. SQLite's permissive text storage does not reproduce that limit.

**Expected:** Reject oversized values before insertion, preserving the form and returning a field-specific message.

**Recommendation:** Align request validation and frontend limits with actual schema limits, using the right character/byte semantics. Exercise these limits on the deployed engine.

**Location:** `backend/api/users.php:83`.

### A10 — Accepted password text can change during account creation — P2

**Current behavior:** A custom password containing leading/trailing spaces was accepted when creating an account, but signing in with the exact supplied text failed. Staff creation trims it; authentication preserves it.

**Expected:** Either preserve the exact password or reject unsupported input explicitly before creating the account.

**Recommendation:** Apply one password policy consistently across creation, reset, change and sign-in. Do not silently normalize passwords.

**Location:** `backend/api/users.php:52` and the corresponding reset path.

### A11 — Accepted long passwords can compare equal despite different suffixes — P1

**Current behavior:** Two passwords with identical first 72 bytes but different suffixes both authenticated for the account. The bcrypt input limit is not reflected in acceptance validation.

**Expected:** Accepted passwords should not silently discard distinguishing input.

**Recommendation:** Enforce a compatible byte limit consistently or adopt a suitable password-hashing policy with a deliberate migration strategy. Do not add an ad hoc truncation rule that remains invisible to the user.

**Locations:** `backend/api/users.php:83`, `backend/lib/auth.php:230`.

### A12 — Header-only image data is labelled as a valid photo — P2

**Current behavior:** PNG/JPEG magic bytes alone were accepted and returned with `hasVehiclePhoto=true`, despite not being decodable photos. Valid PNG, invalid base64, remote URLs, HTML data and oversize rejection behaved as expected.

**Expected:** Under the existing optional-photo policy, invalid images should be omitted and represented as unavailable, not claimed as valid stored photos.

**Recommendation:** Validate actual image decoding and dimensions/resource limits, not just the first bytes. Keep optional-photo failure separate from visitor issuance failure.

**Location:** `backend/lib/photos.php:13`.

## What the adverse tests successfully verified

- Same-ticket concurrent confirmations returned the original movement and produced one audit.
- Competing prepared scans had one successful transition; the rest were stale rather than duplicate movements.
- Audit/custody storage failures rolled back and the original confirmation could be retried after repair.
- Gate-mode authorization did not commit when its required audit failed.
- Visitor item-storage failure did not leave a usable partial pass.
- A lost confirmation reply recovered the committed movement once; an unsent request saved once on retry.
- The seeded movement model maintained custody/audit agreement.
- Chrome rendered tested apostrophes, Unicode and HTML/SQL-looking visitor names literally; no injected dialogs or uncaught errors occurred in the completed browser run.
- An actual visitor save whose reply was dropped appeared in the open browser list. A user retry did not create another pass in the sequential case.
- Mobile retained queued events after 503 responses, malformed replies, missing acknowledgements, unknown statuses and connection failures. It removed only explicitly acknowledged events from a partial batch.

## Boundaries of this evidence

This is systematic, bounded testing—not enumeration of every possible input, device state or schedule. An initial browser timing timeout was investigated; the completed run captured request results and passed without application changes. It is not counted as a confirmed application defect.

Native Android/iOS hardware was unavailable; Flutter listed Windows, Chrome and Edge. Physical camera/OCR quality, permissions/background behavior and actual OS process death/storage corruption remain unverified. The queue failures above were deterministic software injections. No production mail/payment provider was contacted, no hosting/load/endurance acceptance was performed, and no production database was modified.

MariaDB coverage is now stronger than in the earlier report: this pass exercised a real isolated InnoDB runtime. It does not establish compatibility with every production MySQL version/configuration or replace full deployment acceptance.

## Reproduction and next action

From the project root:

```text
python tests/adversarial_runtime.py
python tests/adversarial_recovery.py
python tests/adversarial_mysql.py
python tests/adversarial_browser.py
python tests/adversarial_credentials.py
python tests/adversarial_payload_edges.py
```

From `mobile-app`:

```text
flutter test --no-pub test/adversarial_queue_test.dart --reporter expanded
```

Nonzero exits are intentional while confirmed defects remain. These tests must become green through fixes, not by removing failing cases or treating incorrect saves as acceptable.

Repair priorities: **typed validation and explicit item confirmation; visitor/payment transaction/idempotency guarantees; mobile durable queue isolation/recovery; consistent password boundaries; schema/photo validation.** Then rerun these exact regressions, the full existing suites and native-device acceptance. The system should not be described as universally reliable before these failures are resolved.
