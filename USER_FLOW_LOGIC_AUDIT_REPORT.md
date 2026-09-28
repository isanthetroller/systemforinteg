# SECUREPARK: FULL SYSTEM USER-FLOW & REAL-WORLD LOGIC AUDIT REPORT

> **Document Type:** Operational Architecture, User Flow & Logic Verification Audit  
> **Target Scope:** Mobile Scanner App (Flutter), Web Admin App (Vanilla JS/Tailwind), Web Student App, Backend REST API (PHP/PDO), MySQL Database Schema  
> **Audit Status:** Completed  
> **Implementation Phase Constraint:** Zero Code Modifications (Investigation & Documentation Only)  
> **Date:** September 28, 2026  

---

## Executive Summary

This audit evaluates the **SecurePark Campus Custody & Gate Management System** strictly from the operational perspective of human users: Gate Security Officers, Security Administrators, Registered Students/Faculty, and Campus Visitors.

The system comprises five interacting tiers:
1. **Mobile Gate Terminal (Flutter/Android):** Gate guard client for QR pass scanning, Optical Character Recognition (OCR) visitor onboarding, egress scanning, and local audit tracking.
2. **Web Administrative Portal (Single-Page Vanilla JS + Tailwind):** Operations dashboard, Gate Monitor terminal, live campus census ("On Campus Now"), vehicle registry, visitor day passes, 3-strike violations, and security incidents.
3. **Web Student Portal (Vanilla JS/Tailwind):** Self-service digital vehicle pass, QR display, violation history, and gate activity timeline.
4. **Backend REST API (PHP/PDO):** Gate logging, pass verification, incident management, automated 3-strike policy engine, and system settings.
5. **Relational Database (MySQL on InnoDB):** Tables for `vehicles`, `authorized_drivers`, `visitor_passes`, `visitor_pass_items`, `gate_logs`, `vehicle_violations`, `security_incidents`, `system_users`, and `system_settings`.

### Core Assessment Finding
While individual modules function technically in isolation, **the system suffers from critical real-world logic disconnects, contradictory user states, and cross-application data synchronization gaps**. 

Most notably:
- The mobile entrance scanner fabricates valid visitor passes out of unrecognized/forged QR codes, presenting the guard with a green "CLEARED" button.
- The mobile exit scanner records exits as new append-only rows without updating earlier entry records, causing vehicles to appear twice on the mobile dashboard and preventing the "Inside Campus" KPI from decrementing.
- The web dashboard counts only registered vehicles in its "Inside" metric, while the sidebar counts both vehicles and visitors, creating conflicting headcounts on the same screen.
- Unregistered vehicles admitted through the mobile app are logged to `gate_logs` but never appear in the admin's "On Campus Now" monitor.

---

