# Comprehensive Functional System Behavior Documentation

**Institution:** Go-on National College of the Philippines (GNCP)  
**System:** Integrated Academic & Enrollment Management System  
**Audience:** School Administrators, Academic Registrars, Schedulers, Faculty Professors, Students, and Evaluators  
**Document ID:** `GNCP-SYS-BEHAVIOR-2026-V1`  

---

## 1. Executive Overview & System Architecture

The GNCP Academic & Enrollment Management System is an integrated web application that manages the complete academic lifecycle of higher education—from an applicant's initial online application, through multi-station verification, academic advising, medical assessment, cashier payment, and student profile promotion, to classroom scheduling, faculty workload allocation, and daily online learning management.

Rather than treating enrollment, scheduling, faculty management, and student learning as detached silos, the system maintains a unified relational data pipeline. A decision or schedule adjustment made at the administrative or scheduling level immediately cascades into faculty timetables, student schedules, and student classroom interfaces without manual re-entry or delay.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          1. ADMINISTRATIVE SETUP                            │
│           Academic Periods • Departments • Programs • Course Catalog        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          2. APPLICANT REGISTRATION                          │
│               Online 6-Step Portal • Automatic Requirements                 │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       3. MULTI-STATION ENROLLMENT                           │
│     Registrar Review ──► TLC Advising ──► Clinic ──► Cashier ──► IT Center  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       4. COHORT CLASS SCHEDULING                            │
│      Section Offerings • Conflict Detection • Faculty Load Allocation       │
└───────────────────┬─────────────────────────────────────┬───────────────────┘
                    │                                     │
                    ▼                                     ▼
