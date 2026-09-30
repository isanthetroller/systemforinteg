# Comprehensive Multi-Layer State Transition, Unexpected Choice, CRUD & Complete System Behavior Test Plan

**Document ID:** `ST-PLAN-2026-V1`  
**System:** Go-on National College of the Philippines (GNCP) Academic & Enrollment Management System  
**Test Scope:** End-to-End State Transitions, Dynamic Validation, Dependency Resets, Workstation Workflows, Admin/Scheduler/Professor/Student CRUD, Student LMS, and Multi-Session Concurrency  
**Target Environment:** Local Full Stack (Apache 2.4, MariaDB 10.4, PHP 8.2, Vue 3, Playwright Test Harness)  
**Base URL:** `http://localhost/systemtest`

---

## 1. Executive Summary & Testing Philosophy

The GNCP platform has evolved through multiple modular milestones (Student LMS Subjects redesign, Academic Scheduler workstation, Employee Gateway, Single-Active Session Guard, and Department-Scoped Faculty Management). 

The primary objective of this testing phase is **NOT** merely to verify the "happy path" (valid input $\rightarrow$ click submit $\rightarrow$ successful confirmation). Rather, it is to rigorously probe:
1. **Dynamic State Transitions & "Change of Mind":** When a user makes choice $A$, advances through wizard steps, changes their mind to choice $B$, does the system cleanly purge stale dependent state, re-validate input constraints, and persist only the final valid selection?
2. **Boundary & Unexpected Choices (e.g. ALS $\rightarrow$ BSIT):** When non-traditional applicants (Alternative Learning System, Transferees, Returning Students) choose specialized degree programs, does the system enforce prerequisites, populate appropriate requirement checklists, calculate correct tuition/lab fees, and allow non-destructive recovery if rejected?
3. **Cascading Relational Integrity:** When entities are mutated across departments, programs, subject offerings, sections, professors, and enrollments, do changes cascade consistently without orphan records, ghost classes in student LMS, or conflicting room/schedule assignments?
4. **Resilience & Idempotence:** Does the application safely handle double-clicks, duplicate submissions, back/forward browser navigation, page refreshes mid-workflow, cross-tab mutations, and stale concurrent updates?

---

## 2. System Architecture & Workstation Dependency Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             ADMINISTRATIVE HUB                              │
│         (Departments, Programs, Subjects, Curriculum, Terms, Users)         │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ACADEMIC SCHEDULER WORKSTATION                         │
│               (Sections, Offerings, Room/Time Matrices, Load)               │
└───────────────────┬─────────────────────────────────────┬───────────────────┘
                    │                                     │
                    ▼                                     ▼
┌──────────────────────────────────────┐  ┌───────────────────────────────────┐
│           FACULTY PROFESSOR          │  │       STUDENT ENROLLMENT          │
│ (My Classes, Schedule, LMS, Materials)│  │   (Pre-Reg, Registrar, Advising,  │
└───────────────────┬──────────────────┘  │    Clinic, Cashier, IT Promotion) │
                    │                     └─────────────────┬─────────────────┘
                    │                                       │
                    ▼                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                 STUDENT LMS                                 │
│             (Subjects Grid, Classroom View, Materials, Updates)             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Test Matrix by Phase

