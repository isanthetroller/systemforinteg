-- ============================================================
--  GNCP Academic Portal -- Complete Database Setup Script
--  Database : gncp_portal
--  Engine   : MariaDB / MySQL (XAMPP default)
--
--  HOW TO USE:
--    1. Open phpMyAdmin -> http://localhost/phpmyadmin/
--    2. Click the "Import" tab at the top
--    3. Choose this file -> database/schema.sql
--    4. Click "Go"
--
--  This script is safe to re-run. All statements use
--  IF NOT EXISTS / INSERT WHERE NOT EXISTS guards.
-- ============================================================
-- ============================================================
-- DATABASE CREATION & SELECTION GUARD
-- Ensures successful import in phpMyAdmin even when imported
-- from the top-level server screen without selecting a database first.
-- ============================================================
CREATE DATABASE IF NOT EXISTS `gncp_portal` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `gncp_portal`;

-- ============================================================
--  TABLE 1: pre_enrollments
--  Central student application queue shared by all stations.
-- ============================================================

CREATE TABLE IF NOT EXISTS `pre_enrollments` (
    `id`                        INT AUTO_INCREMENT PRIMARY KEY,
    `temp_student_id`           VARCHAR(50) UNIQUE NOT NULL,
    `temp_pin`                  VARCHAR(6) NOT NULL,
    `student_type`              VARCHAR(20) NOT NULL,
    `course_code`               VARCHAR(20) NOT NULL,
    `nstp`                      VARCHAR(20) NOT NULL,
    `first_name`                VARCHAR(100) NOT NULL,
    `middle_name`               VARCHAR(100) DEFAULT NULL,
    `last_name`                 VARCHAR(100) NOT NULL,
    `email`                     VARCHAR(150) NOT NULL,
    `phone`                     VARCHAR(15) NOT NULL,
    `birth_date`                DATE NOT NULL,
    `gender`                    VARCHAR(20) NOT NULL,
    `address`                   TEXT NOT NULL,
    `elementary_school`         VARCHAR(255) NOT NULL,
    `junior_high_school`        VARCHAR(255) NOT NULL,
    `senior_high_school`        VARCHAR(255) NOT NULL,
    `previous_college`          VARCHAR(255) DEFAULT NULL,
    `shs_track`                 VARCHAR(50) DEFAULT NULL,
    `honors`                    VARCHAR(150) DEFAULT NULL,
    `health_status`             VARCHAR(20) NOT NULL,
    `medical_conditions`        TEXT DEFAULT NULL,
    `allergies`                 VARCHAR(255) DEFAULT NULL,
    `current_medication`        TINYINT(1) DEFAULT 0,
    `medication_details`        VARCHAR(255) DEFAULT NULL,
    `fitness_participation`     TINYINT(1) DEFAULT 1,
    `emergency_contact_name`    VARCHAR(150) NOT NULL,
    `emergency_contact_phone`   VARCHAR(15) NOT NULL,
    `payment_mode`              VARCHAR(20) NOT NULL,
    `scholarship`               VARCHAR(30) NOT NULL DEFAULT 'NONE',
    `registrar_notes`           TEXT DEFAULT NULL,
    `status`                    VARCHAR(20) DEFAULT 'PRE_REGISTERED',
    `roadmap`                   TEXT DEFAULT NULL,
    `requirements_data`         JSON DEFAULT NULL,
    `medical_data`              JSON DEFAULT NULL,
    `scholarship_data`          JSON DEFAULT NULL,
    `payment_data`              JSON DEFAULT NULL,
    `helpdesk_data`             JSON DEFAULT NULL,
    `enrollment_data`           LONGTEXT DEFAULT NULL,
    `section_code`              VARCHAR(50) DEFAULT NULL,
    `or_number`                 VARCHAR(30) DEFAULT NULL COMMENT 'Official Receipt number issued by Cashier',
    `enrolled_at`               DATETIME DEFAULT NULL COMMENT 'Timestamp when Cashier stamped as enrolled',
    `cashier_name`              VARCHAR(100) DEFAULT NULL COMMENT 'Cashier who processed payment',
    `existing_student_id`       VARCHAR(50)  DEFAULT NULL COMMENT 'RETURNING students only — references students.id',
    `year_level_applied`        VARCHAR(50)  DEFAULT NULL COMMENT 'Year level the student is re-enrolling at',
    `curriculum_version`        VARCHAR(100) DEFAULT '2022 Curriculum',
    `created_at`                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_existing_student_id` (`existing_student_id`),
    INDEX `idx_pe_status_created` (`status`, `created_at`),
    INDEX `idx_pe_course_year` (`course_code`, `year_level_applied`),
    INDEX `idx_pe_email` (`email`),
    INDEX `idx_pe_phone` (`phone`)
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 2: station_users
--  Roles: ADMIN | REGISTRAR | HELPDESK | SCHOLARSHIP |
--         MEDICAL | CASHIER | IT_CENTER
-- ============================================================

CREATE TABLE IF NOT EXISTS `station_users` (
    `id`                    INT AUTO_INCREMENT PRIMARY KEY,
    `username`              VARCHAR(50) UNIQUE NOT NULL,
    `password`              VARCHAR(255) NOT NULL,
    `role`                  VARCHAR(50) NOT NULL,
    `name`                  VARCHAR(100) NOT NULL,
    `email`                 VARCHAR(150) NULL,
    `status`                VARCHAR(20) DEFAULT 'PENDING',
    `avatar`                VARCHAR(255) DEFAULT NULL,
    `must_change_password`  TINYINT(1) NOT NULL DEFAULT 1,
    `active_session_token`  VARCHAR(64) DEFAULT NULL,
    `last_login_at`         DATETIME DEFAULT NULL,
    `last_login_ip`         VARCHAR(45) DEFAULT NULL,
    `created_at`            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_user_role_status` (`role`, `status`),
    INDEX `idx_active_session` (`active_session_token`)
) ENGINE=InnoDB;

-- Default bootstrap staff and admin accounts
INSERT INTO `station_users` (`username`, `password`, `role`, `name`, `email`, `status`, `must_change_password`) VALUES
('admin',      '$2y$10$xyUKLnTCwM0eJ8e2p53Lq.wNyWew3ACf4hJRE3wMMLmRdowbzRUoa', 'SUPER_ADMIN', 'System Administrator',     'admin@gncp.edu.ph',      'ACTIVE', 0),
('kriz',       '$2y$10$QVI30Cn5qIzCogzH2oCU..C7OudDTJV9R8cDaQI6Qk/Iv5mnwPxwK', 'REGISTRAR',   'Kriz Registrar Officer',   'kriz@gncp.edu.ph',       'ACTIVE', 0),
('tristan',    '$2y$10$cd78oR8qYsKcNff4/dpdq.qEh.1CdPlchqvD1Dj/3r/khfbsQByb.', 'HELPDESK',    'Tristan Helpdesk Officer', 'tristan@gncp.edu.ph',    'ACTIVE', 0),
('ethan',      '$2y$10$a19sAND.7ilrsfBrZ7uY0e0j.nu3bP8GLadkSN1s3pcoM9kkhReXu', 'MEDICAL',     'Dr. Ethan Medical Doctor', 'ethan@gncp.edu.ph',      'ACTIVE', 0),
('cashier',    '$2y$10$eU8Mlw7SMSnOH.9u1Cy54edUu1MN7Kss01/qyTFwiwJQvNUX6hGS.', 'CASHIER',     'Cashier Officer',          'cashier@gncp.edu.ph',    'ACTIVE', 0),
('it_officer', '$2y$10$mqcRBKBCst7FSiXbCbO5hemMvt/DweLALcB2iqvm9LI83/gqke20e', 'IT_CENTER',   'IT Center Officer',        'it_officer@gncp.edu.ph', 'ACTIVE', 0),
('developer',  '$2y$10$oY753sX7q5l/m4.67J28oObv6fC1/gR5H.h0K7hV183N592aM3hqe', 'DEVELOPER',   'Lead Developer',           'developer@gncp.edu.ph',  'ACTIVE', 0)
ON DUPLICATE KEY UPDATE `password`=VALUES(`password`), `role`=VALUES(`role`), `name`=VALUES(`name`), `status`='ACTIVE', `must_change_password`=0;

-- ============================================================
--  TABLE 3: students
--  Permanent student directory, populated by IT Center
--  on full enrollment completion.
-- ============================================================