┌──────────────────────────────────────┐  ┌───────────────────────────────────┐
│         5. PROFESSOR WORKBENCH       │  │          6. STUDENT LMS           │
│  Weekly Timetable • Personal Drive   │  │   Subjects Dashboard • Classroom  │
│  Announcements • Course Materials    │  │   Announcements • Learning Files  │
└──────────────────────────────────────┘  └───────────────────────────────────┘
```

---

## 2. Institutional User Roles & Capabilities

The system defines specialized user roles, each operating within a dedicated interface with strict data scoping and authorization rules.

### 2.1 Administrator
* **Operational Scope:** Overall institutional governance, academic program setup, course catalog maintenance, term settings, and employee account administration.
* **What They See:** Central administrative dashboard displaying overall enrollment statistics, active student counts, faculty counts, department catalog, program definitions, subject catalog, and user accounts directory.
* **What They Can Create:** Degree programs, course subjects, academic sections, and operator user accounts (Registrars, Helpdesk Officers, Clinic Officers, Cashiers, IT Officers, Schedulers, Professors).
* **What They Cannot Modify (Institutional Lock):** Institutional departments are locked. Existing core colleges cannot be modified or deleted, ensuring system-wide relational stability.
* **What Happens After Their Actions:**
  * When an admin creates a subject, it instantly becomes available for inclusion in department curricula and section offerings.
  * When an admin creates a professor account, the professor is linked to their respective college department and can immediately log in through the Employee Gateway.
  * When an admin deactivates an account, the user is immediately kicked from their active session and cannot log in until reactivated.

### 2.2 Registrar Officer
* **Operational Scope:** First-line verification of applicant documentation and academic eligibility.
* **What They See:** The applicant processing queue listing pre-enrollments awaiting document review, filterable by admission type (Freshman, Transferee, Returning).
* **What They Do:** Inspect submitted physical and digital credentials (e.g., ALS Certificates, High School Form 138, PSA Birth Certificate, Transcript of Records). They can mark records as *Verified*, put them on hold with explanatory notes, or mark them *Rejected*.
* **What Happens After Their Actions:**
  * Marking an applicant *Verified* unlocks the applicant's record at Station 2 (TLC Advising Desk).
  * If the registrar rejects an applicant, the record is locked; subsequent stations (Advising, Clinic, Cashier, IT) are automatically blocked from processing the student.

### 2.3 TLC Helpdesk (Academic Advising)
* **Operational Scope:** Curriculum evaluation, section assignment, and NSTP program tagging.
* **What They See:** Queue of *Verified* applicants ready for academic section assignment.
* **What They Do:** Confirm the applicant's degree program, evaluate elective preferences (e.g., CWTS vs. ROTC for NSTP), and assign the applicant to an open cohort section (e.g., `BSIT-1M`).
* **What Happens After Their Actions:**
  * The applicant moves to *Advised* status with their assigned section code.
  * The assigned section determines the student's future class schedule, subject offerings, and assigned professors.
  * The applicant becomes visible in the Medical Clinic queue.

### 2.4 Medical Clinic Officer
* **Operational Scope:** Health screening, physical examinations, and physical fitness certification.
* **What They See:** Queue of *Advised* applicants awaiting health clearance.
* **What They Do:** Record vitals, assess pre-existing conditions, conduct a brief interview, and issue a fitness status for Physical Education (PE) and NSTP activities.
* **What Happens After Their Actions:**
  * Setting fitness to *Cleared* transitions the applicant to *Medical Cleared* status.
  * The Cashier station is notified that the applicant is medically cleared to pay tuition and registration fees.

### 2.5 Cashier (Finance & Billing)
* **Operational Scope:** Fee assessment verification, downpayment collection, and official receipt issuance.
* **What They See:** Medically cleared applicants with their itemized fee assessment (tuition, laboratory fees, registration fees, and miscellaneous expenses).
* **What They Do:** Verify the payment mode (Cash vs. Installment), collect the student's downpayment or full tuition, enter the physical Official Receipt (OR) number, and record the transaction.
* **What Happens After Their Actions:**
  * The record updates to *Paid* status with the recorded OR number and payment balance.
  * The applicant is forwarded to the final station: IT Center for official enrollment and profile activation.

### 2.6 IT Center Officer
* **Operational Scope:** Final collegiate promotion, permanent Student ID generation, and credential distribution.
* **What They See:** Queue of *Paid* applicants ready for official enrollment.
* **What They Do:** Review the completed multi-station audit trail and click *Promote / Enroll Student*.
* **What Happens After Their Actions:**
  * The applicant's pre-enrollment status transitions to *Enrolled*.
  * The system creates a permanent collegiate student record, generates an official Student ID (e.g., `2026-1018`), and provisions the student portal account.
  * An official Certificate of Registration (COR) is generated containing the student's complete weekly subject timetable, classroom assignments, and professor names based on their assigned section.

### 2.7 Academic Scheduler
* **Operational Scope:** Section class timetable generation, room allocation, faculty teaching load management, and conflict resolution.
* **What They See:** The Cohort Scheduling Workbench showing program sections, curriculum subject offerings, room utilization grids, and faculty availability.
* **What They Do:**
  * Schedule subject offerings into weekly day/time slots (e.g., `MW 09:00 AM - 10:30 AM`) and assign physical lecture halls or computer laboratories.
  * Assign qualified professors to subject sections based on department specialization.
  * Utilize the real-time Conflict Simulator to verify that room bookings and professor workloads do not overlap.
  * Alternatively, run the Deterministic Auto-Scheduler to automatically assign eligible faculty to unscheduled sections based on teaching load constraints.
* **What Happens After Their Actions:**
  * Assigned schedules immediately appear on the professor's weekly teaching calendar.
  * The schedule updates on the timetables of all students enrolled in that section.
  * The professor is granted instructional management authority over that section's LMS classroom.

### 2.8 Professor (Faculty)
* **Operational Scope:** Classroom instruction, syllabus distribution, announcements, and course learning material management.
* **What They See:** The Professor Workstation showing their assigned teaching sections, weekly class timetable, student rosters, personal cloud drive, and published LMS materials.
* **What They Do:**
  * View their weekly schedule, room assignments, and enrolled student counts.
  * Upload lecture slides, PDF readings, and assignment sheets to their private Personal Drive.
  * Publish files from their Drive to specific taught sections (e.g., publishing a C Programming syllabus to `BSIT-1A`).
  * Create academic announcements targeting a specific course, section, or all their students.
  * Unpublish or remove obsolete learning materials when no longer needed.
* **What Happens After Their Actions:**
  * Published announcements appear in real-time on enrolled students' Subject Classroom feeds.
  * Published learning materials become instantly downloadable by enrolled students.
  * Students outside the targeted section cannot view or access the materials.

### 2.9 Student
* **Operational Scope:** Class schedule tracking, academic status review, accessing subject classroom content, downloading course materials, and reading professor announcements.
* **What They See:** The Student Portal featuring the **Subjects** dashboard (Google Classroom-style course cards), weekly class schedule timetable, official COR, and general school announcements.
* **What They Do:**
  * Log in using their permanent Student ID and password.
  * View their enrolled subject cards showing subject code, course title, units, schedule time, and professor name.
  * Click any subject card to enter the full Classroom View.
  * Read professor announcements specific to their class.
  * Download lecture slides, reading materials, and laboratory guides posted by their professor.
* **What Happens After Their Actions:**
  * The student accesses strictly isolated course materials for their section, with zero risk of seeing materials or grades from other cohorts.

---

## 3. The Lifecycle of Major User Actions

Every major user interaction in the GNCP system triggers an explicit operational flow across data, business rules, and dependent modules:

### Action 1: Applicant Submits Online Pre-Registration Form
```text
USER ACTION
An applicant fills out the 6-step online registration form at /enrollment-system/index.html, selects their program (BSIT), declares their educational background (ALS), and clicks "Submit Application".