### Phase 1: The Alternative Learning System (ALS) $\rightarrow$ BSIT Deep-Dive
* **Scenario ID:** `TEST-ALS-01`
* **Workflow:**
  1. Open Online Pre-Registration (`/enrollment-system/index.html`).
  2. Step 1: Select Admission Type = `FRESHMAN`, College = `COIT`, Program = `BSIT`, NSTP = `CWTS`.
  3. Step 2: Input Personal Details (Name, Contact, Birthdate $\ge$ 15 years).
  4. Step 3: Choose Education Pathway = `ALS` (Alternative Learning System). Input ALS Community Learning Center name.
  5. Validate automatic setting of `juniorHighSchool = 'N/A (ALS)'`, `seniorHighSchool = 'Alternative Learning System (ALS)'`, and `shsTrack = 'ALS'`.
  6. Step 4 & 5: Complete Medical Pre-Screening and Payment Mode selection.
  7. Step 6: Verify Review screen displays ALS-specific checklist:
     - *ALS Certificate of Rating (COR) with Passing Marks (Original & Photocopy)*
     - *ALS Certificate of Completion (Original)*
     - *PSA Birth Certificate (Photocopy)*
     - *2 pieces recent 2x2 color pictures*
  8. Submit and verify creation in `pre_enrollments` with `shs_track = 'ALS'` and `course_code = 'BSIT'`.
  9. Verify Downstream Station handling: Registrar document review, Advising curriculum mapping, Cashier assessment computation, and IT Center student promotion.

### Phase 2: Change-of-Mind & Dependency Reset Testing
* **Scenario ID:** `TEST-RESET-01` (Program Switch):
  - User selects College `COIT` $\rightarrow$ `BSIT`.
  - Advances to Step 2 $\rightarrow$ returns to Step 1 $\rightarrow$ switches College to `COBA` (Business Administration).
  - Verify `courseCode` resets immediately, preventing the invalid state `COBA + BSIT`.
  - Re-select `BSBA` $\rightarrow$ advance $\rightarrow$ verify Step 5 Fee calculation updates tuition/lab fees from BSIT (includes ₱3,000 lab) to BSBA (₱0 lab fee).
* **Scenario ID:** `TEST-RESET-02` (Education Pathway Switch):
  - In Step 3, user selects `ALS` $\rightarrow$ inputs ALS CLC name.
  - Changes mind $\rightarrow$ selects `REGULAR` (Senior High School).
  - Verify `seniorHighSchool` and `shsTrack` are cleared and required validation re-engages for standard SHS track.
* **Scenario ID:** `TEST-RESET-03` (Admission Type Switch):
  - User selects `FRESHMAN` $\rightarrow$ inputs educational background.
  - Returns to Step 1 $\rightarrow$ changes to `TRANSFEREE`.
  - Verify Step 3 dynamic validation shifts to mandate `previousCollege` and replaces SHS requirements with *Honorable Dismissal* and *Transcript of Records (TOR)*.
* **Scenario ID:** `TEST-RESET-04` (Section & Subject Switch in Scheduler):
  - Scheduler selects Section `BSIT-1A` $\rightarrow$ loads offerings $\rightarrow$ switches to `BSIT-2A`.
  - Verify UI immediately unmounts `BSIT-1A` subject cards and fetches fresh `BSIT-2A` catalog without stale professor cards.

### Phase 3: Comprehensive Entity CRUD under Unexpected & Boundary Conditions
1. **Professors (`station_users` + `professors`):**
   - Create valid professor linked to `CCS` department.
   - Attempt duplicate creation with existing username (verify HTTP 400 rejection).
   - Attempt creation with missing required fields (verify form blocking).
   - Admin reassigns professor department from `CCS` to `CBA`.
   - Verify impact on existing scheduled classes: does scheduler flag a warning or preserve existing section assignments?
   - Deactivate professor $\rightarrow$ attempt login (verify HTTP 403 / 401 access rejection).
   - Re-enable professor $\rightarrow$ verify immediate login restoration.
2. **Academic Scheduler (`subject_sections` + conflict engine):**
   - Create valid schedule for subject section.
   - Attempt to assign a professor to overlapping time slot on identical day (verify `ScheduleConflictService` rejects with double-booking error).
   - Attempt to schedule two sections in identical room during overlapping hours (verify room collision rejection).
   - Test one-click `auto_assign` deterministic engine: verify unassigned subjects receive conflict-free professor allocations.