CREATE TABLE IF NOT EXISTS `students` (
    `id`            VARCHAR(50) PRIMARY KEY,
    `name`          VARCHAR(150) NOT NULL,
    `program`       VARCHAR(150) NOT NULL,
    `email`         VARCHAR(150) DEFAULT NULL,
    `password`      VARCHAR(255) DEFAULT NULL,
    `photo`         VARCHAR(255) DEFAULT NULL,
    `year_level`    VARCHAR(50) DEFAULT '1st Year',
    `curriculum_version` VARCHAR(100) DEFAULT '2022 Curriculum',
    `status`        VARCHAR(20) DEFAULT 'Active',
    `must_change_password` TINYINT(1) NOT NULL DEFAULT 1,
    `active_session_token` VARCHAR(64) DEFAULT NULL,
    `last_login_at` DATETIME DEFAULT NULL,
    `last_login_ip` VARCHAR(45) DEFAULT NULL,
    `temp_reference_no` VARCHAR(50) DEFAULT NULL,
    `personal_info` TEXT DEFAULT NULL,
    `academic_info` TEXT DEFAULT NULL,
    `roadmap` TEXT DEFAULT NULL,
    `requirements_data` TEXT DEFAULT NULL,
    `medical_data` TEXT DEFAULT NULL,
    `scholarship_data` TEXT DEFAULT NULL,
    `payment_data` TEXT DEFAULT NULL,
    `helpdesk_data`     TEXT DEFAULT NULL,
    `enrollment_data`   TEXT DEFAULT NULL,
    `created_at`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_stud_temp_ref` (`temp_reference_no`),
    INDEX `idx_stud_email` (`email`),
    INDEX `idx_stud_prog_yr_status` (`program`, `year_level`, `status`),
    INDEX `idx_stud_active_session` (`active_session_token`),
    INDEX `idx_stud_created` (`created_at`)
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 6: enrollments
--  LEGACY SNAPSHOT TABLE — not actively written to by any station service.
--  Kept for historical compatibility. Do NOT build new features on this table.
--  Live enrollment data is stored in pre_enrollments (staging) and students (permanent).
-- ============================================================

CREATE TABLE IF NOT EXISTS `enrollments` (
    `id`        INT AUTO_INCREMENT PRIMARY KEY,
    `student`   VARCHAR(150) NOT NULL,
    `course`    VARCHAR(150) NOT NULL,
    `status`    VARCHAR(20) DEFAULT 'Enrolled',
    `updated`   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 7: programs
-- ============================================================
CREATE TABLE IF NOT EXISTS `programs` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `code`       VARCHAR(50) UNIQUE NOT NULL,
    `name`       VARCHAR(150) NOT NULL,
    `department` VARCHAR(150) NOT NULL,
    `status`     VARCHAR(20) DEFAULT 'Active',
    INDEX `idx_prog_dept` (`department`, `status`)
) ENGINE=InnoDB;

INSERT INTO `programs` (`code`, `name`, `department`, `status`) VALUES
('BSCS', 'BS Computer Science', 'Information Technology', 'Active'),
('BSIT', 'BS Information Technology', 'Information Technology', 'Active'),
('BSN', 'BS Nursing', 'College of Nursing', 'Active'),
('BSBA', 'BS Business Administration', 'Business Administration', 'Active'),
('BSCpE', 'BS Computer Engineering', 'Information Technology', 'Active')
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `department`=VALUES(`department`);

-- ============================================================
--  TABLE 8: subjects
-- ============================================================
CREATE TABLE IF NOT EXISTS `subjects` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `code`          VARCHAR(20) UNIQUE NOT NULL,
    `title`         VARCHAR(150) NOT NULL,
    `description`   TEXT DEFAULT NULL,
    `lecture_units` INT NOT NULL DEFAULT 0,
    `lab_units`     INT NOT NULL DEFAULT 0,
    `lab_fee`       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `department`    VARCHAR(150) NOT NULL,
    `prerequisites` VARCHAR(150) DEFAULT 'None',
    INDEX `idx_subj_dept` (`department`),
    INDEX `idx_subj_title` (`title`)
) ENGINE=InnoDB;

INSERT INTO `subjects` (`code`, `title`, `description`, `lecture_units`, `lab_units`, `lab_fee`, `department`, `prerequisites`) VALUES
-- General Education & Common
('GE101', 'Mathematics in the Modern World', 'Core general education math course.', 3, 0, 0.00, 'General Education', 'None'),
('GE102', 'Purposive Communication', 'Writing, speaking, and presenting in multi-cultural environments.', 3, 0, 0.00, 'General Education', 'None'),
('GE103', 'Understanding the Self', 'Psychological, sociological, and philosophical perspective of self.', 3, 0, 0.00, 'General Education', 'None'),
('GE104', 'Art Appreciation', 'Aesthetic and historical appreciation of arts.', 3, 0, 0.00, 'General Education', 'None'),
('GE105', 'Science, Technology and Society', 'Interaction of science and technology with societal contexts.', 3, 0, 0.00, 'General Education', 'None'),
('GE106', 'The Contemporary World', 'Study of globalization and international issues.', 3, 0, 0.00, 'General Education', 'None'),
('GE107', 'Readings in Philippine History', 'Philippine history through primary sources.', 3, 0, 0.00, 'General Education', 'None'),
('GE108', 'Ethics', 'Principles of ethical behavior and moral reasoning.', 3, 0, 0.00, 'General Education', 'None'),
('GE109', 'Life and Works of Rizal', 'Mandatory course on Jose Rizal.', 3, 0, 0.00, 'General Education', 'None'),
('GE110', 'Technopreneurship', 'Entrepreneurship applied to engineering and technology.', 3, 0, 0.00, 'General Education', 'None'),
('PE101', 'PE 1', 'Physical Fitness and Wellness', 2, 0, 0.00, 'Physical Education', 'None'),
('PE102', 'PE 2', 'Rhythmic Activities', 2, 0, 0.00, 'Physical Education', 'PE 1'),
('PE201', 'PE 3', 'Individual/Dual Sports', 2, 0, 0.00, 'Physical Education', 'PE 2'),
('PE202', 'PE 4', 'Team Sports', 2, 0, 0.00, 'Physical Education', 'PE 3'),
('NSTP101', 'NSTP 1', 'National Service Training Program 1', 3, 0, 0.00, 'National Service Training Program', 'None'),
('NSTP102', 'NSTP 2', 'National Service Training Program 2', 3, 0, 0.00, 'National Service Training Program', 'NSTP 1'),

-- BSIT majors
('IT101', 'Introduction to Computing', 'Fundamentals of computer hardware, software, and systems.', 2, 1, 1500.00, 'BS Information Technology', 'None'),
('IT102', 'Computer Programming 1', 'Intro to procedural and structured programming.', 2, 1, 1500.00, 'BS Information Technology', 'None'),
('IT103', 'Computer Programming 2', 'Object-oriented programming constructs.', 2, 1, 1500.00, 'BS Information Technology', 'Computer Programming 1'),
('IT104', 'Discrete Mathematics', 'Mathematical structures for computer studies.', 3, 0, 0.00, 'BS Information Technology', 'Mathematics in the Modern World'),
('IT201', 'Data Structures and Algorithms', 'Arrays, linked lists, stacks, queues, trees, and searching/sorting.', 2, 1, 1500.00, 'BS Information Technology', 'Computer Programming 2'),
('IT202', 'Object-Oriented Programming', 'Inheritance, polymorphism, encapsulation.', 2, 1, 1500.00, 'BS Information Technology', 'Computer Programming 2'),
('IT203', 'Human-Computer Interaction', 'User interface design and usability principles.', 3, 0, 0.00, 'BS Information Technology', 'Introduction to Computing'),
('IT204', 'Networking 1 (Data Communications)', 'Principles of networks and hardware configurations.', 2, 1, 1500.00, 'BS Information Technology', 'Introduction to Computing'),
('IT205', 'Information Management (Database Systems)', 'Relational database schema design and SQL querying.', 2, 1, 1500.00, 'BS Information Technology', 'Data Structures and Algorithms'),
('IT206', 'Applications Development and Emerging Technologies', 'Modern full-stack web and mobile application frameworks.', 2, 1, 1500.00, 'BS Information Technology', 'Object-Oriented Programming'),
('IT207', 'Networking 2', 'Routing, switching, and advanced TCP/IP networking.', 2, 1, 1500.00, 'BS Information Technology', 'Networking 1 (Data Communications)'),
('IT301', 'Systems Integration and Architecture 1', 'Enterprise applications integration and system architectures.', 3, 0, 0.00, 'BS Information Technology', 'Applications Development and Emerging Technologies'),
('IT302', 'Information Assurance and Security 1', 'Security policies, cryptography, and network defense.', 2, 1, 1500.00, 'BS Information Technology', 'Networking 2'),
('IT303', 'Web Systems and Technologies', 'Client and server-side web scripting architectures.', 2, 1, 1500.00, 'BS Information Technology', 'Applications Development and Emerging Technologies'),
('IT304', 'Quantitative Methods', 'Linear programming, decision theory, and statistics.', 3, 0, 0.00, 'BS Information Technology', 'Discrete Mathematics'),
('IT305', 'IT Elective 1', 'Mobile App Development.', 3, 0, 0.00, 'BS Information Technology', 'Object-Oriented Programming'),
('IT306', 'Systems Integration and Architecture 2', 'Web services, APIs, and middleware deployment.', 3, 0, 0.00, 'BS Information Technology', 'Systems Integration and Architecture 1'),
('IT307', 'Information Assurance and Security 2', 'Risk analysis, digital forensics, and security auditing.', 2, 1, 1500.00, 'BS Information Technology', 'Information Assurance and Security 1'),
('IT308', 'Software Engineering', 'Software design patterns, testing, and lifecycle models.', 3, 0, 0.00, 'BS Information Technology', 'Applications Development and Emerging Technologies'),
('IT309', 'Multimedia Systems', 'Audio, video, 2D/3D graphics editing and tools.', 2, 1, 1500.00, 'BS Information Technology', 'Human-Computer Interaction'),
('IT310', 'Capstone Project 1 (Proposal)', 'Research proposal phase for information systems solutions.', 3, 0, 0.00, 'BS Information Technology', 'Software Engineering'),
('IT311', 'IT Elective 2', 'Cloud Infrastructure and Administration.', 3, 0, 0.00, 'BS Information Technology', 'IT Elective 1'),
('IT312', 'On-the-Job Training / Practicum', 'OJT placement with an external partner firm.', 0, 3, 0.00, 'BS Information Technology', 'Completion of 3rd Year'),
('IT401', 'Capstone Project 2', 'System implementation and validation phase.', 3, 0, 0.00, 'BS Information Technology', 'Capstone Project 1 (Proposal)'),
('IT402', 'Systems Administration and Maintenance', 'Linux/Windows Server configuration and script automation.', 2, 1, 1500.00, 'BS Information Technology', 'Networking 2'),
('IT403', 'IT Elective 3', 'Data Science & Big Data Analysis.', 3, 0, 0.00, 'BS Information Technology', 'None'),
('IT404', 'IT Elective 4', 'Cybersecurity Penetration Testing.', 3, 0, 0.00, 'BS Information Technology', 'None'),
('IT405', 'Capstone Project 2 (continuation) / Colloquium', 'Final capstone defense and presentation event.', 3, 0, 0.00, 'BS Information Technology', 'Capstone Project 2'),
('IT406', 'IT Elective 5', 'Internet of Things and Smart Devices.', 3, 0, 0.00, 'BS Information Technology', 'None'),
('IT407', 'Practicum', 'Extended company internship.', 0, 3, 0.00, 'BS Information Technology', 'Completion of 3rd Year'),

-- BSCS majors
('CS101', 'Introduction to Computing (CS)', 'Introductory computing concepts tailored for CS.', 2, 1, 1500.00, 'BS Computer Science', 'None'),
('CS102', 'Computer Programming 1 (CS)', 'Structured C/C++ programming for problem solving.', 2, 1, 1500.00, 'BS Computer Science', 'None'),
('CS103', 'Computer Programming 2 (CS)', 'Advanced programming techniques and pointers.', 2, 1, 1500.00, 'BS Computer Science', 'Computer Programming 1 (CS)'),
('CS104', 'Discrete Structures 1', 'Logic, sets, relations, and proof methods.', 3, 0, 0.00, 'BS Computer Science', 'Mathematics in the Modern World'),
('CS201', 'Data Structures and Algorithms (CS)', 'Fundamental CS data structures and analysis.', 2, 1, 1500.00, 'BS Computer Science', 'Computer Programming 2 (CS)'),
('CS202', 'Discrete Structures 2', 'Graphs, trees, and algebraic structures.', 3, 0, 0.00, 'BS Computer Science', 'Discrete Structures 1'),
('CS203', 'Object-Oriented Programming (CS)', 'OOP paradigm in Java and C++.', 2, 1, 1500.00, 'BS Computer Science', 'Computer Programming 2 (CS)'),
('CS204', 'Calculus', 'Limits, differentiation, and integration functions.', 3, 0, 0.00, 'BS Computer Science', 'Mathematics in the Modern World'),
('CS205', 'Algorithms and Complexity', 'Asymptotic analysis, divide-conquer, greedy, dynamic programming.', 3, 0, 0.00, 'BS Computer Science', 'Data Structures and Algorithms (CS)'),
('CS206', 'Information Management', 'DBMS architectures, index structures, queries.', 2, 1, 1500.00, 'BS Computer Science', 'Data Structures and Algorithms (CS)'),
('CS207', 'Computer Organization and Architecture', 'Logic design, registers, ALU, control logic.', 2, 1, 1500.00, 'BS Computer Science', 'Discrete Structures 2'),
('CS208', 'Human-Computer Interaction (CS)', 'UI ergonomics and interaction models.', 3, 0, 0.00, 'BS Computer Science', 'Introduction to Computing (CS)'),
('CS209', 'Probability and Statistics', 'Distributions, regression, and tests of hypothesis.', 3, 0, 0.00, 'BS Computer Science', 'Mathematics in the Modern World'),
('CS301', 'Automata Theory and Formal Languages', 'Regular languages, context-free languages, Turing machines.', 3, 0, 0.00, 'BS Computer Science', 'Discrete Structures 2'),
('CS302', 'Operating Systems', 'Kernel designs, IPC, file systems, page tables.', 2, 1, 1500.00, 'BS Computer Science', 'Computer Organization and Architecture'),
('CS303', 'Programming Languages', 'Grammars, parsing, scopes, types, and compiler frontends.', 3, 0, 0.00, 'BS Computer Science', 'Object-Oriented Programming (CS)'),
('CS304', 'Networks and Communications', 'TCP/IP socket programming and packet analyses.', 2, 1, 1500.00, 'BS Computer Science', 'Computer Organization and Architecture'),
('CS305', 'Software Engineering 1', 'Requirements analysis, modeling, and architectures.', 3, 0, 0.00, 'BS Computer Science', 'Object-Oriented Programming (CS)'),
('CS306', 'Software Engineering 2', 'Software QA, testing methods, CI/CD cycles.', 3, 0, 0.00, 'BS Computer Science', 'Software Engineering 1'),
('CS307', 'Information Assurance and Security', 'Network security and cryptography concepts.', 2, 1, 1500.00, 'BS Computer Science', 'Networks and Communications'),
('CS308', 'Numerical/Scientific Computing', 'Error propagation, root finding, matrix computation.', 3, 0, 0.00, 'BS Computer Science', 'Calculus'),
('CS309', 'Artificial Intelligence', 'Heuristics, search trees, expert networks, basic neural nets.', 2, 1, 1500.00, 'BS Computer Science', 'Algorithms and Complexity'),
('CS310', 'Methods of Research in Computing', 'Academic research methods and paper planning.', 3, 0, 0.00, 'BS Computer Science', 'Probability and Statistics'),
('CS311', 'Social Issues and Professional Practice', 'Computing laws, privacy, IP, and ethics.', 3, 0, 0.00, 'BS Computer Science', 'None'),
('CS401', 'Thesis/Capstone Project 1', 'Research concept paper and draft proposal formulation.', 3, 0, 0.00, 'BS Computer Science', 'Methods of Research in Computing'),
('CS402', 'CS Elective 1 (e.g., Machine Learning)', 'Supervised and unsupervised learning algos.', 3, 0, 0.00, 'BS Computer Science', 'None'),
('CS403', 'CS Elective 2', 'Parallel and Distributed Systems.', 3, 0, 0.00, 'BS Computer Science', 'None'),
('CS404', 'Thesis/Capstone Project 2', 'Implementation, system testing, and final defense.', 3, 0, 0.00, 'BS Computer Science', 'Thesis/Capstone Project 1'),
('CS405', 'Practicum/OJT', 'Field work internship program.', 0, 3, 0.00, 'BS Computer Science', 'Completion of 3rd Year'),
('CS406', 'CS Elective 3', 'Computer Graphics and Shader Design.', 3, 0, 0.00, 'BS Computer Science', 'None'),

-- BSCpE majors
('COE101', 'Computer Programming 1 (CpE)', 'Procedural program design.', 2, 1, 1500.00, 'BS Computer Engineering', 'None'),
('COE102', 'College Algebra/Pre-Calculus', 'Functions, trigonometric expressions, systems of equations.', 3, 0, 0.00, 'BS Computer Engineering', 'None'),
('COE103', 'Chemistry for Engineers', 'Chemistry applications in structural systems.', 2, 1, 1500.00, 'BS Computer Engineering', 'None'),
('COE104', 'Computer Programming 2 (CpE)', 'Object-oriented programming concepts in C++.', 2, 1, 1500.00, 'BS Computer Engineering', 'Computer Programming 1 (CpE)'),
('COE105', 'Calculus 1', 'Differentiation and application of rates.', 3, 0, 0.00, 'BS Computer Engineering', 'College Algebra/Pre-Calculus'),
('COE106', 'Physics for Engineers 1', 'Mechanics, heat, and thermodynamics laws.', 2, 1, 1500.00, 'BS Computer Engineering', 'College Algebra/Pre-Calculus'),
('COE107', 'Engineering Drawing/CAD', 'Computer-aided design layout models.', 1, 1, 1200.00, 'BS Computer Engineering', 'None'),
('COE201', 'Data Structures and Algorithms (CpE)', 'Common structures and sorting methods.', 2, 1, 1500.00, 'BS Computer Engineering', 'Computer Programming 2 (CpE)'),
('COE202', 'Calculus 2', 'Integration, volumes of revolution, power series.', 3, 0, 0.00, 'BS Computer Engineering', 'Calculus 1'),
('COE203', 'Physics for Engineers 2', 'Electromagnetism, wave optics, modern physics.', 2, 1, 1500.00, 'BS Computer Engineering', 'Physics for Engineers 1'),
('COE204', 'Discrete Mathematics (CpE)', 'Discrete calculations and set theory.', 3, 0, 0.00, 'BS Computer Engineering', 'Mathematics in the Modern World'),
('COE205', 'Electrical Circuits 1', 'DC/AC network analysis and theorems.', 2, 1, 1500.00, 'BS Computer Engineering', 'Physics for Engineers 2'),
('COE206', 'Object-Oriented Programming (CpE)', 'Applied class layouts in Java/C++.', 2, 1, 1500.00, 'BS Computer Engineering', 'Computer Programming 2 (CpE)'),
('COE207', 'Differential Equations', 'Solving ODEs and applications.', 3, 0, 0.00, 'BS Computer Engineering', 'Calculus 2'),
('COE208', 'Fundamentals of Electronic Circuits', 'Diode, transistor modeling, and amplifiers.', 2, 1, 1500.00, 'BS Computer Engineering', 'Electrical Circuits 1'),
('COE209', 'Numerical Methods', 'Nonlinear equations, interpolations, integrations.', 3, 0, 0.00, 'BS Computer Engineering', 'Differential Equations'),
('COE210', 'Data Science and Machine Learning (intro)', 'Intro to data preparation and regressors.', 2, 1, 1500.00, 'BS Computer Engineering', 'Discrete Mathematics (CpE)'),
('COE211', 'Engineering Economics', 'Time value of money, amortization, and projects evaluation.', 3, 0, 0.00, 'BS Computer Engineering', 'Calculus 1'),
('COE301', 'Digital Logic Design', 'Gate architectures, multiplexers, state machines.', 2, 1, 1500.00, 'BS Computer Engineering', 'Fundamentals of Electronic Circuits'),
('COE302', 'Data Communications and Networking 1', 'OSI model layers and LAN setup.', 2, 1, 1500.00, 'BS Computer Engineering', 'None'),
('COE303', 'Computer Architecture and Organization', 'Processor design, pipelines, micro-op sets.', 3, 0, 0.00, 'BS Computer Engineering', 'Digital Logic Design'),
('COE304', 'Feedback and Control Systems', 'Transfer functions, block diagrams, stability.', 2, 1, 1500.00, 'BS Computer Engineering', 'Differential Equations'),
('COE305', 'Probability and Statistics (CpE)', 'Continuous distributions, variance analysis.', 3, 0, 0.00, 'BS Computer Engineering', 'None'),
('COE306', 'Microprocessor Systems', 'Register files, timers, assembly logic.', 2, 1, 1500.00, 'BS Computer Engineering', 'Computer Architecture and Organization'),
('COE307', 'Operating Systems (CpE)', 'Processes scheduling, threads, synchronization.', 2, 1, 1500.00, 'BS Computer Engineering', 'Computer Architecture and Organization'),
('COE308', 'Data Communications and Networking 2', 'WAN technologies and protocol setups.', 2, 1, 1500.00, 'BS Computer Engineering', 'Data Communications and Networking 1'),
('COE309', 'Embedded Systems', 'IoT microcontrollers, sensors, real-time code.', 2, 1, 1500.00, 'BS Computer Engineering', 'Microprocessor Systems'),
('COE310', 'Signals, Spectra and Signal Processing', 'Fourier transform, filter models.', 2, 1, 1500.00, 'BS Computer Engineering', 'Feedback and Control Systems'),
('COE311', 'System and Network Administration', 'Server deployments and security configs.', 2, 1, 1500.00, 'BS Computer Engineering', 'Data Communications and Networking 1'),
('COE401', 'CpE Design Project 1 (Capstone 1)', 'Capstone proposal and prototyping.', 3, 0, 0.00, 'BS Computer Engineering', 'Completion of 3rd Year'),
('COE402', 'Advanced Microprocessor Systems', 'Multicore, superscalar designs, GPU logic.', 2, 1, 1500.00, 'BS Computer Engineering', 'Microprocessor Systems'),
('COE403', 'CpE Elective 1', 'Advanced Embedded Software Development.', 3, 0, 0.00, 'BS Computer Engineering', 'None'),
('COE404', 'CpE Design Project 2 (Capstone 2)', 'Capstone fabrication and final presentation.', 3, 0, 0.00, 'BS Computer Engineering', 'CpE Design Project 1 (Capstone 1)'),
('COE405', 'Practicum/OJT (CpE)', 'Industry engineering training.', 0, 3, 0.00, 'BS Computer Engineering', 'Completion of 3rd Year'),
('COE406', 'CpE Elective 2', 'Hardware Description Languages & FPGA Design.', 3, 0, 0.00, 'BS Computer Engineering', 'None'),

-- BSN Catalog
('NUR101', 'Anatomy and Physiology', 'Study of human body systems.', 3, 1, 2000.00, 'BS Nursing', 'None'),
('NUR102', 'Microbiology and Parasitology', 'Microbes and parasites of medical importance.', 3, 1, 1800.00, 'BS Nursing', 'NUR101'),
('NUR201', 'Pharmacology', 'Mechanism of drug action and dosage.', 3, 0, 0.00, 'BS Nursing', 'NUR102'),
('NUR202', 'Nutrition and Diet Therapy', 'Role of nutrition in disease management.', 2, 1, 1500.00, 'BS Nursing', 'NUR201'),
('NUR301', 'Medical-Surgical Nursing 1', 'Nursing care for surgical conditions.', 3, 2, 3000.00, 'BS Nursing', 'NUR201'),
('NUR302', 'Medical-Surgical Nursing 2', 'Advanced nursing care for operations.', 3, 2, 3000.00, 'BS Nursing', 'NUR301'),
('NUR401', 'Nursing Research 1', 'Research method applications in health sciences.', 3, 0, 0.00, 'BS Nursing', 'NUR302'),
('NUR402', 'Intensive Nursing Practicum', 'Intensive clinical practice rotation.', 0, 6, 5000.00, 'BS Nursing', 'NUR401'),

-- BSBA Catalog
('BA101', 'Introduction to Business', 'Principles of business operations.', 3, 0, 0.00, 'BS Business Administration', 'None'),
('BA102', 'Microeconomics', 'Economic behavior of individual consumers.', 3, 0, 0.00, 'BS Business Administration', 'BA101'),
('BA201', 'Financial Accounting', 'Recording financial transactions and logs.', 3, 0, 0.00, 'BS Business Administration', 'BA102'),
('BA202', 'Marketing Management', 'Product planning, pricing, and campaigns.', 3, 0, 0.00, 'BS Business Administration', 'BA201'),
('BA301', 'Human Resource Management', 'Recruitment, training, and labor relations.', 3, 0, 0.00, 'BS Business Administration', 'BA202'),
('BA302', 'Business Law', 'Legal frameworks for business transactions.', 3, 0, 0.00, 'BS Business Administration', 'BA301'),
('BA401', 'Strategic Management', 'Corporate strategy formulations.', 3, 0, 0.00, 'BS Business Administration', 'BA302'),
('BA402', 'Business Internship', 'Supervised industry internship.', 0, 6, 0.00, 'BS Business Administration', 'BA401')
ON DUPLICATE KEY UPDATE `title`=VALUES(`title`), `description`=VALUES(`description`), `lecture_units`=VALUES(`lecture_units`), `lab_units`=VALUES(`lab_units`), `lab_fee`=VALUES(`lab_fee`);

-- ============================================================
--  TABLE 9: curriculum
-- ============================================================
CREATE TABLE IF NOT EXISTS `curriculum` (
    `id`                 INT AUTO_INCREMENT PRIMARY KEY,
    `program`            VARCHAR(150) NOT NULL,
    `subject`            VARCHAR(150) NOT NULL,
    `year_level`         VARCHAR(50) NOT NULL,
    `semester`           VARCHAR(50) NOT NULL,
    `elective`           TINYINT(1) DEFAULT 0,
    `curriculum_version` VARCHAR(100) DEFAULT '2022 Curriculum',
    INDEX `idx_curr_lookup` (`program`, `year_level`, `semester`, `curriculum_version`),
    UNIQUE KEY `idx_curr_unique` (`program`, `subject`, `year_level`, `semester`, `curriculum_version`)
) ENGINE=InnoDB;

INSERT INTO `curriculum` (`program`, `subject`, `year_level`, `semester`, `elective`) VALUES
-- BSCS Mapping
('BS Computer Science', 'Introduction to Computing (CS)', '1st Year', '1st Semester', 0),
('BS Computer Science', 'Computer Programming 1 (CS)', '1st Year', '1st Semester', 0),
('BS Computer Science', 'Mathematics in the Modern World', '1st Year', '1st Semester', 0),
('BS Computer Science', 'Understanding the Self', '1st Year', '1st Semester', 0),
('BS Computer Science', 'Purposive Communication', '1st Year', '1st Semester', 0),
('BS Computer Science', 'PE 1', '1st Year', '1st Semester', 0),
('BS Computer Science', 'NSTP 1', '1st Year', '1st Semester', 0),
('BS Computer Science', 'Computer Programming 2 (CS)', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'Discrete Structures 1', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'Art Appreciation', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'Science, Technology and Society', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'The Contemporary World', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'PE 2', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'NSTP 2', '1st Year', '2nd Semester', 0),
('BS Computer Science', 'Data Structures and Algorithms (CS)', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'Discrete Structures 2', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'Object-Oriented Programming (CS)', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'Calculus', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'Readings in Philippine History', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'PE 3', '2nd Year', '1st Semester', 0),
('BS Computer Science', 'Algorithms and Complexity', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'Information Management', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'Computer Organization and Architecture', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'Human-Computer Interaction (CS)', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'Probability and Statistics', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'PE 4', '2nd Year', '2nd Semester', 0),
('BS Computer Science', 'Automata Theory and Formal Languages', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Operating Systems', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Programming Languages', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Networks and Communications', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Software Engineering 1', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Ethics', '3rd Year', '1st Semester', 0),
('BS Computer Science', 'Software Engineering 2', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Information Assurance and Security', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Numerical/Scientific Computing', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Artificial Intelligence', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Methods of Research in Computing', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Social Issues and Professional Practice', '3rd Year', '2nd Semester', 0),
('BS Computer Science', 'Thesis/Capstone Project 1', '4th Year', '1st Semester', 0),
('BS Computer Science', 'CS Elective 1 (e.g., Machine Learning)', '4th Year', '1st Semester', 1),
('BS Computer Science', 'CS Elective 2', '4th Year', '1st Semester', 1),
('BS Computer Science', 'Technopreneurship', '4th Year', '1st Semester', 0),
('BS Computer Science', 'Thesis/Capstone Project 2', '4th Year', '2nd Semester', 0),
('BS Computer Science', 'Practicum/OJT', '4th Year', '2nd Semester', 0),
('BS Computer Science', 'CS Elective 3', '4th Year', '2nd Semester', 1),

-- BSIT Mapping
('BS Information Technology', 'Introduction to Computing', '1st Year', '1st Semester', 0),
('BS Information Technology', 'Computer Programming 1', '1st Year', '1st Semester', 0),
('BS Information Technology', 'Mathematics in the Modern World', '1st Year', '1st Semester', 0),
('BS Information Technology', 'Purposive Communication', '1st Year', '1st Semester', 0),
('BS Information Technology', 'Understanding the Self', '1st Year', '1st Semester', 0),
('BS Information Technology', 'PE 1', '1st Year', '1st Semester', 0),
('BS Information Technology', 'NSTP 1', '1st Year', '1st Semester', 0),
('BS Information Technology', 'Computer Programming 2', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'Discrete Mathematics', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'Art Appreciation', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'Science, Technology and Society', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'The Contemporary World', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'PE 2', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'NSTP 2', '1st Year', '2nd Semester', 0),
('BS Information Technology', 'Data Structures and Algorithms', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'Object-Oriented Programming', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'Human-Computer Interaction', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'Networking 1 (Data Communications)', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'Readings in Philippine History', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'PE 3', '2nd Year', '1st Semester', 0),
('BS Information Technology', 'Information Management (Database Systems)', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'Applications Development and Emerging Technologies', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'Networking 2', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'Ethics', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'Life and Works of Rizal', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'PE 4', '2nd Year', '2nd Semester', 0),
('BS Information Technology', 'Systems Integration and Architecture 1', '3rd Year', '1st Semester', 0),
('BS Information Technology', 'Information Assurance and Security 1', '3rd Year', '1st Semester', 0),
('BS Information Technology', 'Web Systems and Technologies', '3rd Year', '1st Semester', 0),
('BS Information Technology', 'Quantitative Methods', '3rd Year', '1st Semester', 0),
('BS Information Technology', 'IT Elective 1', '3rd Year', '1st Semester', 1),
('BS Information Technology', 'Systems Integration and Architecture 2', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'Information Assurance and Security 2', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'Software Engineering', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'Multimedia Systems', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'Technopreneurship', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'Capstone Project 1 (Proposal)', '3rd Year', '2nd Semester', 0),
('BS Information Technology', 'IT Elective 2', '3rd Year', '2nd Semester', 1),
('BS Information Technology', 'On-the-Job Training / Practicum', '3rd Year', 'Summer', 0),
('BS Information Technology', 'Capstone Project 2', '4th Year', '1st Semester', 0),
('BS Information Technology', 'Systems Administration and Maintenance', '4th Year', '1st Semester', 0),
('BS Information Technology', 'IT Elective 3', '4th Year', '1st Semester', 1),
('BS Information Technology', 'IT Elective 4', '4th Year', '1st Semester', 1),
('BS Information Technology', 'Capstone Project 2 (continuation) / Colloquium', '4th Year', '2nd Semester', 0),
('BS Information Technology', 'IT Elective 5', '4th Year', '2nd Semester', 1),
('BS Information Technology', 'Practicum', '4th Year', '2nd Semester', 0),

-- BSCOE Mapping
('BS Computer Engineering', 'Computer Programming 1 (CpE)', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'College Algebra/Pre-Calculus', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'Chemistry for Engineers', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'Understanding the Self', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'Purposive Communication', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'PE 1', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'NSTP 1', '1st Year', '1st Semester', 0),
('BS Computer Engineering', 'Computer Programming 2 (CpE)', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'Calculus 1', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'Physics for Engineers 1', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'Engineering Drawing/CAD', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'Mathematics in the Modern World', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'PE 2', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'NSTP 2', '1st Year', '2nd Semester', 0),
('BS Computer Engineering', 'Data Structures and Algorithms (CpE)', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Calculus 2', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Physics for Engineers 2', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Discrete Mathematics (CpE)', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Electrical Circuits 1', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Readings in Philippine History', '2nd Year', '1st Semester', 0),
('BS Computer Engineering', 'Object-Oriented Programming (CpE)', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Differential Equations', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Fundamentals of Electronic Circuits', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Numerical Methods', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Data Science and Machine Learning (intro)', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Engineering Economics', '2nd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Digital Logic Design', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Data Communications and Networking 1', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Computer Architecture and Organization', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Feedback and Control Systems', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Probability and Statistics (CpE)', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Ethics', '3rd Year', '1st Semester', 0),
('BS Computer Engineering', 'Microprocessor Systems', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Operating Systems (CpE)', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Data Communications and Networking 2', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Embedded Systems', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'Signals, Spectra and Signal Processing', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'System and Network Administration', '3rd Year', '2nd Semester', 0),
('BS Computer Engineering', 'CpE Design Project 1 (Capstone 1)', '4th Year', '1st Semester', 0),
('BS Computer Engineering', 'Advanced Microprocessor Systems', '4th Year', '1st Semester', 0),
('BS Computer Engineering', 'CpE Elective 1', '4th Year', '1st Semester', 1),
('BS Computer Engineering', 'Technopreneurship', '4th Year', '1st Semester', 0),
('BS Computer Engineering', 'CpE Design Project 2 (Capstone 2)', '4th Year', '2nd Semester', 0),
('BS Computer Engineering', 'Practicum/OJT (CpE)', '4th Year', '2nd Semester', 0),
('BS Computer Engineering', 'CpE Elective 2', '4th Year', '2nd Semester', 1),

-- BSN Mapping
('BS Nursing', 'Anatomy and Physiology', '1st Year', '1st Semester', 0),
('BS Nursing', 'Microbiology and Parasitology', '1st Year', '2nd Semester', 0),
('BS Nursing', 'Pharmacology', '2nd Year', '1st Semester', 0),
('BS Nursing', 'Nutrition and Diet Therapy', '2nd Year', '2nd Semester', 0),
('BS Nursing', 'Medical-Surgical Nursing 1', '3rd Year', '1st Semester', 0),
('BS Nursing', 'Medical-Surgical Nursing 2', '3rd Year', '2nd Semester', 0),
('BS Nursing', 'Nursing Research 1', '4th Year', '1st Semester', 0),
('BS Nursing', 'Intensive Nursing Practicum', '4th Year', '2nd Semester', 0),

-- BSBA Mapping
('BS Business Administration', 'Introduction to Business', '1st Year', '1st Semester', 0),
('BS Business Administration', 'Microeconomics', '1st Year', '2nd Semester', 0),
('BS Business Administration', 'Financial Accounting', '2nd Year', '1st Semester', 0),
('BS Business Administration', 'Marketing Management', '2nd Year', '2nd Semester', 0),
('BS Business Administration', 'Human Resource Management', '3rd Year', '1st Semester', 0),
('BS Business Administration', 'Business Law', '3rd Year', '2nd Semester', 0),
('BS Business Administration', 'Strategic Management', '4th Year', '1st Semester', 0),
('BS Business Administration', 'Business Internship', '4th Year', '2nd Semester', 0)
ON DUPLICATE KEY UPDATE `program`=VALUES(`program`), `subject`=VALUES(`subject`), `year_level`=VALUES(`year_level`), `semester`=VALUES(`semester`);

-- ============================================================
--  TABLE 10: academic_periods
-- ============================================================
CREATE TABLE IF NOT EXISTS `academic_periods` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `name`             VARCHAR(150) NOT NULL,
    `academic_year`    VARCHAR(50) NOT NULL,
    `semester`         VARCHAR(50) NOT NULL,
    `enrollment_start` DATE DEFAULT NULL,
    `enrollment_end`   DATE DEFAULT NULL,
    `status`           VARCHAR(20) DEFAULT 'Inactive',
    INDEX `idx_period_status` (`status`),
    INDEX `idx_period_ay_sem` (`academic_year`, `semester`)
) ENGINE=InnoDB;

INSERT INTO `academic_periods` (`name`, `academic_year`, `semester`, `enrollment_start`, `enrollment_end`, `status`) VALUES
('1st Semester, A.Y. 2026-2027', '2026-2027', '1st Semester', '2026-07-01', '2026-09-30', 'Active'),
('2nd Semester, A.Y. 2026-2027', '2026-2027', '2nd Semester', '2026-11-01', '2026-11-30', 'Inactive')
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `academic_year`=VALUES(`academic_year`), `semester`=VALUES(`semester`), `enrollment_start`=VALUES(`enrollment_start`), `enrollment_end`=VALUES(`enrollment_end`), `status`=VALUES(`status`);

-- ============================================================
--  TABLE 11: subject_sections
-- ============================================================
CREATE TABLE IF NOT EXISTS `subject_sections` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `program`    VARCHAR(150) NOT NULL,
    `year_level` VARCHAR(50) NOT NULL,
    `semester`   VARCHAR(50) NOT NULL,
    `subject`    VARCHAR(150) NOT NULL,
    `code`       VARCHAR(50) UNIQUE NOT NULL,
    `instructor` VARCHAR(150) NOT NULL,
    `days`       VARCHAR(50) NOT NULL,
    `time`       VARCHAR(100) NOT NULL,
    `room`       VARCHAR(50) NOT NULL,
    `capacity`   INT NOT NULL,
    `section_id` INT DEFAULT NULL,
    `professor_id` INT DEFAULT NULL,
    INDEX `idx_ss_lookup` (`program`, `year_level`, `semester`, `subject`),
    INDEX `idx_ss_section_id` (`section_id`),
    INDEX `idx_ss_capacity` (`capacity`),
    INDEX `idx_ss_professor` (`professor_id`)
) ENGINE=InnoDB;

INSERT INTO `subject_sections` (`program`, `year_level`, `semester`, `subject`, `code`, `instructor`, `days`, `time`, `room`, `capacity`) VALUES
-- BSIT Year 1 Semester 1 Sections
('BS Information Technology', '1st Year', '1st Semester', 'Introduction to Computing', 'IT-IT101-A', 'Prof. Steve Jobs', 'MW', '09:00 AM - 10:30 AM', 'Lab 1', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Computer Programming 1', 'IT-IT102-A', 'Prof. Dennis Ritchie', 'MW', '10:30 AM - 12:00 PM', 'Lab 2', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Mathematics in the Modern World', 'IT-GE101-A', 'Dr. Pythagoras', 'TTH', '01:00 PM - 02:30 PM', 'Room 201', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Purposive Communication', 'IT-GE102-A', 'Dr. Shakespeare', 'TTH', '02:30 PM - 04:00 PM', 'Room 202', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Understanding the Self', 'IT-GE103-A', 'Dr. Freud', 'MW', '08:00 AM - 09:30 AM', 'Room 203', 40),
('BS Information Technology', '1st Year', '1st Semester', 'PE 1', 'IT-PE101-A', 'Coach Carter', 'F', '04:00 PM - 06:00 PM', 'Gymnasium', 40),
('BS Information Technology', '1st Year', '1st Semester', 'NSTP 1', 'IT-NSTP101-A', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Introduction to Computing', 'IT-IT101-B', 'Prof. Steve Jobs', 'MW', '09:00 AM - 10:30 AM', 'Lab 1', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Computer Programming 1', 'IT-IT102-B', 'Prof. Dennis Ritchie', 'MW', '10:30 AM - 12:00 PM', 'Lab 2', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Mathematics in the Modern World', 'IT-GE101-B', 'Dr. Pythagoras', 'TTH', '01:00 PM - 02:30 PM', 'Room 201', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Purposive Communication', 'IT-GE102-B', 'Dr. Shakespeare', 'TTH', '02:30 PM - 04:00 PM', 'Room 202', 40),
('BS Information Technology', '1st Year', '1st Semester', 'Understanding the Self', 'IT-GE103-B', 'Dr. Freud', 'MW', '08:00 AM - 09:30 AM', 'Room 203', 40),
('BS Information Technology', '1st Year', '1st Semester', 'PE 1', 'IT-PE101-B', 'Coach Carter', 'F', '04:00 PM - 06:00 PM', 'Gymnasium', 40),
('BS Information Technology', '1st Year', '1st Semester', 'NSTP 1', 'IT-NSTP101-B', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 40),

-- BSCS Year 1 Semester 1 Sections
('BS Computer Science', '1st Year', '1st Semester', 'Introduction to Computing (CS)', 'CS-CS101-A', 'Prof. Alan Turing', 'TTH', '09:00 AM - 10:30 AM', 'Lab 1', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Computer Programming 1 (CS)', 'CS-CS102-A', 'Prof. Grace Hopper', 'TTH', '10:30 AM - 12:00 PM', 'Lab 2', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Mathematics in the Modern World', 'CS-GE101-A', 'Dr. Pythagoras', 'MW', '01:00 PM - 02:30 PM', 'Room 201', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Understanding the Self', 'CS-GE103-A', 'Dr. Freud', 'MW', '02:30 PM - 04:00 PM', 'Room 202', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Purposive Communication', 'CS-GE102-A', 'Dr. Shakespeare', 'TTH', '08:00 AM - 09:30 AM', 'Room 203', 40),
('BS Computer Science', '1st Year', '1st Semester', 'PE 1', 'CS-PE101-A', 'Coach Carter', 'F', '02:00 PM - 04:00 PM', 'Gymnasium', 40),
('BS Computer Science', '1st Year', '1st Semester', 'NSTP 1', 'CS-NSTP101-A', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Introduction to Computing (CS)', 'CS-CS101-B', 'Prof. Alan Turing', 'TTH', '09:00 AM - 10:30 AM', 'Lab 1', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Computer Programming 1 (CS)', 'CS-CS102-B', 'Prof. Grace Hopper', 'TTH', '10:30 AM - 12:00 PM', 'Lab 2', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Mathematics in the Modern World', 'CS-GE101-B', 'Dr. Pythagoras', 'MW', '01:00 PM - 02:30 PM', 'Room 201', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Understanding the Self', 'CS-GE103-B', 'Dr. Freud', 'MW', '02:30 PM - 04:00 PM', 'Room 202', 40),
('BS Computer Science', '1st Year', '1st Semester', 'Purposive Communication', 'CS-GE102-B', 'Dr. Shakespeare', 'TTH', '08:00 AM - 09:30 AM', 'Room 203', 40),
('BS Computer Science', '1st Year', '1st Semester', 'PE 1', 'CS-PE101-B', 'Coach Carter', 'F', '02:00 PM - 04:00 PM', 'Gymnasium', 40),
('BS Computer Science', '1st Year', '1st Semester', 'NSTP 1', 'CS-NSTP101-B', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 40),

-- BSCOE Year 1 Semester 1 Sections
('BS Computer Engineering', '1st Year', '1st Semester', 'Computer Programming 1 (CpE)', 'COE-COE101-A', 'Prof. Steve Wozniak', 'MW', '08:00 AM - 09:30 AM', 'Lab 3', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'College Algebra/Pre-Calculus', 'COE-COE102-A', 'Dr. Euler', 'TTH', '10:30 AM - 12:00 PM', 'Room 301', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Chemistry for Engineers', 'COE-COE103-A', 'Dr. Nobel', 'MW', '01:00 PM - 03:00 PM', 'Science Lab', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Understanding the Self', 'COE-GE103-A', 'Dr. Freud', 'TTH', '03:00 PM - 04:30 PM', 'Room 302', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Purposive Communication', 'COE-GE102-A', 'Dr. Shakespeare', 'MW', '08:00 AM - 09:30 AM', 'Room 303', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'PE 1', 'COE-PE101-A', 'Coach Carter', 'F', '10:00 AM - 12:00 PM', 'Gymnasium', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'NSTP 1', 'COE-NSTP101-A', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Computer Programming 1 (CpE)', 'COE-COE101-B', 'Prof. Steve Wozniak', 'MW', '08:00 AM - 09:30 AM', 'Lab 3', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'College Algebra/Pre-Calculus', 'COE-COE102-B', 'Dr. Euler', 'TTH', '10:30 AM - 12:00 PM', 'Room 301', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Chemistry for Engineers', 'COE-COE103-B', 'Dr. Nobel', 'MW', '01:00 PM - 03:00 PM', 'Science Lab', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Understanding the Self', 'COE-GE103-B', 'Dr. Freud', 'TTH', '03:00 PM - 04:30 PM', 'Room 302', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'Purposive Communication', 'COE-GE102-B', 'Dr. Shakespeare', 'MW', '08:00 AM - 09:30 AM', 'Room 303', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'PE 1', 'COE-PE101-B', 'Coach Carter', 'F', '10:00 AM - 12:00 PM', 'Gymnasium', 30),
('BS Computer Engineering', '1st Year', '1st Semester', 'NSTP 1', 'COE-NSTP101-B', 'Major Payne', 'S', '08:00 AM - 11:00 AM', 'Quadrangle', 30)
ON DUPLICATE KEY UPDATE `instructor`=VALUES(`instructor`), `days`=VALUES(`days`), `time`=VALUES(`time`), `room`=VALUES(`room`), `capacity`=VALUES(`capacity`), `program`=VALUES(`program`), `year_level`=VALUES(`year_level`), `semester`=VALUES(`semester`);

-- ============================================================
--  TABLE 12: fee_schedule
-- ============================================================
CREATE TABLE IF NOT EXISTS `fee_schedule` (
    `id`       INT AUTO_INCREMENT PRIMARY KEY,
    `type`     VARCHAR(50) NOT NULL,
    `label`    VARCHAR(150) NOT NULL,
    `amount`   DECIMAL(10,2) NOT NULL,
    `per_unit` TINYINT(1) DEFAULT 0,
    INDEX `idx_fee_type` (`type`),
    UNIQUE KEY `idx_fee_unique` (`type`, `label`)
) ENGINE=InnoDB;

INSERT INTO `fee_schedule` (`type`, `label`, `amount`, `per_unit`) VALUES
('Tuition', 'Tuition Fee per Unit', 650.00, 1),
('Miscellaneous', 'Registration Fee', 1500.00, 0),
('Miscellaneous', 'Library Fee', 800.00, 0),
('Laboratory', 'Computer Lab Fee', 2000.00, 0),
('Laboratory', 'Science Lab Fee', 2500.00, 0)
ON DUPLICATE KEY UPDATE `label`=VALUES(`label`), `amount`=VALUES(`amount`), `per_unit`=VALUES(`per_unit`);

-- ============================================================
--  TABLE 13: departments
-- ============================================================
CREATE TABLE IF NOT EXISTS `departments` (
    `id`     INT AUTO_INCREMENT PRIMARY KEY,
    `code`   VARCHAR(50) UNIQUE NOT NULL,
    `name`   VARCHAR(150) NOT NULL,
    `status` VARCHAR(20) DEFAULT 'Active',
    INDEX `idx_dept_status` (`status`)
) ENGINE=InnoDB;

INSERT INTO `departments` (`code`, `name`, `status`) VALUES
('CCS', 'Information Technology', 'Active'),
('CHS', 'College of Nursing', 'Active'),
('COB', 'Business Administration', 'Active'),
('GED', 'General Education', 'Active'),
('NSTP', 'National Service Training Program', 'Active'),
('PE', 'Physical Education', 'Active')
ON DUPLICATE KEY UPDATE `status`=VALUES(`status`);

-- ============================================================
--  TABLE 14: sections
-- ============================================================
CREATE TABLE IF NOT EXISTS `sections` (
    `id`                 INT AUTO_INCREMENT PRIMARY KEY,
    `code`               VARCHAR(50) NOT NULL, -- e.g. "A", "B"
    `program`            VARCHAR(150) NOT NULL,
    `year_level`         VARCHAR(50) NOT NULL,
    `academic_period_id` INT NOT NULL,
    `curriculum_version` VARCHAR(50) NOT NULL DEFAULT '2022 Curriculum',
    `capacity`           INT NOT NULL DEFAULT 40,
    `adviser`            VARCHAR(150) DEFAULT NULL,
    UNIQUE KEY `unique_section_cohort` (`code`, `program`, `year_level`, `academic_period_id`),
    INDEX `idx_sect_period` (`academic_period_id`),
    INDEX `idx_sect_prog_yr` (`program`, `year_level`)
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 15: audit_logs
--  System-wide structured audit trail for workstation actions.
-- ============================================================
CREATE TABLE IF NOT EXISTS `audit_logs` (
    `id`                 INT AUTO_INCREMENT PRIMARY KEY,
    `reference_number`  VARCHAR(50) NOT NULL,
    `operator_username` VARCHAR(50) NOT NULL,
    `station_role`       VARCHAR(50) NOT NULL,
    `action_performed`  VARCHAR(100) NOT NULL,
    `previous_state`    JSON NULL,
    `new_state`         JSON NULL,
    `created_at`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_ref_num` (`reference_number`),
    INDEX `idx_operator` (`operator_username`),
    INDEX `idx_audit_created` (`created_at`),
    INDEX `idx_audit_action` (`action_performed`)
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 16: password_resets
--  Stores hashed password reset tokens and verification codes.
-- ============================================================
CREATE TABLE IF NOT EXISTS `password_resets` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `email`      VARCHAR(150) NOT NULL,
    `token`      VARCHAR(255) NOT NULL,
    `code`       VARCHAR(6) NOT NULL,
    `attempts`   INT DEFAULT 0,
    `user_type`  VARCHAR(20) DEFAULT 'STUDENT',
    `expires_at` DATETIME NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_email` (`email`),
    INDEX `idx_code` (`code`),
    INDEX `idx_token` (`token`),
    INDEX `idx_expires` (`expires_at`)
) ENGINE=InnoDB;

-- ============================================================
--  TABLE 17: announcements
--  Admin-authored campus announcements with media attachments.
-- ============================================================
CREATE TABLE IF NOT EXISTS `announcements` (
    `id`              INT AUTO_INCREMENT PRIMARY KEY,
    `title`           VARCHAR(255) NOT NULL,
    `category`        VARCHAR(50) DEFAULT 'GENERAL',
    `content`         TEXT NOT NULL,
    `image_url`       VARCHAR(255) DEFAULT NULL,
    `author_id`       INT DEFAULT NULL,
    `author_name`     VARCHAR(100) DEFAULT 'GNCP Administration',
    `target_audience` VARCHAR(50) DEFAULT 'ALL',
    `subject_code`    VARCHAR(50) DEFAULT NULL,
    `is_pinned`       TINYINT(1) DEFAULT 0,
    `status`          VARCHAR(20) DEFAULT 'PUBLISHED',
    `created_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_status_pinned_created` (`status`, `is_pinned`, `created_at`),
    INDEX `idx_category` (`category`),
    INDEX `idx_author_id` (`author_id`),
    INDEX `idx_ann_subject` (`subject_code`)
) ENGINE=InnoDB;

INSERT INTO `announcements` (`id`, `title`, `category`, `content`, `image_url`, `author_name`, `is_pinned`, `status`, `target_audience`) VALUES
(1, 'Official Schedule & Guidelines: 1st Semester Preliminary Examinations', 'ACADEMIC', '<p>Please be guided by the official schedule and room assignments for the upcoming <strong>1st Semester Preliminary Examinations</strong> across all undergraduate degree programs:</p><ul><li><strong>October 15, 2026 (Tuesday):</strong> General Education & Core Applied Sciences</li><li><strong>October 16, 2026 (Wednesday):</strong> Major Professional Courses & Laboratory Practicums</li><li><strong>October 17, 2026 (Thursday):</strong> Capstone Design Reviews & Departmentals</li></ul><blockquote><strong>Examination Protocol Reminder:</strong> Students are required to present their validated Certificate of Registration (COR) and Examination Permit upon entry to testing rooms.</blockquote>', NULL, 'Dr. Eleanor Vance (VP for Academic Affairs)', 1, 'PUBLISHED', 'ALL'),
(2, 'Final Call: Academic Advising & NSTP Section Allocation for A.Y. 2026-2027', 'ENROLLMENT', '<p>The <strong>Office of the University Registrar</strong> announces that the late enrollment, section cohort alignment, and NSTP component locking window will officially conclude on <strong>September 30, 2026</strong>.</p><ul><li><strong>NSTP 1 Components:</strong> CWTS and ROTC enlistments are strictly capped at 45 students per section.</li><li><strong>Course Overload Petitions:</strong> Graduating seniors must submit Dean-approved overload forms before validation week.</li></ul>', NULL, 'Office of the University Registrar', 0, 'PUBLISHED', 'ALL'),
(3, 'Annual College Convocation & Student Leadership Summit 2026', 'EVENT', '<p>All bonafide GNCP students and student leaders are cordially invited to the <strong>2026 Annual College Convocation & Student Leadership Summit</strong> on November 12, 2026 at the GNCP University Gymnasium & Main Auditorium.</p><blockquote>Theme: "Empowering Academic Excellence & Tech-Driven Community Leadership". Free admission and snack kit provision upon presentation of Student Portal ID.</blockquote>', NULL, 'Office of Student Affairs & Services', 0, 'PUBLISHED', 'ALL'),
(4, 'Health Services Advisory: Mandatory Annual Physical & Dental Screening Schedule', 'MEDICAL', '<p>In compliance with institutional health and safety protocols, the <strong>College Health & Medical Clinic</strong> is conducting its free Annual Physical, Visual Acuity, and Dental Screening for all enrolled students.</p><ul><li><strong>BSIT & BSCS:</strong> Mondays & Tuesdays (9:00 AM - 3:00 PM)</li><li><strong>BSCpE & BSN:</strong> Wednesdays & Thursdays (9:00 AM - 3:00 PM)</li><li><strong>BSBA & Transferees:</strong> Fridays (9:00 AM - 12:00 NN)</li></ul>', NULL, 'College Health & Medical Clinic', 0, 'PUBLISHED', 'ALL'),
(5, 'Call for Applications: CHED Tertiary Education Subsidy (TES) & Merit Grants', 'FINANCIAL', '<p>Applications for the <strong>Commission on Higher Education (CHED) Tertiary Education Subsidy (TES)</strong> and <strong>GNCP Institutional Academic Honor Grants</strong> for Academic Year 2026-2027 are now officially open.</p><blockquote>Submit your digitized document portfolio at the Scholarships Desk, 2nd Floor Student Services Building on or before <strong>October 31, 2026</strong>.</blockquote>', NULL, 'Scholarships & Student Assistance Office', 0, 'PUBLISHED', 'ALL')
ON DUPLICATE KEY UPDATE
    `title` = VALUES(`title`),
    `category` = VALUES(`category`),
    `content` = VALUES(`content`),
    `author_name` = VALUES(`author_name`),
    `is_pinned` = VALUES(`is_pinned`),
    `status` = VALUES(`status`);

-- ============================================================
--  TABLE 18: academic_milestones
--  Key academic calendar milestones and deadlines managed by Admin.
-- ============================================================
CREATE TABLE IF NOT EXISTS `academic_milestones` (
    `id`                 INT AUTO_INCREMENT PRIMARY KEY,
    `academic_period_id` INT DEFAULT NULL,
    `title`              VARCHAR(150) NOT NULL,
    `date_start`         DATE DEFAULT NULL,
    `date_end`           DATE DEFAULT NULL,
    `date_display`       VARCHAR(100) DEFAULT NULL,
    `status`             VARCHAR(30) NOT NULL DEFAULT 'SCHEDULED',
    `display_order`      INT NOT NULL DEFAULT 0,
    `created_at`         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at`         TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_milestone_period` (`academic_period_id`),
    INDEX `idx_milestone_status` (`status`),
    INDEX `idx_milestone_order` (`display_order`)
) ENGINE=InnoDB;

INSERT INTO `academic_milestones` (`id`, `academic_period_id`, `title`, `date_start`, `date_end`, `date_display`, `status`, `display_order`) VALUES
(1, 1, 'Enrollment & Advising', '2026-07-01', '2026-09-30', 'Jul 01 - Sep 30, 2026', 'ACTIVE', 1),
(2, 1, 'Preliminary Examinations', '2026-10-15', '2026-10-17', 'October 15 - 17, 2026', 'UPCOMING', 2),
(3, 1, 'Midterm Grade Encoding', '2026-11-05', '2026-11-08', 'November 05 - 08, 2026', 'SCHEDULED', 3),
(4, 1, 'Final Semester Examinations', '2026-12-15', '2026-12-18', 'December 15 - 18, 2026', 'SCHEDULED', 4)
ON DUPLICATE KEY UPDATE
    `title` = VALUES(`title`),
    `date_display` = VALUES(`date_display`),
    `status` = VALUES(`status`),
    `display_order` = VALUES(`display_order`);


-- ============================================================
--  TABLE 19: payments
--  Cashier and financial transactions tracking.
-- ============================================================
CREATE TABLE IF NOT EXISTS `payments` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `student_reference` varchar(50) NOT NULL,
  `student_id` varchar(50) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_method` varchar(50) NOT NULL,
  `payment_type` varchar(50) NOT NULL DEFAULT 'DOWNPAYMENT',
  `channel` varchar(50) NOT NULL DEFAULT 'CASH',
  `transaction_reference` varchar(100) NOT NULL,
  `official_receipt_number` varchar(50) DEFAULT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'COMPLETED',
  `cashier_username` varchar(50) NOT NULL,
  `notes` text DEFAULT NULL,
  `paid_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_student_reference` (`student_reference`),
  KEY `idx_student_id` (`student_id`),
  KEY `idx_transaction_reference` (`transaction_reference`),
  KEY `idx_or_number` (`official_receipt_number`),
  KEY `idx_paid_at` (`paid_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 20: official_receipts
--  Permanent official receipt records issued by Cashier.
-- ============================================================
CREATE TABLE IF NOT EXISTS `official_receipts` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `or_number` varchar(50) NOT NULL,
  `student_reference` varchar(50) NOT NULL,
  `student_name` varchar(150) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_id` bigint(20) DEFAULT NULL,
  `cashier_username` varchar(50) NOT NULL,
  `issued_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `or_number` (`or_number`),
  KEY `idx_or_student_ref` (`student_reference`),
  KEY `idx_issued_at` (`issued_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 21: student_clearances
--  Multi-station digital clearance flags per applicant.
-- ============================================================
CREATE TABLE IF NOT EXISTS `student_clearances` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `student_reference` varchar(50) NOT NULL,
  `station_code` varchar(50) NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'PENDING',
  `verified_by` varchar(50) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `clearance_data` longtext DEFAULT NULL,
  `cleared_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_student_station` (`student_reference`,`station_code`),
  KEY `idx_station_status` (`station_code`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 22: professors
--  Faculty members linked to station_users and departments.
-- ============================================================
CREATE TABLE IF NOT EXISTS `professors` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL COMMENT 'FK to station_users.id',
  `employee_id` varchar(50) NOT NULL COMMENT 'Faculty ID e.g. FAC-2026-001',
  `name` varchar(150) NOT NULL,
  `department_id` int(11) NOT NULL COMMENT 'FK to departments.id',
  `email` varchar(150) DEFAULT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'ACTIVE',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id` (`user_id`),
  UNIQUE KEY `employee_id` (`employee_id`),
  KEY `idx_prof_dept` (`department_id`,`status`),
  KEY `idx_prof_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 23: professor_availability
--  Faculty weekly availability matrix for the scheduler.
-- ============================================================
CREATE TABLE IF NOT EXISTS `professor_availability` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `professor_id` int(11) NOT NULL,
  `day_of_week` varchar(20) NOT NULL COMMENT 'Monday, Tuesday, Wednesday, Thursday, Friday, Saturday',
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `is_available` tinyint(1) NOT NULL DEFAULT 1,
  `notes` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_avail_prof_day` (`professor_id`,`day_of_week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 24: professor_files
--  Professor Personal Drive storage metadata.
-- ============================================================
CREATE TABLE IF NOT EXISTS `professor_files` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `professor_id` int(11) NOT NULL,
  `filename` varchar(255) NOT NULL,
  `stored_filename` varchar(255) NOT NULL,
  `file_type` varchar(20) NOT NULL,
  `mime_type` varchar(100) NOT NULL,
  `file_size` bigint(20) NOT NULL,
  `storage_path` varchar(255) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_files_prof` (`professor_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 25: lms_materials
--  Learning materials published by faculty to classrooms.
-- ============================================================
CREATE TABLE IF NOT EXISTS `lms_materials` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `professor_id` int(11) NOT NULL,
  `file_id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `subject_code` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_mat_prof` (`professor_id`),
  KEY `idx_mat_file` (`file_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 26: lms_material_sections
--  Section targeting for published LMS learning materials.
-- ============================================================
CREATE TABLE IF NOT EXISTS `lms_material_sections` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `material_id` int(11) NOT NULL,
  `section_id` int(11) DEFAULT NULL,
  `section_code` varchar(50) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_lms_sec_mat` (`material_id`),
  KEY `idx_lms_sec_code` (`section_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  TABLE 27: announcement_sections
--  Section targeting for class-specific announcements.
-- ============================================================
CREATE TABLE IF NOT EXISTS `announcement_sections` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `announcement_id` int(11) NOT NULL,
  `section_id` int(11) DEFAULT NULL,
  `section_code` varchar(50) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ann_sec_id` (`announcement_id`),
  KEY `idx_ann_sec_code` (`section_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  BOOTSTRAP SEED: Academic Scheduler Operator Account
--  Password: Gncp#2026!
-- ============================================================
INSERT INTO `station_users` (`username`, `password`, `name`, `email`, `role`, `status`, `must_change_password`)
VALUES ('scheduler', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Academic Scheduler Officer', 'scheduler@gncp.edu.ph', 'SCHEDULER', 'ACTIVE', 0)
ON DUPLICATE KEY UPDATE `role` = 'SCHEDULER', `status` = 'ACTIVE';

-- ============================================================
--  BOOTSTRAP SEED: Faculty Accounts & Department Associations
-- ============================================================
INSERT INTO `station_users` (`id`, `username`, `password`, `name`, `email`, `role`, `status`, `must_change_password`) VALUES
(199, 'steve.jobs', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Prof. Steve Jobs', 'steve.jobs@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(200, 'dennis.ritchie', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Prof. Dennis Ritchie', 'dennis.ritchie@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(201, 'pythagoras', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Dr. Pythagoras', 'pythagoras@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(202, 'shakespeare', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Dr. Shakespeare', 'shakespeare@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(203, 'freud', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Dr. Freud', 'freud@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(204, 'carter', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Coach Carter', 'carter@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(205, 'payne', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Major Payne', 'payne@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(206, 'alan.turing', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Prof. Alan Turing', 'alan.turing@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(207, 'grace.hopper', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Prof. Grace Hopper', 'grace.hopper@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(208, 'steve.wozniak', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Prof. Steve Wozniak', 'steve.wozniak@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(209, 'euler', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Dr. Euler', 'euler@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0),
(210, 'nobel', '$2y$10$wN9v2rVvVwK4U7F4Xv3GKe2Z8Wf9Yt4O0Qp6L5M1N8P3R7S9T0V1W', 'Dr. Nobel', 'nobel@gncp.edu.ph', 'PROFESSOR', 'ACTIVE', 0)
ON DUPLICATE KEY UPDATE `status` = 'ACTIVE';

INSERT INTO `professors` (`id`, `user_id`, `employee_id`, `name`, `department_id`, `email`, `status`) VALUES
(1, 199, 'FAC-CCS-001', 'Prof. Steve Jobs', 1, 'steve.jobs@gncp.edu.ph', 'ACTIVE'),
(2, 200, 'FAC-CCS-002', 'Prof. Dennis Ritchie', 1, 'dennis.ritchie@gncp.edu.ph', 'ACTIVE'),
(3, 201, 'FAC-GED-001', 'Dr. Pythagoras', 4, 'pythagoras@gncp.edu.ph', 'ACTIVE'),
(4, 202, 'FAC-GED-002', 'Dr. Shakespeare', 4, 'shakespeare@gncp.edu.ph', 'ACTIVE'),
(5, 203, 'FAC-GED-003', 'Dr. Freud', 4, 'freud@gncp.edu.ph', 'ACTIVE'),
(6, 204, 'FAC-PE-001', 'Coach Carter', 6, 'carter@gncp.edu.ph', 'ACTIVE'),
(7, 205, 'FAC-NSTP-001', 'Major Payne', 5, 'payne@gncp.edu.ph', 'ACTIVE'),
(8, 206, 'FAC-CCS-003', 'Prof. Alan Turing', 1, 'alan.turing@gncp.edu.ph', 'ACTIVE'),
(9, 207, 'FAC-CCS-004', 'Prof. Grace Hopper', 1, 'grace.hopper@gncp.edu.ph', 'ACTIVE'),
(10, 208, 'FAC-CCS-005', 'Prof. Steve Wozniak', 1, 'steve.wozniak@gncp.edu.ph', 'ACTIVE'),
(11, 209, 'FAC-CCS-006', 'Dr. Euler', 1, 'euler@gncp.edu.ph', 'ACTIVE'),
(12, 210, 'FAC-GED-004', 'Dr. Nobel', 4, 'nobel@gncp.edu.ph', 'ACTIVE')
ON DUPLICATE KEY UPDATE `status` = 'ACTIVE';

-- Link existing subject sections to their professor IDs
UPDATE `subject_sections` SET `professor_id` = 1 WHERE `instructor` LIKE '%Steve Jobs%';
UPDATE `subject_sections` SET `professor_id` = 2 WHERE `instructor` LIKE '%Dennis Ritchie%';
UPDATE `subject_sections` SET `professor_id` = 3 WHERE `instructor` LIKE '%Pythagoras%';
UPDATE `subject_sections` SET `professor_id` = 4 WHERE `instructor` LIKE '%Shakespeare%';
UPDATE `subject_sections` SET `professor_id` = 5 WHERE `instructor` LIKE '%Freud%';
UPDATE `subject_sections` SET `professor_id` = 6 WHERE `instructor` LIKE '%Carter%';
UPDATE `subject_sections` SET `professor_id` = 7 WHERE `instructor` LIKE '%Payne%';
UPDATE `subject_sections` SET `professor_id` = 8 WHERE `instructor` LIKE '%Alan Turing%';
UPDATE `subject_sections` SET `professor_id` = 9 WHERE `instructor` LIKE '%Grace Hopper%';
UPDATE `subject_sections` SET `professor_id` = 10 WHERE `instructor` LIKE '%Steve Wozniak%';
UPDATE `subject_sections` SET `professor_id` = 11 WHERE `instructor` LIKE '%Euler%';
UPDATE `subject_sections` SET `professor_id` = 12 WHERE `instructor` LIKE '%Nobel%';