↓

SYSTEM RESPONSE
The system validates that all required fields are present, verifies age eligibility, checks that the applicant has agreed to data privacy policies, and calculates initial tuition and lab fee assessments.

↓

DATA THAT CHANGES
A new pre-enrollment record is created in the database with status "PENDING".
A unique Temporary Student ID (e.g., GNCP-2026-873058) and a secure 4-digit tracking PIN are generated.

↓

OTHER MODULES AFFECTED
The applicant appears in the Registrar station processing queue.
The Status Tracker portal recognizes the Temporary ID and PIN, displaying "Application Under Review".

↓

WHAT THE USER SEES NEXT
The applicant is presented with a printable Confirmation Slip containing their Temp ID, PIN, assessed fees, and a checklist of physical documents required at the Registrar desk.
```

---

### Action 2: Registrar Verifies Applicant Credentials
```text
USER ACTION
The Registrar Officer opens the applicant's record, examines their physical ALS Certificate of Rating and Completion, enters verification remarks, and clicks "Verify Application".

↓

SYSTEM RESPONSE
The system checks that the application is currently in "PENDING" status and verifies that no required documents are marked missing.

↓

DATA THAT CHANGES
The pre-enrollment status updates from "PENDING" to "VERIFIED".
Registrar verification timestamp, officer username, and notes are stamped onto the record.

↓

OTHER MODULES AFFECTED
The applicant is cleared from the Registrar queue.
The applicant immediately appears in the TLC Helpdesk (Advising) queue.
The Tracking Portal updates the applicant's status to "Documents Verified — Proceed to Advising".

↓

WHAT THE USER SEES NEXT
The Registrar sees the record marked with a green "VERIFIED" badge.
The applicant at the campus helpdesk is called to Station 2 for section allocation.
```

---

### Action 3: TLC Helpdesk Assigns Academic Section
```text
USER ACTION
The Helpdesk Officer selects Section BSIT-1M for the applicant, confirms their CWTS preference, and clicks "Save Advising".

↓

SYSTEM RESPONSE
The system verifies that Section BSIT-1M belongs to the BSIT program, is open for enrollment, and has remaining seat capacity.

↓

DATA THAT CHANGES
The pre-enrollment status updates to "ADVISED".
The record's section code is set to "BSIT-1M", and helpdesk completion metadata is saved.

↓

OTHER MODULES AFFECTED
The section's enrolled count increments by 1.
The applicant immediately becomes visible in the Medical Clinic queue.

↓

WHAT THE USER SEES NEXT
The Helpdesk Officer sees a confirmation toast.
The applicant receives their Routing Slip directing them to Station 3 (Medical Clinic).
```

---

### Action 4: Cashier Collects Downpayment & Issues Receipt
```text
USER ACTION
The Cashier inputs Official Receipt number OR-2026-40804, inputs payment amount ₱18,300.00 (Cash), and clicks "Confirm Payment".

↓

SYSTEM RESPONSE
The system verifies that the applicant has achieved "MEDICAL_CLEARED" status, validates that the OR number is non-empty, and checks that the amount meets the minimum downpayment threshold.

↓

DATA THAT CHANGES
The pre-enrollment status updates to "PAID".
The payment record stores the OR number, amount paid, balance (₱0.00), payment mode, and cashier identification.

↓

OTHER MODULES AFFECTED
The applicant is automatically queued at Station 5 (IT Center) for student promotion.
The Cashier daily collection report increments total collections and logs the issued OR number.

↓

WHAT THE USER SEES NEXT
The Cashier prints the official GNCP payment receipt.
The applicant proceeds to Station 5 (IT Center) for ID issuance.
```

---

### Action 5: IT Center Promotes Applicant to Permanent Student
```text
USER ACTION
The IT Officer reviews the paid pre-enrollment record and clicks "Promote / Generate Student Profile".

