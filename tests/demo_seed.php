<?php
/**
 * SecurePark - LOCAL demo data (never run against production)
 *
 *   php tests/demo_seed.php
 *
 * Deletes the local SQLite database (web-app-admin/data/securepark.sqlite) and fills it with
 * demo vehicles, strikes, a banned vehicle, vehicles inside campus, visitor passes and logins.
 * Generated demo passwords are written to web-app-admin/data/DEMO_CREDENTIALS.txt
 * (data/ is git-ignored and never deployed). The admin keeps the default first-login password.
 */

if (PHP_SAPI !== 'cli') {
    exit("CLI only.\n");
}

$root = dirname(__DIR__);
$dataDir = $root . '/web-app-admin/data';
$dbFile = $dataDir . '/securepark.sqlite';
if (file_exists($dbFile)) unlink($dbFile);

// Load the app exactly as the API does, forced onto the local SQLite database
$_SERVER['REQUEST_METHOD'] = 'GET';
putenv('DB_DRIVER=sqlite');
ob_start();
require $root . '/web-app-admin/config/db.php';
require_once $root . '/web-app-admin/lib/vehicles.php';
require_once $root . '/web-app-admin/lib/strikes.php';
require_once $root . '/web-app-admin/lib/students.php';
ob_end_clean();

if ($db_driver !== 'sqlite') exit("Refusing to seed: not using the local SQLite database.\n");

$credentials = [];
$now = time();
$system = ['id' => null, 'full_name' => 'Demo Seed', 'badge_number' => null];

