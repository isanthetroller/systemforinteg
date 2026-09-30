# Full CRUD and Multi-Layer State Transition Matrix

**System:** Go-on National College of the Philippines (GNCP) Academic & Enrollment Management System  
**Audit Phase:** Comprehensive State Transition, Unexpected Choice, CRUD & Cross-Module Behavior Audit  
**Document ID:** `CRUD-MATRIX-2026-V1`  
**Execution Environment:** Local Full Stack (Apache 2.4, MariaDB 10.4, PHP 8.2, Vue 3, Playwright Test Harness)  

---

## 1. Master CRUD and State Transition Matrix

The table below outlines each primary core entity, detailing behavior across standard CRUD lifecycles, unexpected inputs, internal state mutations, and resulting cross-module effects.

| Entity | Create | Read | Update | Delete/Deactivate | Unexpected Input | State Change | Cross-Module Effect |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Professor** | Admin creates via User Management modal (`role: PROFESSOR`). Persisted in `station_users` and linked to `professors` with department assignment. Default temporary password generated, `must_change_password=1`. | Admin, Schedulers, and Registrar read faculty directory. Filterable by department, status, and active teaching loads. | Admin updates full name, email, department, or active status. Profile edits reflect across directory immediately. | Soft delete via `status='DEACTIVATED'`. Active session token cleared immediately; existing JWT/cookie rejected with HTTP 401. | Duplicate username or email rejected with descriptive 400 error. Department reassignment with active assigned classes triggers conflict warning. | `ACTIVE` $\leftrightarrow$ `DEACTIVATED`. Transition terminates active sessions and blocks station access. | Schedulers cannot assign deactivated faculty to new sections. Existing assigned schedules remain visible but display an "Inactive Faculty" alert. Student LMS preserves posted historical materials. |
| **Scheduler** | Admin creates operator account (`role: SCHEDULER`) via Admin User Directory or dedicated Operator modal. Account stored in `station_users`. | System reads role upon authentication. Schedulers view room schedules, cohort grids, faculty directories, and teaching load summaries. | Admin updates user credentials or workstation permissions. Scheduler can update own profile. | Admin toggles status to `DEACTIVATED` or `SUSPENDED`. Single-active session engine kicks existing active browser session. | Attempting to create duplicate scheduler username returns 400. Submitting malformed session tokens triggers immediate auth rejection. | `ACTIVE` $\leftrightarrow$ `DEACTIVATED`. Governs login capability and write access to schedule workbench. | Deactivation terminates scheduling authority without altering existing published section schedules or classroom allocations. |
| **Department** | Pre-seeded with institutional colleges: `CCS` (Computing Studies), `CBA` (Business Administration), `COED` (Education), `CAS` (Arts & Sciences), `CCJ` (Criminal Justice). | Visible in program dropdowns, user creation, professor tagging, and curriculum mapping. | System enforces **Department Lock Rule**: institutional departments are immutable. | Deletion blocked by API with HTTP 403 Forbidden. Preserves relational integrity of programs, faculty, and curricula. | Attempting to `POST` a new rogue department code returns HTTP 403: *"Departments are locked and cannot be added or modified."* | Static / Immutable state. Prevents structural drift in college hierarchy. | Protects programs, faculty affiliations, and subject assignments from dangling foreign keys and unmapped colleges. |
| **Program** | Admin creates degree programs (e.g., `BSIT`, `BSBA`, `BEED`) mapped to parent department with degree code, title, and year levels. | Read by applicant registration wizard, registrar evaluation, scheduler cohort filters, and student portal. | Admin modifies program title, description, or department affiliation. Changes propagate to course lists. | Soft-deactivation supported. Active programs cannot be deleted while active curricula or enrolled students exist. | Submitting duplicate program code returns 400. Incompatible program-department pairings rejected by backend validation. | `ACTIVE` $\leftrightarrow$ `INACTIVE`. Governs availability in applicant admission dropdowns. | If a program is deactivated, applicants cannot choose it during registration. Existing student cohorts proceed without curriculum interruption. |
| **Subject** | Admin creates course catalog entries: course code, title, lecture units, lab units, lab fees, and prerequisites. | Catalog accessible to Admin, Registrar, Schedulers, Professors, and Student Curriculum trackers. | Admin updates unit counts, description, or lab fees. Updates do not retroactively alter assessed fees of completed enrollments. | Deletion blocked if subject is referenced in active section offerings or student grade records. | Negative lecture/lab units rejected with 400 validation error. Special character injection sanitized safely. | `ACTIVE` catalog status. | Changes to subject lab fees dynamically alter fee assessments for future pre-registrations and cashier recalculations. |
| **Section** | Admin or Scheduler defines academic sections per program and year level (e.g., `BSIT-1M`, `BSIT-1A`, `BSBA-2B`). | Filterable by academic period, department, program, and year level in Scheduler workbench. | Updates section room capacity, name, or shift (Morning / Afternoon / Evening). | Cannot be deleted if students are enrolled. May be marked closed or archived. | Creating duplicate section code for the same academic year/semester rejected with unique constraint error. | `OPEN` $\rightarrow$ `FULL` $\rightarrow$ `CLOSED` $\rightarrow$ `ARCHIVED`. | Controls student intake at Advising desk (TLC Helpdesk). Assigning students to full sections triggers capacity warning. |
| **Subject Section** | Created when a curriculum subject is instantiated into a specific section offering with day, time, and room slots. | Displayed in Scheduler cohort grid, Professor teaching loads, and Student Certificate of Registration (COR). | Scheduler updates assigned room, schedule hours, or assigned faculty. Dynamic conflict detector checks room/prof/section overlaps. | Removing offering unlinks professor assignment and schedule slot. Blocked if students have grades recorded. | Overlapping time slot for the same room or same professor returns conflict alert with conflicting subject/section details. | `UNASSIGNED` $\rightarrow$ `SCHEDULED` $\rightarrow$ `FACULTY_ASSIGNED`. | Directly populates student schedule table, generates professor weekly schedule grid, and establishes LMS Classroom access context. |
| **Schedule** | Instantiated via Scheduler Workbench or deterministic Auto-Assignment engine. Maps Day (e.g., `MW`, `TTH`, `FS`), Time range, and Room. | Visible in Scheduler time grid, Student Portal class schedule, and Professor weekly planner. | Scheduler drags/edits time slots. Conflict simulator evaluates room and professor availability in real time. | Clearing schedule resets offering to unscheduled state. Room and professor slots are immediately freed. | Submitting invalid time strings (e.g. End Time earlier than Start Time) rejected by backend time parser. | `DRAFT` $\rightarrow$ `PUBLISHED` $\rightarrow$ `MODIFIED`. | Determines student weekly timetable. Professor schedule syncs instantaneously. Student portal calendar updates without requiring re-enrollment. |
| **Student** | Promoted from `pre_enrollments` by IT Center after Cashier downpayment. Creates permanent record in `students` with student ID (`YYYY-NNNN`). | Accessible to Student Portal, Registrar records, Professor student roster, and Clinic health charts. | Profile edits (contact info, emergency phone) allowed in portal. Academic profile (Program, Section) modified only by Registrar. | Student status toggled to `INACTIVE`, `DROPPED`, `GRADUATED`, or `SUSPENDED`. Deactivated students cannot log in to Student Portal. | Submitting invalid birthdate (< 15 years old for freshmen) rejected by registration validation. Malformed email blocked. | `APPLICANT` $\rightarrow$ `VERIFIED` $\rightarrow$ `ADVISED` $\rightarrow$ `MEDICAL_CLEARED` $\rightarrow$ `PAID` $\rightarrow$ `ENROLLED`. | Determines active access to Student LMS Subjects dashboard. Student can only see subjects matching their enrolled section. |
| **Enrollment** | Created when applicant completes 6-step online registration wizard. Stored in `pre_enrollments` with temporary ID (`GNCP-YYYY-NNNNNN`). | Trackable by applicant via Tracking Portal using Temp ID + PIN. Visible in queue at Registrar, Helpdesk, Clinic, Cashier, and IT Center. | Each station updates its respective slice (Registrar notes, assigned section, clinic clearance, OR number and payment). | Rejected applicants marked `REJECTED` with registrar remarks. Application retained for audit compliance; student cannot advance. | Submitting inconsistent pathway (e.g. ALS track with regular SHS strand) auto-sanitized by wizard state handlers. | `PENDING` $\rightarrow$ `VERIFIED` $\rightarrow$ `ADVISED` $\rightarrow$ `MEDICAL_CLEARED` $\rightarrow$ `PAID` $\rightarrow$ `PROMOTED/ENROLLED`. | Dictates which station can process the applicant. Out-of-order station access (e.g. Cashier attempting to accept payment for unverified applicant) is blocked. |
| **Announcement** | Created by Professors or Admin. Supports audience targeting: `ALL`, `DEPARTMENT`, `SUBJECT`, or specific `SECTION`. | Displayed on Student Portal Announcements feed and inside individual LMS Classroom views. | Professor or Admin can edit title, content, or pinned status. Historical edits logged with timestamp. | Deleting announcement removes record from `announcements` and unlinks from `announcement_sections`. | Blank title or empty target section payload rejected with 400 Bad Request. | `DRAFT` $\rightarrow$ `PUBLISHED` $\rightarrow$ `ARCHIVED` $\rightarrow$ `DELETED`. | Subject-specific announcements display exclusively in enrolled students' Classroom views. Zero cross-subject leakage observed. |
| **File** | Professor uploads documents, PDFs, slides, and syllabus to Personal Drive (`professor_files`). Stored in dedicated filesystem directory. | Professor views file list, file sizes, and storage usage. Downloadable via secure authenticated endpoint. | Renaming file title in personal drive. | Deleting file removes physical disk file and database metadata. Blocked if file is actively linked to a published LMS material. | Unsupported file extensions (e.g. `.exe`, `.bat`, `.sh`) rejected. Files exceeding size limits (25MB) blocked by upload guard. | `STORED` $\rightarrow$ `LINKED_TO_MATERIAL` $\rightarrow$ `DELETED`. | Files in Personal Drive remain private to professor until explicitly published as an LMS Learning Material to one or more sections. |
| **LMS Material** | Created when a professor publishes a file from Personal Drive to a target subject and section(s). Stored in `lms_materials` & `lms_material_sections`. | Enrolled students view materials in their Classroom View under the corresponding Subject card. | Professor can update material title, instructions, and target section distribution. | Unpublishing material (`unpublishMaterial`) deletes LMS post and sections link without destroying professor's original file in Drive. | Attempting to publish without selecting at least one target section rejected with 400. Targeting a section professor does not teach rejected with 403. | `PUBLISHED` $\rightarrow$ `UNPUBLISHED/REMOVED`. | Instantaneously updates student Classroom view. Unpublished materials disappear from student view immediately. |

