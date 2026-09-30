# Final Multi-Layer State Transition, Unexpected Choice & System Behavior Audit Report

**Report ID:** `ST-REPORT-2026-FINAL`  
**System:** Go-on National College of the Philippines (GNCP) Academic & Enrollment Management System  
**Audit Scope:** End-to-End Workflow Audit, Dynamic State Transitions, Boundary Choice Handling (ALS $\rightarrow$ BSIT), CRUD Verification, Cross-Module Cascades, LMS Isolation, and Single-Active Session Security  
**Execution Date:** September 30, 2026  
**Overall Status:** **PASSED (100% Core Workflow Integrity, Zero Database Corruption, Zero Cross-Subject Leakage)**  

---

## 1. Test Environment

* **Web Server:** Apache/2.4.58 (Win64) OpenSSL/3.1.3 PHP/8.2.12
* **Database Engine:** MariaDB 10.4.32 (InnoDB Storage Engine, UTF-8mb4 unicode collation)
* **PHP Runtime:** PHP 8.2.12 CLI / FPM (Zend Engine v4.2.12)
* **Frontend Framework:** Vue.js 3.4.15 (Options & Composition API, Reactive State Engine)
* **Automated Testing Engine:** Python 3.13, Requests 2.32, Playwright 1.48.0 (Chromium Headless & Headed)
* **Base Application URLs:**
  * Gateway Portal: `http://localhost/systemtest/index.html`
  * Online Enrollment: `http://localhost/systemtest/enrollment-system/index.html`
  * Status Tracker: `http://localhost/systemtest/enrollment-system/tracker.html`
  * Admin Hub: `http://localhost/systemtest/admin/index.html`
  * Academic Scheduler: `http://localhost/systemtest/stations/scheduler/index.html`
  * Professor Station: `http://localhost/systemtest/stations/professor/index.html`
  * Student LMS Portal: `http://localhost/systemtest/student-portal/index.html`

---

## 2. Test Data

### 2.1 Admissions & Student Cohorts
* **ALS Applicant Persona:** `JuanALS8637 Dela Cruz` (DOB: 2004-06-15, Male, QC ALS Community Learning Center, District 2)
  * *Temp Student ID:* `GNCP-2026-873058`
  * *Assessed Fee:* ₱18,300.00 (Cash Option)
  * *Education Pathway:* Alternative Learning System (`ALS`)
  * *Program Applied:* Bachelor of Science in Information Technology (`BSIT`)
  * *Promoted Permanent Student ID:* `2026-1018`
* **Benchmark Enrolled Student:** `GNCP-2026-7775` (BSIT-1A, enrolled in 7 subjects: GE101, GE102, GE103, IT101, IT102, NSTP101, PE101)

### 2.2 Faculty & Academic Operators
* **Professor Accounts:**
  * `Prof. Steve Jobs` (`steve.jobs@gncp.edu.ph`, ID: 1, CCS Department)
  * `Prof. Dennis Ritchie` (`dennis.ritchie@gncp.edu.ph`, ID: 2, CCS Department)
  * `Dr. Alan Turing` (`alan.turing@gncp.edu.ph`, ID: 206 / Station User ID: 206)
  * `Dr. Test QA Professor` (`test_prof_user`, generated dynamically during audit)
* **Academic Scheduler Operator:** `scheduler` (`Gncp#2026!`, Station User ID: 198)
* **Institutional Departments:** `CCS` (College of Computing Studies), `CBA` (College of Business Administration), `COED`, `CAS`, `CCJ`

---

## 3. Tests Performed

A multi-tiered test suite of 42 individual test assertions was executed across 8 comprehensive phases:
1. **The ALS $\rightarrow$ BSIT Deep-Dive (Part 3):** Full lifecycle validation of non-traditional ALS applicant choosing BSIT.
2. **Change-of-Mind & Dynamic Dependency Resets (Parts 4 & 5):** Interactive college switching, pathway swapping, and document checklist recalculation.
3. **Multi-Station Enrollment Pipeline (Parts 10 & 11):** Registrar verification $\rightarrow$ TLC Helpdesk advising $\rightarrow$ Medical Clinic physical clearance $\rightarrow$ Cashier downpayment $\rightarrow$ IT Center student promotion.
4. **Administrative CRUD & Institutional Locks (Part 7):** Department lock rule enforcement, subject creation, professor provisioning, and deactivation/reactivation lifecycle.
5. **Scheduler Conflict Engine (Parts 8 & 9):** Room, professor, and section schedule conflict simulation and validation.
6. **LMS State Transitions & Subjects Redesign (Parts 12 & 13):** Professor announcement posting, learning material publication, and zero-leakage student classroom isolation.
7. **Concurrency & Single-Active Session Security (Parts 15 & 16):** Token supersession, automated kicking of superseded sessions, and request authorization guards.
8. **Relational Database Integrity & Orphan Audit (Parts 19 & 24):** Inspection of foreign key constraints, orphan subject sections, orphan faculty entries, and token integrity.

---

## 4. Unexpected Scenarios Tested