↓

SYSTEM RESPONSE
The system opens a database transaction, validates that status is "PAID", generates the next sequential permanent Student ID (e.g., 2026-1018), creates the collegiate student account, provisions portal credentials, and generates the student's official schedule based on their assigned section.

↓

DATA THAT CHANGES
Pre-enrollment status is marked "PROMOTED" / "ENROLLED".
A permanent row is inserted into the collegiate students table.
The Certificate of Registration (COR) schedule is generated.

↓

OTHER MODULES AFFECTED
The student can now log in to the Student Portal.
The student appears on the class rosters of all professors teaching subjects in Section BSIT-1M.

↓

WHAT THE USER SEES NEXT
The IT Officer prints the official GNCP Certificate of Registration (COR) and student ID card for the student.
The student receives their permanent student ID and login instructions.
```

---

### Action 6: Scheduler Assigns Professor to Class Offering
```text
USER ACTION
The Scheduler opens Section BSIT-1M, selects Subject IT101 (Intro to Computing), selects Dr. Alan Turing from the candidate faculty list, and clicks "Save Assignment".

↓

SYSTEM RESPONSE
The system validates that Dr. Alan Turing is an active faculty member, belongs to the College of Computing Studies, and has no scheduling conflicts in the designated room and time slot.

↓

DATA THAT CHANGES
The subject offering record in the database updates its assigned professor ID to Dr. Alan Turing's ID.

↓

OTHER MODULES AFFECTED
Dr. Alan Turing's faculty dashboard immediately displays IT101 (BSIT-1M) under his active teaching assignments.
All students enrolled in BSIT-1M immediately see Dr. Alan Turing listed as their instructor for IT101 on their COR and on their LMS Subjects card.

↓

WHAT THE USER SEES NEXT
The Scheduler sees the subject card turn green with Dr. Turing's name displayed.
Dr. Turing can now create announcements and publish course materials to BSIT-1M for IT101.
```

---

### Action 7: Professor Publishes Learning Material to Section
```text
USER ACTION
Professor Dennis Ritchie opens his Personal Drive, selects "C_Programming_Lecture_01.pdf", clicks "Publish to Class", selects Course "IT102", checks Section "BSIT-1A", and clicks "Publish".

↓

SYSTEM RESPONSE
The system validates that the file exists in the professor's drive, verifies that Professor Ritchie is the assigned instructor for IT102 in BSIT-1A, and creates the material posting.

↓

DATA THAT CHANGES
A new learning material entry is recorded, and an association record links the material to Section "BSIT-1A".

↓

OTHER MODULES AFFECTED
The Student Portal for all students enrolled in BSIT-1A updates its LMS repository for IT102.

↓

WHAT THE USER SEES NEXT
The professor sees the file listed in his "Published Materials" table with its target section tag.
Students in BSIT-1A opening their IT102 Classroom card immediately see "Lecture 01: C Language Basics" available for download. Students in other sections or courses cannot see it.
```

---

## 4. Multi-Layer Cross-Module Dependency Rules

The integrity of the academic system relies on strict upward and downward dependency chains:

```
Academic Period (e.g. 1st Sem 2026-2027)
       │
       ▼
Department / College (e.g. College of Computing Studies)
       │
       ▼
Degree Program (e.g. BSIT)
       │
       ▼
Curriculum Catalog (e.g. BSIT 2026 Curriculum)
       │
       ▼
Course Subjects (e.g. IT101, IT102, GE101)
       │
       ▼
Academic Section (e.g. BSIT-1M, BSIT-1A)
       │
       ▼
Subject Section Offerings (Instantiated with Day, Time, Room)
       │
       ▼
Professor Assignment (Faculty member allocated to offering)
       │
       ▼
Student Enrollment (Student allocated to section)
       │
       ▼