---

## 2. Dynamic Selection Dependency & Reset Matrix

When an interactive selection at an upper level of the academic hierarchy is changed, the system triggers deterministic dependency purges to prevent orphan or contradictory state:

```
[Admission Type] ───────────────► Resets: Required Document Checklist & Previous School validation
       │
[Education Pathway] ────────────► Resets: JHS, SHS, Track, Strand, and CLC fields
       │
   [College] ───────────────────► Resets: Degree Program, Major, and Specialization
       │
   [Program] ───────────────────► Resets: Curriculum, Required Lab Fees, and Available Sections
       │
   [Section] ───────────────────► Resets: Subject Offerings, Assigned Faculty, Schedule Timetable
       │
   [Subject] ───────────────────► Resets: Classroom Context, Announcements Feed, Course Materials
```

### Detailed Reset Behaviors Tested

1. **College Switch (`COIT` $\rightarrow$ `COBA`):**
   - *Previous Selection:* College of Information Technology $\rightarrow$ BSIT.
   - *User Action:* Switch College dropdown to College of Business Administration.
   - *System State Mutation:* `courseCode` is immediately reset to empty string `''`.
   - *Outcome:* Prevents the fatal contradictory state of `College of Business Administration + BSIT`. User must actively select `BSBA`.

2. **Education Pathway Switch (`ALS` $\rightarrow$ `REGULAR`):**
   - *Previous Selection:* Alternative Learning System $\rightarrow$ CLC Name entered $\rightarrow$ JHS/SHS set to `N/A (ALS)`.
   - *User Action:* Switch pathway back to `REGULAR`.
   - *System State Mutation:* Clears ALS Learning Center, un-sets automatic N/A labels, and re-engages required field validations for Junior High School, Senior High School, and SHS Academic Track/Strand.