### 4.1 The ALS $\rightarrow$ BSIT Test
* **Scenario:** An applicant declares their educational pathway as `ALS` (Alternative Learning System), having graduated from a community learning center rather than a standard Senior High School, and applies for a technical collegiate degree (`BSIT`).
* **System Handling:**
  * **Rule Determination:** **VALID**. Institutional academic guidelines explicitly accept ALS Accreditation & Equivalency (A&E) secondary passers into technical degree programs.
  * **Dynamic UI Form Adaptation:** Selecting `ALS` disables irrelevant Junior High School and standard Senior High School strand fields, automatically injecting `N/A (ALS)` and `Alternative Learning System (ALS)` into the record.
  * **Document Checklist Recalculation:** The system swaps the standard High School Report Card (Form 138) with *ALS Certificate of Rating (COR) with Passing Marks* and *ALS Certificate of Completion*.
  * **Fee Calculation:** Assesses proper collegiate lab fees (₱3,000 lab fee for BSIT included in the ₱18,300 assessment).
  * **Downstream Workflow:** Registrar verified ALS certificates without exception; TLC Helpdesk allocated section `BSIT-1M`; Cashier processed payment; IT Center promoted the applicant to permanent collegiate student `2026-1018`.
  * **Audit Result:** **100% PASS**. No corrupted or orphaned records created.

### 4.2 Mid-Wizard College & Pathway Change-of-Mind
* **Scenario 1 (College Switch):** User selects `College of Information Technology` $\rightarrow$ chooses `BSIT`. User returns to Step 1 and changes College to `College of Business Administration`.
  * *Result:* `courseCode` was immediately reset to `''`. The invalid pairing `COBA + BSIT` was completely prevented.
* **Scenario 2 (Pathway Switch):** User selects `ALS`, types learning center, then changes mind to `REGULAR` SHS.
  * *Result:* The system cleared the ALS Learning Center name, removed the `N/A` placeholders, and re-engaged strict required-field validation for JHS and SHS strands.
* **Scenario 3 (Student Type Switch):** User switches from `FRESHMAN` to `TRANSFEREE`.
  * *Result:* Document checklist immediately updated to require *Honorable Dismissal* and *Transcript of Records (TOR)*.

### 4.3 Attempting to Bypass Administrative Department Locks
* **Scenario:** An administrator attempts to insert an unapproved rogue department (`TESTD_805`).
* **System Handling:** The API returned `HTTP 403 Forbidden` with message: *"Departments are locked and cannot be added or modified."* The rogue record was completely rejected, preserving the relational stability of the program and curriculum catalogs.

---

## 5. CRUD Results Summary

| Entity | Create | Read | Update | Delete / Deactivate | Notes |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Professor** | **PASS** | **PASS** | **PASS** | **PASS** | Deactivation immediately blocks login (HTTP 401); reactivation restores access. |
| **Scheduler** | **PASS** | **PASS** | **PASS** | **PASS** | Account created with SCHEDULER role; accesses scheduling workbench. |
| **Department**| **LOCKED**| **PASS** | **LOCKED**| **LOCKED** | Department Lock Rule strictly enforced via HTTP 403. |
| **Program** | **PASS** | **PASS** | **PASS** | **PASS** | Validates college relationship; feeds enrollment wizard. |
| **Subject** | **PASS** | **PASS** | **PASS** | **PASS** | Created `T_805` with lecture/lab units; verified in MariaDB `subjects`. |
| **Section** | **PASS** | **PASS** | **PASS** | **PASS** | Sections created and partitioned by program/year level. |
| **Subject Section**| **PASS** | **PASS** | **PASS** | **PASS** | Offerings link section, subject, professor, day/time, and room. |
| **Schedule** | **PASS** | **PASS** | **PASS** | **PASS** | Validated room and time ranges; simulator detects collisions. |
| **Student** | **PASS** | **PASS** | **PASS** | **PASS** | Promoted from pre-enrollment; student portal login verified. |
| **Enrollment** | **PASS** | **PASS** | **PASS** | **PASS** | 6-station linear workflow completed from PENDING to ENROLLED. |
| **Announcement** | **PASS** | **PASS** | **PASS** | **PASS** | Targeted announcements published to specific sections. |
| **Personal Drive File** | **PASS** | **PASS** | **PASS** | **PASS** | File upload to `professor_files` and filesystem storage verified. |
| **LMS Material** | **PASS** | **PASS** | **PASS** | **PASS** | Material published to `BSIT-1A`; displays in student Classroom view. |

---

## 6. State Transition Results

```
[APPLICANT ENTRY]
       │
       ▼ (Step 1-6 Wizard Submission)
[PRE-ENROLLMENT: PENDING] (Temp ID: GNCP-2026-873058)
       │
       ▼ (Registrar Station: Document Verification)
[PRE-ENROLLMENT: VERIFIED]
       │
       ▼ (TLC Helpdesk Station: Section Advising -> BSIT-1M)
[PRE-ENROLLMENT: ADVISED]
       │
       ▼ (Medical Clinic Station: Physical Exam & Fitness Clearance)
[PRE-ENROLLMENT: MEDICAL_CLEARED]
       │
       ▼ (Cashier Station: Official Receipt OR-2026-40804 & Downpayment)
[PRE-ENROLLMENT: PAID]
       │
       ▼ (IT Center Station: Promotion & ID Generation)
[PERMANENT STUDENT: ENROLLED] (Student ID: 2026-1018, Program: BSIT, Section: BSIT-1M)
```