Student LMS Classroom View (Subjects, Materials, Announcements)
```

### Dependency Rules Enforced

1. **Downstream Schedule Propagation:** If a scheduler changes the meeting time of a subject section from Monday morning to Tuesday afternoon, the change updates simultaneously across:
   * The Scheduler's cohort timetable grid;
   * The Professor's weekly teaching schedule;
   * The Student Portal timetable for every enrolled student;
   * The Student's printable Certificate of Registration (COR).
   * *No student needs to be dropped or re-enrolled for schedule updates to take effect.*

2. **Faculty Reassignment:** If a scheduler reassigns a section from Professor A to Professor B:
   * Professor A immediately loses LMS publishing access to that section.
   * Professor B immediately gains LMS management authority over that section.
   * Students in the section see Professor B's name on their subject card.
   * Existing historical materials published by Professor A remain visible to students so learning continuity is not broken.

3. **Section Reassignment at Advising:** If an applicant is moved from Section `BSIT-1A` to `BSIT-1B` prior to final enrollment:
   * The student's assigned subject list resets to match `BSIT-1B`'s specific offerings and timetable.
   * Upon IT Center promotion, the student is granted LMS access strictly to `BSIT-1B` classrooms.

---

## 5. The Student LMS: Subjects & Classroom Behavior

The Student Portal LMS underwent a major architectural redesign, transitioning from a generic file list ("School Materials") to an intuitive, Google Classroom-inspired **Subjects** experience.

### 5.1 The Subjects Dashboard
* **Why the Student Sees Their Subjects:** The dashboard does not display arbitrary courses. A subject card appears on the student's dashboard **if and only if** that subject is part of the official class schedule for the student's enrolled section in the active academic term.
* **Information Displayed on Each Card:**
  * **Visual Header Banner:** Harmonious color-coded gradient uniquely identifying the subject.
  * **Subject Code & Title:** E.g., `IT101 — Introduction to Computing`.
  * **Assigned Professor:** E.g., `Dr. Alan Turing` (or *"Faculty to be announced"* if unscheduled).
  * **Schedule & Room:** E.g., `MW 09:00 AM - 10:30 AM | Computer Lab 1`.
  * **Enrolled Section:** E.g., `BSIT-1M`.
  * **Units Breakdown:** E.g., `3 Lec / 1 Lab Units`.
  * **Action Button:** *"Open Classroom"* button providing entry to the subject's dedicated space.

### 5.2 The Subject Classroom View
When the student clicks a subject card, the dashboard transitions into the dedicated Classroom interface for that specific course:
* **Hero Banner:** Full-width header featuring the course title, instructor name, and meeting time.
* **Class Announcements Stream:** Reverse-chronological feed of announcements published by the professor targeting this subject and section. Announcements feature timestamps and priority indicators.
* **Course Materials Repository:** Itemized repository of lecture notes, slides, and reference files uploaded by the professor. Each material displays:
  * Document title and professor instructions;
  * Filename and file extension badge (PDF, DOCX, PPTX);
  * Formatted file size (e.g., `1.05 MB`);
  * Direct one-click download button.
* **Strict Section Isolation:** The system guarantees zero cross-course or cross-section data leakage. A student enrolled in `BSIT-1A` taking `IT101` cannot see announcements or files posted for `IT102`, nor can they see content posted to `BSIT-1B` unless the professor explicitly co-published the material to both sections.

---

## 6. System Error Handling & Resilience

The system provides graceful, user-centric error handling across all unexpected conditions, ensuring that mistakes do not corrupt data or leave users trapped:

| Error Condition | User Experience & System Behavior | Data Impact | User Recovery Path |
| :--- | :--- | :--- | :--- |
| **Invalid Admission Input** (e.g. Missing contact, invalid birthdate) | UI highlights invalid fields in red with inline explanation; Submit button remains disabled or notifies user. | No record created in database. | User corrects highlighted field and submits successfully. |
| **Out-of-Order Station Attempt** (e.g. Cashier attempts to charge un-advised student) | System displays warning: *"Applicant must complete Advising and Medical clearance before payment."* Action is rejected. | Record status remains unchanged. | Officer instructs applicant to visit required prior station. |
| **Schedule Slot Conflict** (e.g. Same room booked for two classes at the same time) | Scheduler conflict engine displays warning modal detailing conflicting subject, section, and booked time. | Conflicting schedule is rejected and not saved. | Scheduler adjusts start/end time or selects an alternative open classroom. |
| **Unsupported File Upload** (e.g. Professor attempts to upload `.exe` or `.bat`) | System rejects upload with alert: *"Unsupported file format. Please upload PDF, Word, PowerPoint, or image files."* | File is not written to disk or database. | Professor chooses a standard document format and re-uploads. |
| **Single-Active Session Collision** (User logs in from a second browser) | The earlier browser session is immediately invalidated. The next click receives an alert: *"Your session was opened in another window. Please log in again."* | Active session token updates to the new login. | Earlier session redirects cleanly to login page. New session continues unhindered. |
| **Duplicate Application Submission** | Form submission button enters loading state and disables further clicks during transit. | Only one unique pre-enrollment row is persisted. | User sees single confirmation slip with one Temp ID and PIN. |

---

## 7. The ALS $\rightarrow$ BSIT Applicant Experience: Deep-Dive

A critical scenario tested during this audit was an applicant graduating from the **Alternative Learning System (ALS)** choosing a technical collegiate degree (**BSIT**):

1. **Academic Validity:** Under GNCP institutional policy, graduates of the DepEd Alternative Learning System who pass the Accreditation & Equivalency (A&E) secondary assessment are legally qualified for admission into tertiary degree programs, including technical disciplines such as BSIT.
2. **Registration Experience:**
   * When the applicant selects `Education Pathway: ALS`, the system automatically adjusts the form:
   * Junior High School and standard Senior High School track fields are set to `N/A (ALS)` and disabled, preventing user confusion.
   * An **ALS Community Learning Center** field appears, allowing the applicant to record their testing center.
   * The required document checklist dynamically swaps out Form 138 (High School Report Card) and mandates the **ALS Certificate of Rating (COR)** and **ALS Certificate of Completion**.
3. **Assessment Calculation:** The system correctly evaluates BSIT laboratory requirements, assessing the ₱3,000 lab fee alongside standard collegiate tuition, resulting in an accurate ₱18,300 total assessment.
4. **Change-of-Mind Recovery:**
   * If the applicant changes their mind and switches their College choice from `Computing Studies` to `Business Administration`, the course selection immediately clears to prevent the contradictory state of `Business Administration + BSIT`.
   * If the applicant switches back from `ALS` to `Regular SHS`, the ALS learning center is cleared, placeholders are removed, and standard SHS track validations re-engage.
5. **Downstream Handling:** The ALS applicant was successfully verified by the Registrar, assigned to Section `BSIT-1M` by Advising, cleared by the Medical Clinic, processed by the Cashier, and promoted by the IT Center to permanent student `2026-1018` with zero database errors or orphan records.

---

## 8. High-Level Operational Map

```text
========================================================================================
                                1. INSTITUTIONAL SETUP