/* ---------- Staff ---------- */
$guardPass = generateTempPassword();
$pdo->prepare("INSERT INTO system_users (username, password_hash, full_name, role, badge_number, gate_assigned, status, must_change_password)
               VALUES ('guard.demo', ?, 'Jose Rizal Bautista', 'guard', 'NCST-SEC-07', 'Gate 1 (Main Ingress)', 'Active', 1)")
    ->execute([password_hash($guardPass, PASSWORD_BCRYPT)]);
$credentials[] = "Guard (staff portal)    username: guard.demo            temporary password: {$guardPass}";
$guardActor = ['id' => (int)$pdo->lastInsertId(), 'full_name' => 'Jose Rizal Bautista', 'badge_number' => 'NCST-SEC-07'];

/* ---------- Vehicles ---------- */
function addVehicle($pdo, $v, $drivers) {
    $pdo->prepare("INSERT INTO vehicles (plate_number, vehicle_type, category, make_model_color, owner_name, owner_role, department,
                   owner_id_number, owner_phone, owner_email, status, registration_status, sticker_year)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Active', '2026')")
        ->execute([$v['plate'], $v['type'], $v['category'], $v['model'], $v['owner'], $v['role'], $v['dept'],
                   $v['id'], $v['phone'], $v['email'], $v['status'] ?? 'Outside']);
    $id = (int)$pdo->lastInsertId();
    foreach ($drivers as $d) {
        $pdo->prepare("INSERT INTO authorized_drivers (vehicle_id, full_name, relationship, license_no, phone) VALUES (?, ?, ?, ?, ?)")
            ->execute([$id, $d[0], $d[1], $d[2], $d[3] ?? null]);
    }
    return ensurePassIdentity($pdo, findVehicleById($pdo, $id));
}

function logGate($pdo, $plate, $owner, $driver, $rel, $action, $when, $guard = 'Jose Rizal Bautista (NCST-SEC-07)') {
    $exit = strpos($action, 'Exit') === 0;
    $pdo->prepare("INSERT INTO gate_logs (plate_number, vehicle_type, owner_name, driver_name, driver_relationship, verified_driver_name,
                   gate_point, action, gate_type, status, guard_name, notes, logged_at)
                   VALUES (?, '4-Wheel (Sedan)', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Verified (VALID)', ?)")
        ->execute([$plate, $owner, $driver, $rel, $driver, $exit ? 'Gate 2 (Main Egress)' : 'Gate 1 (Main Ingress)',
                   $action, $exit ? 'Egress' : 'Ingress', $exit ? 'Exited' : 'Inside Campus', $guard, date('Y-m-d H:i:s', $when)]);
}

$juan = addVehicle($pdo, ['plate' => 'NDK 4821', 'type' => '4-Wheel (Sedan)', 'category' => 'plated', 'model' => 'White Toyota Vios',
    'owner' => 'Juan Dela Cruz', 'role' => 'Student', 'dept' => 'BS Information Technology', 'id' => 'NCST-2024-05182',
    'phone' => '0917 123 4567', 'email' => 'juan.delacruz@ncst.edu.ph'],
    [['Juan Dela Cruz', 'Self (Owner)', 'N01-22-123456', '0917 123 4567'], ['Pedro Dela Cruz', 'Brother', 'N02-19-654321', '0918 222 3344']]);

$maria = addVehicle($pdo, ['plate' => 'ABC 1234', 'type' => '4-Wheel (SUV)', 'category' => 'plated', 'model' => 'Gray Mitsubishi Xpander',
    'owner' => 'Maria Santos', 'role' => 'Faculty', 'dept' => 'College of Computer Studies', 'id' => 'NCST-EMP-0311',
    'phone' => '0922 555 0101', 'email' => 'maria.santos@ncst.edu.ph'],
    [['Maria Santos', 'Self (Owner)', 'N03-15-777888']]);

$carlo = addVehicle($pdo, ['plate' => 'XYZ 7788', 'type' => '4-Wheel (Sedan)', 'category' => 'plated', 'model' => 'Red Honda City',
    'owner' => 'Carlo Reyes', 'role' => 'Student', 'dept' => 'BS Criminology', 'id' => 'NCST-2023-01447',
    'phone' => '0935 777 1212', 'email' => null],
    [['Carlo Reyes', 'Self (Owner)', 'N04-21-111222']]);

$ana = addVehicle($pdo, ['plate' => 'LTO 5566', 'type' => '4-Wheel (Hatchback)', 'category' => 'plated', 'model' => 'Blue Toyota Wigo',
    'owner' => 'Ana Lim', 'role' => 'Student', 'dept' => 'BS Accountancy', 'id' => 'NCST-2025-00872',
    'phone' => '0917 888 9090', 'email' => null, 'status' => 'Inside Campus'],
    [['Ana Lim', 'Self (Owner)', 'N05-23-333444']]);

$kevin = addVehicle($pdo, ['plate' => 'MC 9012', 'type' => 'Motorcycle', 'category' => 'motorcycle', 'model' => 'Black Honda Click 125',
    'owner' => 'Kevin Tan', 'role' => 'Staff', 'dept' => 'Maintenance Office', 'id' => 'NCST-EMP-0977',
    'phone' => '0999 444 5566', 'email' => null, 'status' => 'Inside Campus'],
    [['Kevin Tan', 'Self (Owner)', 'N06-18-555666']]);

/* ---------- Gate history ---------- */
$today8 = strtotime(date('Y-m-d 08:00:00', $now));
logGate($pdo, 'NDK 4821', 'Juan Dela Cruz', 'Juan Dela Cruz', 'Self (Owner)', 'Entry Recorded', min($now - 5400, $today8));
logGate($pdo, 'NDK 4821', 'Juan Dela Cruz', 'Pedro Dela Cruz', 'Brother', 'Exit Approved', $now - 1800);
logGate($pdo, 'ABC 1234', 'Maria Santos', 'Maria Santos', 'Self (Owner)', 'Entry Recorded', $now - 20000);
logGate($pdo, 'ABC 1234', 'Maria Santos', 'Maria Santos', 'Self (Owner)', 'Exit Approved', $now - 9000);

// Ana entered yesterday morning and never left -> OVERNIGHT (the dashboard flags it on sign-in)
logGate($pdo, 'LTO 5566', 'Ana Lim', 'Ana Lim', 'Self (Owner)', 'Entry Recorded', strtotime('-1 day', $today8));

// Kevin has been inside ~13 hours (after last night's curfew) -> OVERTIME (manual flag button)
$curfewToday = strtotime(date('Y-m-d', $now) . ' ' . SP_CURFEW_TIME . ':00');
$nightStart = $now >= $curfewToday ? $curfewToday : strtotime('-1 day', $curfewToday);
logGate($pdo, 'MC 9012', 'Kevin Tan', 'Kevin Tan', 'Self (Owner)', 'Entry Recorded', max($now - 13 * 3600, $nightStart + 600));

/* ---------- Strikes ---------- */
addWarning($pdo, $guardActor, $maria, 'Parking in Fire Lane / Restricted Zone', 'Parked beside the gym fire exit.');
addWarning($pdo, $guardActor, $maria, 'Unauthorized Driver at Helm', 'Driven by an unlisted relative; turned back at Gate 1.');
foreach (['Parking in Fire Lane / Restricted Zone', 'Reckless / Prohibited Driving on Campus', 'Refusal of Inspection / Gate Bypass'] as $t) {
    addWarning($pdo, $guardActor, findVehicleById($pdo, $carlo['id']), $t, 'Recorded by patrol.');
}

/* ---------- Visitor passes (today) ---------- */
$today = date('Y-m-d', $now);
function addVisitor($pdo, $code, $name, $contact, $plate, $model, $purpose, $host, $today, $entryTs, $items, $now) {
    $pdo->prepare("INSERT INTO visitor_passes (pass_code, visitor_name, contact_number, plate_number, vehicle_model, purpose_of_visit,
                   person_to_visit, valid_date, entry_time, status, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'Active', ?, ?)")
        ->execute([$code, $name, $contact, $plate, $model, $purpose, $host, $today,
                   $entryTs ? date('Y-m-d H:i:s', $entryTs) : null, 'Jose Rizal Bautista (NCST-SEC-07)', date('Y-m-d H:i:s', $now - 7200)]);
    $id = (int)$pdo->lastInsertId();
    foreach ($items as $it) {
        $pdo->prepare("INSERT INTO visitor_pass_items (visitor_pass_id, item_name, quantity, description) VALUES (?, ?, ?, ?)")
            ->execute([$id, $it[0], $it[1], $it[2] ?? null]);
    }
    if ($entryTs) {
        $pdo->prepare("INSERT INTO gate_logs (plate_number, vehicle_type, owner_name, driver_name, driver_relationship, verified_driver_name,
                       gate_point, action, gate_type, status, guard_name, notes, logged_at)
                       VALUES (?, 'Visitor Vehicle', ?, ?, 'Visitor (Day Pass)', ?, 'Gate 1 (Main Ingress)', 'Entry Recorded', 'Ingress',
                       'Inside Campus', 'Jose Rizal Bautista (NCST-SEC-07)', ?, ?)")
            ->execute([$plate, $name, $name, $name, 'Verified (VALID) | Items checked in: ' . visitorItemsSummary(array_map(fn($i) => ['name' => $i[0], 'quantity' => $i[1], 'description' => $i[2] ?? null], $items)),
                       date('Y-m-d H:i:s', $entryTs)]);
    }
}
$day = str_replace('-', '', $today);
// Inside campus right now, with event equipment
addVisitor($pdo, "VP-{$day}-EVT1", 'Eventos Catering Services', '0917 321 0000', 'EVT4040', 'White Isuzu Elf truck',
    'Foundation Day setup', 'Student Affairs Office', $today, $now - 2 * 3600,
    [['Monobloc chairs', 40], ['Folding tables', 8], ['Sound system', 1, 'speakers + mixer']], $now);
// Issued, not yet arrived
addVisitor($pdo, "VP-{$day}-DEMO", 'Liza Soberano', '0917 000 1111', 'VIS2026', 'White Nissan Almera',
    'Enrollment inquiry', "Registrar's Office", $today, null, [['Document box', 1, 'transcripts']], $now);

/* ---------- VIP vehicle, scheduled pass, and an offline-issued pass ---------- */
// The school president's car: inside since this morning. A normal vehicle in that state would be flagged
// overnight / overtime; a VIP is exempt (and needs no driver check at the gate).
$pres = addVehicle($pdo, ['plate' => 'PRES 001', 'type' => '4-Wheel (Sedan)', 'category' => 'plated', 'model' => 'Black Toyota Camry',
    'owner' => 'Dr. Rosa Villanueva', 'role' => 'Faculty', 'dept' => 'Office of the President', 'id' => 'NCST-PRES-001',
    'phone' => '0917 000 0001', 'email' => null, 'status' => 'Inside Campus'],
    [['Dr. Rosa Villanueva', 'Self (Owner)', 'N07-10-000001']]);
$pdo->prepare("UPDATE vehicles SET pass_class = 'VIP', pass_class_by = 'Demo Seed', pass_class_at = ? WHERE id = ?")
    ->execute([date('Y-m-d H:i:s', $now), $pres['id']]);
logGate($pdo, 'PRES 001', 'Dr. Rosa Villanueva', 'VIP (driver not checked)', 'VIP (driver not checked)', 'Entry Recorded', max($now - 14 * 3600, $nightStart - 3600));
$pdo->prepare("UPDATE gate_logs SET notes = 'VIP pass | Verified (VALID)' WHERE plate_number = 'PRES 001'")->execute();

// A pass an administrator scheduled for a later day: shown under "Upcoming", refused as "not yet valid" until then
$later = date('Y-m-d', strtotime('+2 days', $now));
addVisitor($pdo, 'VP-' . str_replace('-', '', $later) . '-SCH1', 'Accreditation Team (PAASCU)', '0917 555 0303', 'ACC2030', 'Silver Toyota Innova',
    'Accreditation visit', 'Office of the President', $later, null, [['Laptop bags', 4]], $now);

// A visitor pass a guard issued on a phone with no connection: the pass and its entry keep the real time,
// and reached the server later (the list marks it "ISSUED OFFLINE")
addVisitor($pdo, "VP-{$day}-OFFL", 'Olga Offline', '0917 000 4444', 'OFF5005', 'Red Toyota Vios',
    'Enrollment', "Registrar's Office", $today, $now - 3 * 3600, [['Boxes', 3]], $now);
$pdo->prepare("UPDATE visitor_passes SET created_at = ?, synced_at = ?, created_by = 'Mobile Scanner / Jose Rizal Bautista' WHERE pass_code = ?")
    ->execute([date('Y-m-d H:i:s', $now - 3 * 3600 - 60), date('Y-m-d H:i:s', $now - 45 * 60), "VP-{$day}-OFFL"]);
$pdo->prepare("UPDATE gate_logs SET synced_at = ?, guard_name = 'Mobile Scanner', notes = notes || ' | Recorded offline: event ' || logged_at WHERE plate_number = 'OFF5005'")
    ->execute([date('Y-m-d H:i:s', $now - 45 * 60)]);

/* ---------- Student portal logins ---------- */
foreach ([[$juan, 'Juan Dela Cruz'], [$carlo, 'Carlo Reyes']] as [$veh, $name]) {
    $acct = ensureStudentAccount($pdo, $veh['owner_id_number'], $name, $veh['owner_email']);
    $credentials[] = sprintf("Student (student portal) ID: %-22s temporary password: %s   (%s)", $veh['owner_id_number'], $acct['tempPassword'], $name);
}

$lines = array_merge([
    'SecurePark LOCAL DEMO credentials - generated ' . date('Y-m-d H:i'),
    'Staff portal:   http://localhost:8000/web-app-admin/',
    'Student portal: http://localhost:8000/web-app-student/',
    '',
    'Admin (staff portal)    username: admin                 password: the default first-login password in README.md',
], $credentials, ['', 'Every account asks for a new password at first sign-in.']);
file_put_contents($dataDir . '/DEMO_CREDENTIALS.txt', implode(PHP_EOL, $lines) . PHP_EOL);

echo "Demo data seeded into web-app-admin/data/securepark.sqlite\n";
echo "Logins written to web-app-admin/data/DEMO_CREDENTIALS.txt\n";