## Table of Contents
1. [Section A: System Overview](#section-a-system-overview)
2. [Section B: Intended User Journeys](#section-b-intended-user-journeys)
3. [Section C: Current Actual User Journeys](#section-c-current-actual-user-journeys)
4. [Section D: Workflow Mismatches Table](#section-d-workflow-mismatches-table)
5. [Section E: Cross-App Synchronization Problems Table](#section-e-cross-app-synchronization-problems-table)
6. [Section F: Entity State & Status Problems Table](#section-f-entity-state--status-problems-table)
7. [Section G: Dedicated QR Code Lifecycle & Logic Audit](#section-g-dedicated-qr-code-lifecycle--logic-audit)
8. [Section H: Guard Perspective Analysis](#section-h-guard-perspective-analysis)
9. [Section I: Administrator Perspective Analysis](#section-i-administrator-perspective-analysis)
10. [Section J: Missing Workflows](#section-j-missing-workflows)
11. [Section K: Unnecessary & Illogical Steps](#section-k-unnecessary--illogical-steps)
12. [Section L: Edge Cases & Error Handling Analysis](#section-l-edge-cases--error-handling-analysis)
13. [Section M: Severity & Prioritized Remediation Roadmap](#section-m-severity--prioritized-remediation-roadmap)

---

## Section A: System Overview

In plain language, SecurePark is designed to control and monitor physical vehicular access through the gates of the National College of Science and Technology (NCST).

```
                      +-----------------------------+
                      |       Campus Gates          |
                      |  (Ingress / Egress Points)  |
                      +--------------+--------------+
                                     |
               +---------------------+---------------------+
               |                                           |
    [Mobile App / Scanner]                       [Web Gate Monitor]
    Used by: Gate Guards                         Used by: Guard Desk / Admin
    Tasks: Scan QR, Verify Driver,               Tasks: Scan/Type Plate, Driver Pick,
    Check Items, Quick Check-in                  Item Checklist, Ingress/Egress
               |                                           |
               +---------------------+---------------------+
                                     |
                                     v
                        +-------------------------+
                        |  Backend API (PHP 8.x)  |
                        |   - /api/verify.php     |
                        |   - /api/logs.php       |
                        |   - /api/oncampus.php   |
                        |   - /api/visitors.php   |
                        |   - /api/vehicles.php   |
                        +------------+------------+
                                     |
                        +------------v------------+
                        |   MySQL Database        |
                        | (vehicles, logs, etc.)  |
                        +------------+------------+
                                     |
               +---------------------+---------------------+
               |                                           |
    [Web Admin Portal]                           [Web Student Portal]
    Used by: Security Officers                   Used by: Vehicle Owners
    Tasks: Live On-Campus List,                  Tasks: View Digital QR Pass,
    Bans/Strikes, Audit Logs, Settings           Check Standing, View Gate Activity
```

### Operational Intent
- **Registered Vehicles (Students & Faculty):** Permanent registered vehicles display a physical RFID/QR windshield decal or digital pass. The gate guard scans the pass, verifies that the physical driver matches the vehicle's approved driver roster, and clears entry. The vehicle becomes "Inside Campus". Upon leaving, the vehicle is scanned at the exit gate, dwell time is logged, and status reverts to "Outside".
- **Campus Visitors:** Non-registered vehicles arrive at the gate. The guard inputs visitor identity, license plate, purpose, host department, and any equipment/items brought in (e.g., event chairs). A single-day temporary QR pass is issued. The visitor scans in at entry and scans out at exit, where declared items are cross-checked before departure.
- **Enforcement & Safety:** Vehicles exceeding campus stay limits, driving recklessly, or parking overnight accumulate warnings (strikes). Reaching 3 strikes triggers an automatic violation, campus ban, and security incident hold. Banned vehicles must be blocked at the gate.

---

## Section B: Intended User Journeys

### 1. Entrance Guard (Mobile Scanner)
```
Arrive at Gate -> Log In -> Open Camera Scanner -> Vehicle Approaches ->
Scan Windshield/Phone QR -> System Validates Signature & Status ->
Display Vehicle Details, Driver Roster & Photo -> Guard Confirms Driver Identity ->
Guard Taps "Clear Entry" -> Gate Opens -> Vehicle Enters -> System Sets Status "Inside Campus" ->
Vehicle Appears on Live Campus Monitor
```

### 2. Exit Guard (Mobile Scanner)
```
Vehicle Approaches Exit Gate -> Guard Opens Exit Scanner -> Scan Vehicle/Visitor QR ->
System Verifies Vehicle is Currently Inside -> Check Declared Items (if Visitor) ->
Guard Taps "Confirm Exit" -> Gate Opens -> Status Changes to "Outside" / "Used" ->
Vehicle Removed from Live Campus Census -> Gate Log Records Exit Timestamp & Dwell Duration
```

### 3. Authorized Driver / Student
```
Log in to Student Web Portal -> View Vehicle Pass -> Check Campus Standing (0/3 Strikes) ->
Drive to Gate -> Present QR Code on Phone Screen -> Guard Scans & Clears ->
Receive Immediate Visual Status "ON CAMPUS" -> Later Exit -> Pass Reverts to "Outside"
```

### 4. Campus Visitor
```
Arrive at Gate -> State Purpose & Present ID -> Guard Fills Checklist & Declares Items ->
System Issues Single-Day Pass Valid for Today -> Visitor Receives QR Code ->
Guard Clears Ingress -> Visitor Enters -> On Leaving: Guard Scans Exit QR ->
Guard Verifies Declared Items Carried Out -> Pass Marked "Used" -> Exit Logged
```

### 5. Security Administrator
```
Log in to Web Admin Portal -> View Real-Time Dashboard ->
Monitor Accurate "Vehicles Inside Campus" Count -> Inspect "On Campus Now" List ->
Filter by Overtime/Overnight Vehicles -> Review Audit Logs ->
Manage 3-Strike Violations -> Set Pass Validity Rules in Settings
```

---

## Section C: Current Actual User Journeys

Based on line-by-line inspection of active source files in [lib/](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib), [web-app-admin/](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/web-app-admin), [web-app-student/](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/web-app-student), and [backend/](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend), the actual execution paths diverge significantly from the intended workflows:

### Current Actual Entrance Guard Flow
1. Guard opens [QrScannerScreen](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/screens/qr_scanner_screen.dart).
2. Guard scans a QR code.
3. In `_processRawQrCode()`, the app calls `GateRepository.resolveVehicle(raw)`.
4. In [VehicleLookupService.dart:91](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/services/vehicle_lookup_service.dart#L91): If the QR code is unknown, forged, or random text, **the service automatically generates a dummy `VehicleRecord`** (`ownerName: 'Visitor / Unregistered Pass'`).
5. The camera stops. The UI renders [ScannedPersonCard](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/widgets/scanned_person_card.dart#L37).
6. Line 37 of `scanned_person_card.dart` renders a green checkmark icon with text: **`SCANNED QR PASS VERIFIED`**.
7. The bottom bar renders two buttons: Red `BLOCKED` and Green `CLEARED (TO GO)`.
8. Guard taps `CLEARED (TO GO)`.
9. The app posts to `/api/logs.php` with `action: 'Entry Recorded', status: 'Inside Campus'`.
10. In [logs.php:181](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/logs.php#L181), because the request has the mobile app user-agent/header (`$isScanner`), the backend **bypasses registration validation** and inserts the log entry.
11. **Result:** An unknown vehicle is admitted. The mobile app says "ENTRY CLEARED". However, because the vehicle does not exist in `vehicles` or `visitor_passes`, **it never appears in the Admin's "On Campus Now" list**.

### Current Actual Exit Guard Flow
1. Guard opens [ExitScannerScreen](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/screens/exit_scanner_screen.dart).
2. Guard scans a registered vehicle pass.
3. In `_evaluateRegisteredVehicle()` ([exit_scanner_screen.dart:174](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/screens/exit_scanner_screen.dart#L174)), the status is set to `ExitVerificationStatus.valid` **without checking if the vehicle is currently inside campus**.
4. Guard taps "Confirm Vehicle Exit".
5. App posts to `/api/logs.php` with `action: 'Exit Approved', status: 'Departed Campus'`.
6. Backend records the log and sets `vehicles.status = 'Exited'`.
7. Guard returns to [DashboardScreen](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/dashboard/screens/dashboard_screen.dart).
8. The exit log is prepended to `_auditLogs`.
9. `_insideCount` is calculated as `_auditLogs.where((l) => l.isInside).length` ([dashboard_screen.dart:48](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/dashboard/screens/dashboard_screen.dart#L48)).
10. The original entry log row in `_auditLogs` still has `isInside == true`.
11. **Result:** The dashboard inside count **does not decrement**. Both the entry log and exit log appear in the list, making it look as though the vehicle entered twice or remains inside.

---

## Section D: Workflow Mismatches Table

| # | User Action | Expected Result | Actual Result | Underlying Problem | Severity | Certainty |
|---|---|---|---|---|---|---|
| **1** | Guard scans an unregistered / forged QR code at gate entrance | System alerts "Unregistered Pass / Invalid QR", denies access, and instructs visitor to register | Mobile app invents a synthetic visitor record ([VehicleLookupService.dart:91](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/services/vehicle_lookup_service.dart#L91)), displays `SCANNED QR PASS VERIFIED`, and presents a green `CLEARED (TO GO)` button | Fallback code fabricates fake valid records instead of throwing an invalid pass state | **CRITICAL** | **Confirmed** |
| **2** | Guard clears entrance of unknown vehicle | If cleared, vehicle must appear on Admin "On Campus Now" list | Backend writes log row, but vehicle is completely absent from `oncampus.php` and invisible on web dashboard | `oncampus.php` queries `vehicles` and `visitor_passes`, neither of which contains the unverified mobile entry | **CRITICAL** | **Confirmed** |
| **3** | Guard completes vehicle exit check on mobile | Vehicle count inside campus decrements by 1; vehicle status updates to exited | Mobile inside count remains unchanged; vehicle appears twice in dashboard audit log list | `DashboardScreen` treats an append-only transaction log as a list of distinct active vehicles ([dashboard_screen.dart:48](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/dashboard/screens/dashboard_screen.dart#L48)) | **HIGH** | **Confirmed** |
| **4** | Guard scans a banned / suspended vehicle at entrance | Mobile screen shows prominent red "ACCESS DENIED — BANNED", disabling entry clearance | Screen displays red flag note, but card header still displays green `SCANNED QR PASS VERIFIED` and bottom bar still displays active green `CLEARED (TO GO)` button | No gate barrier or button suppression based on `isBanned` or `isFlagged` in `QrScannerScreen` | **HIGH** | **Confirmed** |
| **5** | Guard scans vehicle at exit that never entered campus | System warns: "Vehicle was not recorded as entering campus" | System marks exit verification as `valid` ([exit_scanner_screen.dart:174](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/screens/exit_scanner_screen.dart#L174)) and allows exit logging | Missing pre-condition check verifying `vehicle.status == 'Inside Campus'` | **MEDIUM** | **Confirmed** |
| **6** | Guard registers visitor and prints temporary pass | Temporary QR pass code matches database record for checkout scanning | Mobile generates `NCST-VIS-2026-XXXX`, but backend generates `VP-YYYYMMDD-XXXX` ([visitors.php:176](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/visitors.php#L176)) | Client pass ID generator diverges from server pass code generator; pass code on physical ticket is not in DB | **HIGH** | **Confirmed** |
| **7** | Guard scans visitor bringing 40 declared items on mobile | Guard must verify items before admitting | Mobile scanner bypasses item verification check ([logs.php:191](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/logs.php#L191)); log notes say "not checked by mobile scanner" | Backend relaxes validation for `$isScanner` while strictly requiring it on Web Gate Monitor | **MEDIUM** | **Confirmed** |
| **8** | Student views portal after leaving campus | Pass status says "Outside Campus" or "Off Campus" | Pass displays "Campus status: Exited" and retains previous static timestamp | Backend sets `vehicles.status = 'Exited'` instead of the schema default `'Outside'`; Student app lacks auto-refresh | **LOW** | **Confirmed** |
| **9** | Admin views Dashboard KPI card vs Sidebar | Inside vehicle count is identical across both UI components | Sidebar shows e.g. "5", while Dashboard KPI card shows "3" | Dashboard KPI filters `state.vehicles` (registered only), while sidebar badge calls `oncampus.php` (vehicles + visitors) | **HIGH** | **Confirmed** |
| **10** | Admin attempts to revoke visitor pass of disruptive visitor inside campus | Admin clicks "Revoke" to invalidate QR and flag vehicle at gate | "Revoke" button is hidden/disabled because visitor is currently inside campus ([visitors.js:103](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/web-app-admin/js/visitors.js#L103)) | UI condition `!p.isInside` prevents revoking active on-campus passes | **MEDIUM** | **Confirmed** |

---

## Section E: Cross-App Synchronization Problems Table

| Event | Mobile App | Backend API | Database (`gate_logs` / `vehicles`) | Web Admin App | Synchronization Mismatch Finding |
|---|---|---|---|---|---|
| **Vehicle Enters (Registered)** | Displays "ENTRY CLEARED"; adds log locally; inside count +1 | `/api/logs.php` returns 201 Created | `gate_logs` row added; `vehicles.status` set to `'Inside Campus'` | Appears on "On Campus Now" upon next poll (up to 60s delay); Dashboard KPI card does NOT update without page reload | **Partial Sync:** Dashboard charts and KPI cards do not auto-refresh |
| **Vehicle Enters (Unregistered Fallback)** | Displays "ENTRY CLEARED"; inside count +1 | Accepts request because `$isScanner == true` ([logs.php:181](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/logs.php#L181)) | `gate_logs` row added with raw plate; `vehicles` table unchanged | Appears in Audit Logs table; **MISSING from "On Campus Now" list and missing from all dashboard KPI counts** | **Severe Desync:** Vehicle is physically inside campus and logged, but invisible in live monitoring |
| **Vehicle Exits Campus** | Displays "Exit Approved"; prepends exit log; **Inside count DOES NOT decrement**; vehicle listed twice | Sets `vehicles.status = 'Exited'`; writes exit log | `gate_logs` row added; `vehicles.status` becomes `'Exited'` | Removed from "On Campus Now"; **Dashboard KPI card does NOT update without page refresh** | **Logic Desync:** Mobile app shows vehicle exited AND vehicle inside simultaneously |
| **Vehicle Banned (3 Strikes)** | Does not receive real-time push; only checks standing on plate search | Strike engine updates `is_banned = 1, status = 'Suspended'`; opens held incident | `vehicles.is_banned = 1`; `security_incidents` row added | Incident badge updates; vehicle marked banned in Directory | **Gate Desync:** If mobile app has cached vehicle record, it will not know vehicle is banned until remote sync |
| **Temporary Visitor Pass Issued on Mobile** | Generates `NCST-VIS-2026-XXXX`; shows confirmation screen | `/api/visitors.php` inserts pass with code `VP-YYYYMMDD-XXXX` | `visitor_passes.pass_code` is `VP-...`, NOT `NCST-VIS-...` | Web app lists pass under `VP-...` code | **Identity Desync:** QR printed/shown on mobile cannot be verified by pass code lookup on web gate monitor |

---

## Section F: Entity State & Status Problems Table

```
   [Canonical Schema States]                 [Observed Runtime States]
      +---------------+                          +---------------+
      |    Outside    |<-------------------------|    Exited     |  <-- Contradictory Label
      +-------+-------+                          +---------------+
              |
              | (Ingress)
              v
      +---------------+                          +---------------+
      | Inside Campus |                          | Inside Campus |
      +-------+-------+                          +---------------+
              |                                          ^
              |                                          | (Both present simultaneously
              | (Egress)                                 |  in mobile dashboard!)
              v                                          v
      +---------------+                          +---------------+
      |    Outside    |                          |  Exit Approved|
      +---------------+                          +---------------+
```

| Entity | Current Actual State | Expected Canonical State | Logical Contradiction / Real-World Problem |
|---|---|---|---|
| **Registered Vehicle** | `status = 'Exited'` in MySQL after leaving gate | `status = 'Outside'` | The database migration [001_v2.sql](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/database/migrations/001_v2.sql) sets column default to `'Outside'`. But [logs.php:202](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/logs.php#L202) writes `status = 'Exited'`. In the student portal, it displays `Campus status: Exited` instead of `Outside Campus`. |
| **Audit Log List (Mobile)** | Simultaneously has `status: GateStatus.inside` AND `status: GateStatus.exited` for the same plate | The exit event should either supersede the entry event or the list must distinguish "Current Vehicles on Campus" from "Historical Gate Log Events" | The guard sees two rows for one car and an unchanged "Inside" counter, leading the guard to believe the exit failed. |
| **Unregistered Vehicle Pass** | Exists in `gate_logs` as `status: 'Inside Campus'`, but does NOT exist in `vehicles` or `visitor_passes` | Must either be registered as a visitor pass OR rejected at the gate | Creates an unidentifiable phantom record that cannot be managed, checked out, or tracked for overstaying. |
| **Temporary Visitor Pass** | Displayed QR payload has `passId: NCST-VIS-2026-XXXX`, but DB holds `pass_code: VP-YYYYMMDD-XXXX` | QR payload and DB `pass_code` must be identical | Scanning the pass code string on another gate terminal fails lookup unless searched by plate number. |
| **Flagged Student Vehicle** | Evaluated as `hasActiveFlag == true`, but presented with `SCANNED QR PASS VERIFIED` and `CLEARED (TO GO)` | Card header must display `ACCESS HOLD / WARNING`, and `CLEARED` button must require explicit override confirmation | Contradicts real-world security protocol by signaling success to the guard before clearance. |

---

## Section G: Dedicated QR Code Lifecycle & Logic Audit

The audit examined every stage of the QR code lifecycle: creation, encoding, presentation, scanning, decoding, and retirement.

```
                    +------------------------------------+
                    |  Pass Generation / Digital Issue   |
                    |  (Admin Web App / Student Portal)  |
                    +-----------------+------------------+
                                      |
                                      v
                        Signed Payload Generated:
               SP|{passId}|{plate}|{type}|{validUntil}|{HMAC}
                                      |
                                      +-------------------------------+
                                      |                               |
                                      v                               v
                         [Web Gate Monitor]                 [Mobile App Scanner]
                         Uses /api/verify.php               Bypasses /api/verify.php!
                         - HMAC Checked                     - Decodes JSON locally
                         - Bans Checked                     - Dummy fallback on error
                         - Driver Pick Required             - No HMAC validation
```

### 1. Who Generates Each QR Code?
- **Registered Student/Faculty Pass:** Generated server-side by [backend/lib/qr.php](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/lib/qr.php) using HMAC-SHA256: `SP|{passId}|{plate}|{type}|{validUntil}|{signature}`. Displayed in Web Student Portal and printable as a decal in Web Admin Portal.
- **Visitor Day Pass:** Generated server-side by [backend/api/visitors.php](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/backend/api/visitors.php) (`VP-YYYYMMDD-XXXX`). However, the mobile app also generates client-side codes (`NCST-VIS-2026-XXXX`) on [visitor_registration_screen.dart:782](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/visitor/screens/visitor_registration_screen.dart#L782).
- **Legacy Pass:** Plain JSON payload `{"plateNumber":"...","authorizedDrivers":[...]}` without HMAC signature.

### 2. Who Scans It and Where?
- Gate Guards at Campus Ingress (Entrance) and Egress (Exit) using Android phones or web cameras.

### 3. Critical QR Vulnerabilities & Flaws Identified

#### A. Signature Verification Bypass on Mobile App (Confirmed)
- The backend has a cryptographic verification endpoint: `/api/verify.php`.
- The helper `ApiService.verifyPassWithServer()` exists in Dart ([api_service.dart:541](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/services/api_service.dart#L541)).
- **However, `verifyPassWithServer` is NEVER called by any scanner screen.**
- The mobile scanner evaluates passes locally or via plain plate lookup. A driver presenting an altered QR code with a tampered expiration date will not have their cryptographic signature checked by the mobile scanner.

#### B. Fallback to Fabricated Pass on Unrecognized QR (Confirmed)
- In [VehicleLookupService.dart:91](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/services/vehicle_lookup_service.dart#L91), if the QR code does not match any registered vehicle or JSON schema, it calls `_generateVisitorPass(clean)`.
- **Impact:** An expired QR, a supermarket barcode, or a competitor pass is automatically converted into a valid-looking "Guest Driver" pass on the guard's screen.

#### C. Can an Entry QR Be Used for Exit?
- **Yes.** Registered vehicle passes are identical for entry and exit (static identity pass).
- In the case of visitor day passes, the same QR code is scanned on entry and on exit.
- **Flaw:** On exit, the mobile scanner does not verify whether the visitor pass was ever marked as entered. If a visitor generated a pass online, never visited, and someone scans it at exit, it logs an exit checkout.

#### D. Can a QR Code Be Scanned Multiple Times on Entry?
- If a registered vehicle is already marked "Inside Campus", scanning the QR again at the entrance gate still resolves successfully and displays the green `CLEARED (TO GO)` button.
- Tapping "CLEARED" creates a second "Entry Recorded" log row in `gate_logs` and overwrites `vehicles.last_entry_time`.
- The system does not prevent or warn the guard about double-entry ("Passback").

---

## Section H: Guard Perspective Analysis

To evaluate real-world guard usability, we simulated an actual officer standing at Gate 1 with vehicles waiting in line.

### Entrance Guard Experience
1. **Ambiguous Feedback on Flagged Vehicles:**
   - A student with a disciplinary warning approaches. The guard scans the decal.
   - The screen shows:
     - Header: `✔ SCANNED QR PASS VERIFIED` (Green)
     - Middle: `⚠ FLAGGED STUDENT: Parking Violation` (Red)
     - Footer: `CLEARED (TO GO)` (Green) vs `BLOCKED` (Red)
   - **Guard Dilemma:** "The system says verified at the top and gives me a green button, but there is a red box in the middle. Am I supposed to stop them or let them through?"
   - There is no prompt explaining what action security policy dictates.

2. **Accidental Clearance of Unknown Vehicles:**
   - A car with an unregistered pass approaches. The guard scans it.
   - Instead of an alert chime and a red screen saying "UNREGISTERED VEHICLE — DIRECT TO VISITOR LANE", the app smoothly transitions to a verification screen naming them "Visitor / Unregistered Pass" with a green `CLEARED` button.
   - The guard assumes the vehicle was pre-approved and presses `CLEARED`.

3. **No Driver Selection Enforcement:**
   - The vehicle has 3 registered drivers (Student, Mother, Father).
   - On the web gate monitor, the guard is forced to pick who is behind the wheel.
   - On the mobile app, it defaults to Driver #1. If the brother is driving, the guard can tap "CLEARED" without ever being prompted to confirm driver identity.

### Exit Guard Experience
1. **Missing Ingress Verification:**
   - The exit guard has no way of knowing if the vehicle exiting was actually logged in today or entered through an unmonitored opening.
2. **Item Check Bypass:**
   - When a visitor with declared cargo arrives at the exit gate, the mobile exit screen does not provide the mandatory item inspection checklist that exists on the web terminal.

---

## Section I: Administrator Perspective Analysis

We evaluated the Security Administrator attempting to maintain situational awareness from the Web Admin Portal.

```
                              Administrator View
      +---------------------------------------------------------------+
      |  Sidebar Badge:  [ 5 ] On Campus Now                          |
      +---------------------------------------------------------------+
      |  Dashboard KPI:  [ 3 ] Inside Campus   <--- CONFLICT!         |
      +---------------------------------------------------------------+
      |  "On Campus Now" Table:                                       |
      |   - ABC-123 (Student)                                         |
      |   - NDK-1234 (Visitor)                                        |
      |   - XYZ-789 (Employee)                                        |
      |   * Phantom mobile entry (ABC-999) is COMPLETELY MISSING!     |
      +---------------------------------------------------------------+
```

1. **Conflicting Headcounts on the Same Screen:**
   - In the sidebar navigation menu: `onCampusSidebarCount` shows **5**.
   - On the dashboard main card: `kpiInside` shows **3**.
   - **Cause:** The dashboard KPI calculates registered vehicles only (`state.vehicles.filter(...)`), ignoring visitors, while the sidebar uses the API total (`count($vehicles) + count($visitors)`).
   - **Admin Impact:** The administrator cannot determine how many vehicles are actually occupying campus parking spaces.

2. **Stale Dashboard Activity Charts:**
   - Gate activity charts, hourly trend graphs, and recent audit logs on the dashboard do not poll or refresh automatically.
   - If 30 cars pass through Gate 1 over an hour, the admin's screen remains unchanged until the admin presses F5.

3. **Inability to Revoke Passes for Visitors Inside Campus:**
   - In [visitors.js:103](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/web-app-admin/js/visitors.js#L103), the "Revoke" button is only rendered if `!p.isInside`.
   - If security detects a visitor engaging in prohibited activity on campus, the administrator cannot revoke their pass from the Visitor Day Passes view.

4. **Missing Fleet Status Category:**
   - When a vehicle exits, its status in `vehicles` table is set to `'Exited'`.
   - In the Vehicle Directory, filtering by status offers: "Inside", "Outside", "Blocked".
   - A vehicle with status `'Exited'` does not match `'Outside'`, creating classification discrepancies in directory searches.

---

## Section J: Missing Workflows

The audit identified critical operational workflows that are required for campus security but currently do not exist in the system:

1. **Anti-Passback Prevention Workflow:**
   - If Vehicle `ABC-123` is currently marked "Inside Campus", attempting to scan that same pass at an entrance gate should immediately trigger an "Anti-Passback Alert: Vehicle Already Recorded Inside".
   - *Current State:* Missing. The system logs duplicate entries without warning.

2. **Mandatory Guard Override for Flagged Entries:**
   - When a vehicle has an active disciplinary flag or warning, the system should require the guard to enter an officer PIN or reason before allowing entry.
   - *Current State:* Missing. Guard can tap `CLEARED (TO GO)` unconditionally.

3. **Visitor Cargo/Equipment Exit Reconciliation:**
   - On exit, the system must display the items recorded during entry (e.g., "40x Event Chairs") with checkboxes requiring the guard to confirm all items are present before authorizing exit.
   - *Current State:* Implemented on Web Gate Monitor, but completely bypassed and missing on Mobile Scanner.

4. **Automated Exit Pass Clearance for Student Portal:**
   - The student web portal should display a real-time status badge that changes from green ("Authorized Inside Campus") to neutral ("Outside Campus") immediately upon gate egress.
   - *Current State:* Missing real-time updates; requires manual browser refresh.

5. **Visitor Overstay Gate Hold:**
   - When a visitor attempts to exit after their pass validity hours have expired, the system should prompt the guard with an overstay alert and record an overtime flag.
   - *Current State:* Mobile app shows hardcoded 8-hour text and does not link to configurable settings.

---

## Section K: Unnecessary & Illogical Steps

1. **Unregistered Dummy Pass Generation in Mobile Scanner:**
   - *Illogical Step:* When an unrecognized QR code is scanned, the mobile app creates a fake `VehicleRecord` with `makeModelColor: 'Unregistered / Visitor Vehicle'` and routes it into the normal verification screen.
   - *Why It Is Wrong:* Unregistered vehicles must not be routed to the "Scanned QR Pass Verified" screen. They should be stopped immediately with a prompt: "Pass not found. Direct driver to Visitor Registration."

2. **Dual Pass Code Formats for Visitor Passes:**
   - *Illogical Step:* Mobile generates `NCST-VIS-2026-XXXX`, while backend generates `VP-YYYYMMDD-XXXX`.
   - *Why It Is Wrong:* Creates two competing pass identifiers for the same visitor transaction. The server should be the sole authority generating the pass code.

3. **Status Oscillation Between 'Outside' and 'Exited':**
   - *Illogical Step:* Schema default is `'Outside'`, but log action sets `'Exited'`.
   - *Why It Is Wrong:* Introduces two synonyms for the same physical state, breaking filter queries.

---

## Section L: Edge Cases & Error Handling Analysis

| Edge Case Scenario | Intended System Behavior | Actual Current Behavior | Operational Result |
|---|---|---|---|
| **Scanning Twice Within 5 Seconds** | Reject second scan as duplicate | `MobileScannerController` has `noDuplicates` detection, but once cleared, tapping scan again immediately accepts and logs a duplicate row in `gate_logs` | Multiple duplicate logs for single gate passage |
| **Banned Vehicle Attempts Entry** | Gate access denied; security alert triggered; vehicle held | On web gate monitor: correctly rejected (`VEHICLE_BANNED`). On mobile scanner: shows red flag text, but still offers green `CLEARED` button; guard can tap cleared and admit car | Banned vehicle can enter campus via mobile guard |
| **Exit Attempted for Vehicle Never Logged In** | Prompt guard: "No entry record found for this vehicle today. Log manual departure?" | Mobile exit scanner approves exit unconditionally ([exit_scanner_screen.dart:174](file:///c:/Users/ethan/Downloads/systemforinteg-feature-web-v2/systemforinteg-feature-web-v2/lib/features/scanner/screens/exit_scanner_screen.dart#L174)) | Phantom exit logs with invalid duration calculations |
| **Visitor Pass Scanned on Following Day** | Reject pass with "EXPIRED TEMPORARY PASS" | Backend `verify.php` and `logs.php` correctly return 403 `EXPIRED_TEMP`. However, if scanned by mobile app before calling API, screen displays card as valid | Guard admits expired visitor before API error is noticed |
| **Network Disconnection at Gate** | Queue logs locally; process scans against local database cache | Mobile app has `SyncQueueService` and `LocalCacheService`, which successfully store offline logs and replay them | Offline architecture works well, but caches stale banned lists |
| **Simultaneous Ingress and Egress** | Update vehicle to latest timestamp | Database transaction locks row in `logs.php`, but status is set to whichever transaction commits last | Last write wins; race condition can leave status as "Inside" |

---

## Section M: Severity & Prioritized Remediation Roadmap

The discovered issues are prioritized below strictly by their **impact on campus physical security, data accuracy, and user clarity**:

```
================================================================================
PRIORITY 1: CRITICAL SECURITY & DATA LOGIC DEFECTS (Address First)
================================================================================
1. [CRITICAL] Disable Unregistered QR Fallback in Mobile Scanner
   - File: lib/services/vehicle_lookup_service.dart (Line 91)
   - Problem: Unknown QR generates fake guest record and displays green verified card.
   - Required Logic: If QR cannot be verified against registered vehicles or valid
     signed visitor passes, return null and show an explicit "UNRECOGNIZED PASS" error.

2. [CRITICAL] Enforce Server Verification in Mobile Entrance Scanner
   - File: lib/features/scanner/screens/qr_scanner_screen.dart
   - Problem: Scanner never calls ApiService.verifyPassWithServer(), bypassing HMAC
     signatures, bans, suspensions, and tamper checks.
   - Required Logic: Invoke /api/verify.php on every scan before rendering decision card.

3. [CRITICAL] Enforce Gate Registration Check in Backend logs.php
   - File: backend/api/logs.php (Line 181)
   - Problem: if (!$vehicle && !$visitor && !$isScanner) skips check for mobile app,
     allowing unverified mobile logs to enter gate_logs without DB registration.
   - Required Logic: Remove !$isScanner exemption for entry approvals.

================================================================================
PRIORITY 2: HIGH SEVERITY WORKFLOW & SYNCHRONIZATION DEFECTS
================================================================================
4. [HIGH] Fix Mobile Dashboard Inside Count & Duplicate Entry Display
   - File: lib/features/dashboard/screens/dashboard_screen.dart (Lines 48 & 81)
   - Problem: Prepending exit logs leaves old entry logs active, preventing inside
     count from decrementing and showing duplicate rows for the same vehicle.
   - Required Logic: Update the existing vehicle entry state in the active list upon
     exit, or compute inside count from current vehicle states rather than raw logs.

5. [HIGH] Harmonize Web Admin Dashboard KPI Count with "On Campus Now"
   - File: web-app-admin/js/app.js (Line 359) vs web-app-admin/js/oncampus.js
   - Problem: Dashboard KPI ignores visitors, showing a lower count than the sidebar.
   - Required Logic: Update app.js insideCount to include both active vehicles and
     active day visitors, matching oncampus.php.

6. [HIGH] Unify Visitor Pass Code Generation Between Mobile and Server
   - File: lib/features/visitor/screens/visitor_registration_screen.dart (Line 782)
     and backend/api/visitors.php (Line 176)
   - Problem: Mobile generates NCST-VIS-..., while server generates VP-....
   - Required Logic: Mobile must adopt server-generated passCode upon pass creation.

7. [HIGH] Disable "CLEARED" Button on Banned / Suspended Vehicles in Mobile Scanner
   - File: lib/features/scanner/screens/qr_scanner_screen.dart & bottom_decision_bar.dart
   - Problem: Prominent green "CLEARED (TO GO)" button is active even for banned cars.
   - Required Logic: If vehicle is banned, disable or remove the green button and require
     security escalation.

================================================================================
PRIORITY 3: MEDIUM SEVERITY USER CLARITY & PROCESS DEFECTS
================================================================================
8. [MEDIUM] Require Egress Check That Vehicle Was Inside Campus
   - File: lib/features/scanner/screens/exit_scanner_screen.dart (Line 174)
   - Problem: Allows exit approvals for vehicles that never entered campus.
   - Required Logic: Validate vehicle status is "Inside Campus" before clearing exit.

9. [MEDIUM] Enforce Visitor Item Reconciliation on Mobile Scanner
   - File: backend/api/logs.php (Line 191) & mobile exit scanner
   - Problem: Mobile scanner exempt from verifying visitor equipment.
   - Required Logic: Show item checklist on mobile exit scanner for visitor passes.

10. [MEDIUM] Standardize Status Terminology: 'Outside' vs 'Exited'
    - File: backend/api/logs.php (Line 202) & database schema
    - Problem: System writes 'Exited' to vehicles table, contradicting 'Outside' default.
    - Required Logic: Use 'Outside' canonically across database, API, and UI.

11. [MEDIUM] Allow Admin to Revoke Passes for Visitors Currently Inside Campus
    - File: web-app-admin/js/visitors.js (Line 103)
    - Problem: Revoke button disabled when p.isInside is true.
    - Required Logic: Allow revoking on-campus passes, flagging them for gate security hold.

================================================================================
PRIORITY 4: LOW SEVERITY POLISH & COSMETIC DEFECTS
================================================================================
12. [LOW] Remove Hardcoded 8-Hour Text in Mobile Exit Scanner
    - File: lib/features/scanner/screens/exit_scanner_screen.dart (Line 160)
    - Problem: Hardcoded "8-hour limit" text ignores dynamic validity setting.
    - Required Logic: Use LocalCacheService.getVisitorPassValidityHours().

13. [LOW] Add Auto-Refresh or Polling to Web Admin Dashboard
    - File: web-app-admin/js/app.js (Line 3620)
    - Problem: Dashboard activity charts remain static until page reload.
    - Required Logic: Implement periodic refresh timer matching oncampus.js.

14. [LOW] Student Portal Status Display Polish
    - File: web-app-student/js/app.js (Line 223)
    - Problem: Displays "Campus status: Exited" instead of "Outside Campus".
    - Required Logic: Map status to user-friendly badge.
```

---

## Conclusion

The SecurePark system has a robust technical foundation: SQLite/shared-preferences offline caching in Flutter, HMAC-SHA256 signature generation in PHP, and relational integrity in MySQL.

However, the real-world operational logic currently breaks down at the gate interface:
1. **The mobile scanner is overly permissive**, inventing valid guest records for invalid QR codes and allowing banned vehicles to be cleared with a green button.
2. **The mobile dashboard confuses audit logs with current campus inventory**, resulting in exit logs being recorded as duplicate vehicles and preventing the inside vehicle count from decreasing.
3. **The web admin interface presents contradictory information**, displaying different inside vehicle counts between the sidebar and the dashboard KPI.

Resolving these issues does not require architectural redesign. It requires:
- Removing the synthetic pass fallback in `VehicleLookupService.dart`.
- Connecting `QrScannerScreen` to the existing `ApiService.verifyPassWithServer()` endpoint.
- Correcting the state calculation in `DashboardScreen.dart`.
- Harmonizing the headcount metric in `app.js`.

*End of Audit Report.*