========================================================================================
Admin defines Academic Terms ──► Configures Departments ──► Establishes Degree Programs
                                                                     │
                                                                     ▼
                                                          Creates Subject Catalog
                                                                     │
                                                                     ▼
                                                          Creates Operator Accounts

========================================================================================
                                2. ADMISSION & ONBOARDING
========================================================================================
Applicant fills 6-Step Portal ──► Generates Temp ID & PIN ──► Prints Document Checklist
                                                                     │
                                                                     ▼
                                                           Station 1: REGISTRAR
                                                           (Document Verification)
                                                                     │
                                                                     ▼
                                                           Station 2: TLC ADVISING
                                                           (Section & CWTS Allocation)
                                                                     │
                                                                     ▼
                                                           Station 3: MEDICAL CLINIC
                                                           (Health Screening & Fitness)
                                                                     │
                                                                     ▼
                                                           Station 4: CASHIER
                                                           (Downpayment & OR Issuance)
                                                                     │
                                                                     ▼
                                                           Station 5: IT CENTER
                                                           (Promotion & Permanent ID)

========================================================================================
                                3. ACADEMIC SCHEDULING
========================================================================================
Scheduler opens Workbench ──► Allocates Days & Times ──► Checks Conflict Simulator
                                                                     │
                                                                     ▼
                                                          Assigns Qualified Professor
                                                                     │
                                                                     ▼
                                                          Auto-Updates Class Timetable

========================================================================================
                                4. INSTRUCTION & LEARNING
========================================================================================
Professor opens Workstation ──► Views Weekly Classes ──► Uploads to Personal Drive
                                                                     │
                                                                     ▼
                                                          Publishes to Specific Section
                                                                     │
                                                                     ▼
Student logs into Portal ──► Clicks Enrolled Subject ──► Reads Announcements & Downloads
========================================================================================
```

---

## 9. Conclusion & System Readiness

The Go-on National College of the Philippines Academic Management System operates as a fully integrated, highly resilient collegiate platform. The system successfully balances strict academic business rules with flexible user recovery, maintains real-time cross-module synchronization, strictly isolates classroom data, and delivers an intuitive, modern user experience for administrators, staff, faculty, and students alike.