3. **Student Type Switch (`FRESHMAN` $\rightarrow$ `TRANSFEREE`):**
   - *Previous Selection:* Freshman with High School Form 138 / ALS Certificate requirements.
   - *User Action:* Switch Admission Type to `TRANSFEREE`.
   - *System State Mutation:* Dynamic document checklist swaps High School credentials for *Honorable Dismissal*, *Transcript of Records (TOR)*, and *Certificate of Good Moral Character*. Reassessment of general education transfer credits enabled.

4. **Section Reassignment in Advising (`BSIT-1A` $\rightarrow$ `BSIT-1M`):**
   - *Previous Selection:* Applicant advised into Section `BSIT-1A`.
   - *User Action:* Advising officer changes section to `BSIT-1M` before cashier processing.
   - *System State Mutation:* Pre-enrollment record `section_code` updates to `BSIT-1M`.
   - *Downstream Effect:* Upon promotion, student Certificate of Registration (COR) populates subjects, room assignments, and professors belonging strictly to `BSIT-1M`.

5. **Schedule Slot Mutation in Scheduler (`MW 09:00-10:30` $\rightarrow$ `TTH 13:00-14:30`):**
   - *Previous Selection:* Subject scheduled on Monday/Wednesday morning.
   - *User Action:* Scheduler modifies offering to Tuesday/Thursday afternoon.
   - *System State Mutation:* `subject_sections` record updates days and time range. Conflict engine re-checks both room and professor availability for the new window.
   - *Downstream Effect:* Professor weekly teaching grid relocates class slot. All enrolled students see updated schedule on their portal timetable instantly without manual re-enrollment.