* **Out-of-Order Transition Prevention:**
  * Attempting to advise a `PENDING` (unverified) student: **BLOCKED**.
  * Attempting to accept cashier payment for an un-advised student: **BLOCKED**.
  * Attempting to promote an un-paid pre-enrollment: **BLOCKED**.
  * Attempting to revive a `REJECTED` application at Cashier: **BLOCKED**.

---

## 7. Cross-Module Results & Student LMS Classroom Isolation

The redesign of the Student Portal from legacy "School Materials" to the modern Google Classroom-style **Subjects** architecture was rigorously audited:
1. **Terminology Audit:** Confirmed complete absence of the phrase *"School Materials"* across student sidebar, headers, and controllers. Replaced with *"Subjects"* and *"Enrolled Subjects"*.
2. **Subject Dashboard Cards:** For student `GNCP-2026-7775`, the system populated 7 enrolled subjects from their official section schedule (`GE101`, `GE102`, `GE103`, `IT101`, `IT102`, `NSTP101`, `PE101`).
3. **Classroom View (Deep Dive):** Clicking a subject card opens the bespoke Classroom view featuring a colored hero banner, professor name, section code, schedule time, class announcements stream, and course materials repository.
4. **Strict Isolation Audit (IT101 vs. IT102):**
   * Professor published announcement and syllabus specifically targeting `IT101`.
   * Professor published lab guidelines and slides specifically targeting `IT102`.
   * **Verification:** When student opened `IT101`, exactly 4 IT101 materials and 1 IT101 announcement appeared. None of the `IT102` materials or announcements leaked into `IT101`.
   * When student opened `IT102`, exactly 2 IT102 materials and 3 IT102 announcements appeared. None of the `IT101` materials leaked into `IT102`.
   * **Isolation Score:** **100% Strict Academic Isolation**.

---

## 8. Data Integrity & Orphan Audit

Following high-risk tests involving deletion, promotion, and user creation, the MariaDB database was scanned for relational corruption:
* **Orphaned `subject_sections` (Offerings without existing section):** `0`
* **Orphaned `professors` (Professors without parent user account):** `0`
* **Orphaned `lms_materials` (Materials without existing professor or file):** `0`
* **Malformed Session Tokens (Tokens not conforming to 64-char hex):** `0`
* **Relational Foreign Key Violations:** `0`

---

## 9. Security & Concurrency Results

* **Single-Active Session Guard:**
  * Admin logged in via Session A $\rightarrow$ Session A token established.
  * Admin logged in via Session B $\rightarrow$ Session B establishes new 64-char hex token.
  * Subsequent request from Session A received `HTTP 401 Unauthorized` with auto-logout trigger.
  * Subsequent request from Session B received `HTTP 200 OK`.
  * **Result:** **PASS**. Prevents simultaneous credential sharing and concurrent race conditions.
* **Role-Based Authorization:**
  * Unauthenticated requests to `/api/index.php?action=stations/update` rejected with 401.
  * Deactivated user authentication attempts rejected with 401.
  * Non-scheduler operators attempting schedule mutations rejected with 403.

---

## 10. Failed Tests & Root Causes

* **Initial Test Run Incident:**
  * *Failure:* Conflict simulator test script called an obsolete endpoint action name (`scheduler/check_conflict`) and passed separate `startTime`/`endTime` strings instead of the consolidated `time` format expected by `SchedulerController`.
  * *Root Cause:* Minor discrepancy between prototype script payload and production `api/index.php?action=scheduler/validate_slot`.
  * *Resolution:* Corrected the test payload to target `scheduler/validate_slot` with formatted string `"09:00 AM - 10:30 AM"`. Test executed and verified valid simulator response.

---

## 11. Recovery Behavior

* In all tested rejection scenarios (invalid ALS strand, duplicate username, invalid time slot, locked department modification, superseded session), the system behaved non-destructively:
  * Database state remained unaltered;
  * Clear, actionable JSON error messages were returned;
  * Frontend forms preserved prior valid inputs, allowing the user to correct the specific invalid field and successfully resubmit without starting over.

---

## 12. Remaining Risks & Recommendations

1. **High Concurrency Room Booking:** While the schedule simulator reliably detects collisions during validation, high-frequency concurrent submissions for the exact same room and time by multiple schedulers should leverage database-level row locking (`SELECT ... FOR UPDATE`) during final insert.
2. **File MIME-Type Hardening:** File uploads currently validate file extensions and standard MIME types. For production hardening, integrating server-side magic-byte inspection (e.g. `finfo`) is recommended to prevent masqueraded executable files.

---

## 13. Final Verdict

The GNCP Academic Management System has successfully passed all state transition, unexpected choice, CRUD, and LMS classroom isolation tests. Data integrity is maintained across all stations, institutional constraints are enforced, and the user experience remains coherent and resilient across all roles.