3. **Class Sections (`sections`):**
   - Create section with capacity 40.
   - Assign enrolled students until limit $\rightarrow$ test whether IT Center promotion respects or decrements section capacity.
   - Admin changes section code: verify downstream `subject_sections` and student section tags update consistently.
4. **Bulletin Announcements (`announcements`):**
   - Professor creates subject-specific announcement tagged with `subject_code = 'IT101'`.
   - Verify student enrolled in `IT101` sees announcement on subject page.
   - Verify student enrolled only in `IT102` does NOT see the announcement.
   - Professor updates announcement text $\rightarrow$ verify student view reflects update immediately upon refresh.
   - Professor deletes announcement $\rightarrow$ verify announcement unmounts from student classroom feed.
5. **LMS Course Materials (`materials` / uploaded files):**
   - Professor uploads PDF file to Personal Drive $\rightarrow$ publishes to `IT101`.
   - Verify student in `IT101` can view and download the material.
   - Professor unpublishes / deletes material $\rightarrow$ verify material disappears from student portal.
   - Attempt upload of disallowed file types (`.exe`, `.bat`, `.php`, `.js`) $\rightarrow$ verify strict rejection by MIME and extension guard.

### Phase 4: Full Multi-Stage Enrollment Pipeline Transitions
* **States Verified:**
  $$\text{PRE\_REGISTERED} \longrightarrow \text{VERIFIED} \longrightarrow \text{ADVISED} \longrightarrow \text{MEDICAL\_CLEARED} \longrightarrow \text{PAID} \longrightarrow \text{ENROLLED}$$
* **Edge Transitions:**
  - Registrar rejects applicant $\rightarrow$ status becomes `REJECTED`.
  - Can a rejected applicant proceed to Advising or Clinic? (Verify stations block rejected students).
  - Can Registrar re-open / approve a rejected applicant? Verify state transitions and audit logging.
  - What happens when a student changes their NSTP choice at the Advising desk? Verify frozen assessment snapshot in Cashier reflects updated NSTP choice.
  - Cashier processes partial installment payment $\rightarrow$ verify ledger balance and Official Receipt generation.
  - IT Center captures photo and promotes student $\rightarrow$ verify migration to `students` table, generation of permanent `YYYY-XXXX` ID, creation of institutional email, and student portal access activation.

### Phase 5: Student LMS Real-Time Reflection & Subject Scoping
* Verify Google Classroom-style grid renders only enrolled subjects.
* Opening subject opens isolated classroom view (Announcements feed + Course Materials).
* Cross-subject data leak verification: materials and announcements for other courses must not appear.
* Admin re-assigns student to another section $\rightarrow$ verify Student Portal subjects, teachers, and schedules update to the new section's offerings.

### Phase 6: Session Security, Concurrency & Backward Navigation
* Single-Active Session Token Enforcement:
  - User logs in on Browser $A$.
  - Same account logs in on Browser $B$.
  - Browser $A$ attempts next action $\rightarrow$ verify immediate HTTP 401 session invalidation and redirection to login with alert notice.
* Backward / Forward Navigation:
  - Fill steps 1–4 of pre-enrollment $\rightarrow$ browser Back button $\rightarrow$ forward $\rightarrow$ verify draft preservation and state validity.
  - Page refresh on step 5 $\rightarrow$ verify state restored via `localStorage` draft cache.
* Duplicate Click Protection:
  - Rapid double-click on payment or enrollment submission $\rightarrow$ verify button disables immediately and server idempotency prevents duplicate records.

---

## 4. Test Execution & Reporting Artifacts

1. `state_transition_test_plan.md` *(This comprehensive plan)*
2. `crud_state_transition_matrix.md` *(Full Entity vs Operation vs State Change Matrix)*
3. `final_state_transition_test_report.md` *(Empirical Test Execution Results, Playwright suite output, and Pass/Fail telemetry)*
4. `system_functional_behavior_documentation.md` *(Detailed, plain-language operational documentation explaining user roles, actions, state changes, and cross-module effects)*