---

## 3. Station Workflow State Transition Matrix

The table below documents legal, illegal, and recovery transitions across the multi-station enrollment lifecycle:

| Initial State | Trigger Action | Executing Role | Target State | Validation Rules Enforced | Failure / Illegal Attempt Behavior |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **New Entry** | Submit Online Form | Applicant | `PENDING` | Validates all personal, contact, educational, and medical fields. Birthdate $\ge$ 15 years. | Missing required fields flags inline validation errors; form submission blocked. |
| **PENDING** | Document Verification | Registrar | `VERIFIED` | Registrar verifies original ALS COR / Form 138 / Birth Certificate. | Cannot verify if mandatory documents are flagged missing. |
| **PENDING** | Attempt Advising | TLC Helpdesk | **BLOCKED** | System mandates `VERIFIED` status prior to section assignment. | Action rejected: *"Applicant must be verified by Registrar before advising."* |
| **VERIFIED** | Section Allocation | TLC Helpdesk | `ADVISED` | Validates section capacity. Section must match student program and year level. | Assigning full section returns capacity warning. Mismatched program blocked. |
| **ADVISED** | Medical Clearance | Clinic Officer | `MEDICAL_CLEARED` | Physical examination and medical interview completed. Fitness status recorded. | Incomplete physical exam flags review hold. Applicant cannot bypass to Cashier. |
| **MEDICAL_CLEARED**| Downpayment / OR | Cashier | `PAID` | Official Receipt (OR) number required. Minimum downpayment (₱3,000) or Full Cash recorded. | Blank OR number or invalid amount rejected. Applicant remains `MEDICAL_CLEARED`. |
| **PAID** | Student Promotion | IT Center | `PROMOTED` / `ENROLLED`| Generates permanent Student ID (`YYYY-NNNN`), student portal credentials, and COR. | Cannot promote un-paid pre-enrollment. Database transaction ensures atomicity. |
| **REJECTED** | Mark Disqualified | Registrar | `REJECTED` | Reason for rejection required in registrar notes. Pre-enrollment marked terminal. | Downstream stations (Helpdesk, Clinic, Cashier, IT) completely block further processing. |
| **REJECTED** | Attempt Payment | Cashier | **BLOCKED** | Rejected applicants are ineligible for payment processing. | System throws error: *"Applicant has been rejected and cannot be processed for payment."* |

---

## 4. Multi-Layer Validation & Cross-Module Isolation Matrix

| Layer Tested | Scope | Expected Behavior | Actual Behavior | Audit Status |
| :--- | :--- | :--- | :--- | :--- |
| **UI Presentation Layer** | Vue 3 Form Validation & State Handlers | Immediate feedback on empty/invalid inputs; disables buttons during flight; clears stale children upon parent change. | Reactive watchers reset course dropdown upon college switch and toggle ALS fields dynamically. | **PASS** |
| **API Controller Layer** | PHP 8.2 Endpoints (`api/index.php`) | Validates payload structures, data types, mandatory keys, and CSRF/Session tokens. | Returns clean JSON with HTTP status codes (200, 400, 401, 403, 404, 500). No uncaught fatals. | **PASS** |
| **Business Logic Layer** | PHP Service Classes (`*Service.php`) | Enforces institutional constraints (single-active session, department lock, schedule conflict checking). | Conflict engine detects room/prof overlaps; Department lock blocks rogue inserts with 403. | **PASS** |
| **Database Layer** | MariaDB 10.4 Relational Engine | Foreign key integrity, unique constraints, transactional rollbacks, no orphan records. | Zero orphaned `subject_sections`, zero orphaned `professors`, zero malformed tokens. | **PASS** |
| **Classroom Isolation Layer**| Student LMS Subjects & Content | Enrolled students access only their section's materials and announcements; zero cross-course leakage. | Students enrolled in `BSIT-1A` access only IT101/IT102 content tagged for their section; zero leakage. | **PASS** |

---

*This matrix serves as the formal baseline for the GNCP Complete System Behavior Audit.*
