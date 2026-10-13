<?php
/**
 * SecurePark API - Student / Vehicle-Owner Portal
 *
 * All data is scoped to the signed-in student's owner ID taken from the session
 * token. No endpoint accepts an owner ID, vehicle ID or plate from the client.
 *
 * GET /api/student.php?action=me           Profile + standing summary
 * GET /api/student.php?action=vehicles     Own vehicles with drivers, status, violation hold and signed QR pass
 * GET /api/student.php?action=notices     Notices sent to the owner (violations, vehicle blocked at the gate) and whether they were e-mailed
 * GET /api/student.php?action=payments    Own registration-fee payments / receipts (pay online with student_pay.php)
 * GET /api/student.php?action=violations   Violations on own vehicles (a pending one blocks entry and exit)
 * GET /api/student.php?action=activity     Gate audit log (entries, exits, denied attempts) of own vehicles
 *                                          optional: &plate=<own plate>  &limit=<1-200, default 50>
 * GET /api/student.php?action=alerts       Own vehicles flagged at the gate: active (Held) cases and recent closed ones
 *                                          (each carries logId = the refused passage, for its gate clip)
 * GET /api/student.php?action=evidence&id=N  One evidence photo the guard took on the owner's own vehicle, as a data URL.
 *                                          Cases, activity rows and flags list the photos (no pictures) in their `evidence` field.
 *
 * Sign in:          POST /api/auth.php?action=login&realm=student  { username: <student ID>, password }
 * Change password:  POST /api/auth.php?action=change_password
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/records.php';
require_once __DIR__ . '/../lib/payments.php';
require_once __DIR__ . '/../lib/notices.php';
require_once __DIR__ . '/../lib/cases.php';
require_once __DIR__ . '/../lib/renewals.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, 'Method not allowed');
}

$student = requireStudent($pdo);
$ownerId = $student['owner_id_number'];
$action = $_GET['action'] ?? 'me';

function ownVehicles($pdo, $ownerId, $includeRetired = true) {
    $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `owner_id_number` = ?" . ($includeRetired ? '' : ' AND `is_retired` = 0') . " ORDER BY `id` ASC");
    $stmt->execute([$ownerId]);
    return $stmt->fetchAll();
}

function ownPlates($pdo, $ownerId) {
    return array_map(fn($v) => normalizePlate($v['plate_number']), ownVehicles($pdo, $ownerId));
}

function plateInClause($plates) {
    return "REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') IN (" . implode(',', array_fill(0, count($plates), '?')) . ')';
}

/**
 * Free-text gate notes can carry guard names or device tags; the owner only sees the reason.
 */
function ownerSafeNote($notes) {
    $n = preg_replace('/\s*\[Mobile operator:[^\]]*\]/i', '', (string)$notes);
    $n = trim($n, " |");
    return $n === '' ? null : $n;
}

/**
 * The evidence photos taken on the owner's vehicles (details only, never the pictures), indexed by what they belong to.
 * The pictures are fetched one at a time with action=evidence.
 */
function ownerEvidenceIndex($pdo, array $plates) {
    $idx = ['violation' => [], 'incident' => [], 'log' => []];
    if (!$plates) return $idx;
    $stmt = $pdo->prepare("SELECT `id`, `kind`, `gate_log_id`, `violation_id`, `incident_id`, `created_at`, `purged_at` FROM `evidence_photos`
        WHERE " . plateInClause($plates) . " ORDER BY `id` ASC LIMIT 1000");
    $stmt->execute($plates);
    foreach ($stmt->fetchAll() as $r) {
        $p = ['id' => (int)$r['id'], 'kind' => $r['kind'], 'takenAt' => $r['created_at'], 'purged' => $r['purged_at'] !== null];
        if ($r['violation_id'] !== null) $idx['violation'][(int)$r['violation_id']][$p['id']] = $p;
        if ($r['incident_id'] !== null) $idx['incident'][(int)$r['incident_id']][$p['id']] = $p;
        if ($r['gate_log_id'] !== null) $idx['log'][(int)$r['gate_log_id']][$p['id']] = $p;
    }
    return $idx;
}

/** The photos of one case / flag / gate passage: any of the records it is tied to, each photo once, oldest first. */
function evidenceFor(array $idx, $violationId = null, $incidentId = null, $logId = null) {
    $out = [];
    foreach ([['violation', $violationId], ['incident', $incidentId], ['log', $logId]] as [$kind, $id]) {
        if ($id !== null && isset($idx[$kind][(int)$id])) $out += $idx[$kind][(int)$id];
    }
    ksort($out);
    return array_values($out);
}

function incidentView($pdo, $r, array $evidenceIdx = ['violation' => [], 'incident' => [], 'log' => []]) {
    $logId = incidentLogId($pdo, $r);
    return [
        'id' => (int)$r['id'],
        'logId' => $logId,
        'caseNumber' => $r['case_number'],
        'plateNumber' => $r['plate_number'],
        'reason' => $r['reason'],
        'status' => $r['status'],
        'gatePoint' => $r['gate_point'],
        // For a stop at the gate this is the person who was driving; a ban notice has no stranger at the wheel
        'driverName' => $r['driver_name'],
        'driverRelationship' => $r['driver_relationship'],
        'reportedAt' => $r['reported_at'],
        'resolvedAt' => $r['resolved_at'],
        'evidence' => evidenceFor($evidenceIdx, null, (int)$r['id'], $logId),
    ];
}

function openViolationCount($pdo, $ownerId) {
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM `vehicle_violations` vv
        JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
        WHERE v.`owner_id_number` = ? AND vv.`severity` = 'Violation' AND vv.`status` = 'Pending'");
    $stmt->execute([$ownerId]);
    return (int)$stmt->fetchColumn();
}

function heldIncidentCount($pdo, array $plates) {
    if (!$plates) return 0;
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM `security_incidents` WHERE `status` = 'Held' AND " . plateInClause($plates));
    $stmt->execute($plates);
    return (int)$stmt->fetchColumn();
}

function studentVehicleView($pdo, $row) {
    $v = vehicleForOutput($pdo, $row, true);
    $renewal = renewalInfo($pdo, $row);
    // Only what the owner needs; internal / duplicate snake_case keys are dropped
    return [
        'id' => $v['id'],
        'plateNumber' => $v['plateNumber'],
        'vehicleType' => $v['vehicleType'],
        'makeModelColor' => $v['makeModelColor'],
        'ownerName' => $v['ownerName'],
        'ownerRole' => $v['ownerRole'],
        'ownerIdNumber' => $v['ownerIdNumber'],
        'ownerPhone' => $v['ownerPhone'],
        'ownerEmail' => $v['ownerEmail'],
        'ownerPhoto' => $v['ownerPhoto'],
        'department' => $v['department'],
        'isVip' => $v['isVip'],
        'passClass' => $v['passClass'],
        'registeredAt' => $row['created_at'] ?? null,
        'lastEntryTime' => $v['lastEntryTime'],
        'lastGatePoint' => $v['lastGatePoint'],
        'stickerYear' => $v['stickerYear'],
        'status' => $v['status'],
        'registrationStatus' => $v['registrationStatus'],
        'vehiclePhoto' => $v['vehiclePhoto'],
        'renewal' => [
            'due' => $renewal['due'], 'eligible' => $renewal['eligible'], 'expired' => $renewal['expired'], 'daysLeft' => $renewal['daysLeft'],
            'fee' => $renewal['fee'], 'targetYear' => $renewal['targetYear'], 'newValidUntil' => $renewal['newValidUntil'], 'blocker' => $renewal['blocker'],
        ],
        'paymentStatus' => $v['paymentStatus'],
        'feeAmount' => $v['feeAmount'],
        'paidAt' => $v['paidAt'],
        'passId' => $v['passId'],
        'passValidUntil' => $v['passValidUntil'],
        'passExpired' => $v['passValidUntil'] !== null && $v['passValidUntil'] < date('Y-m-d'),
        'isBanned' => $v['isBanned'],
        'qrPayload' => $v['qrPayload'],
        'authorizedDrivers' => array_map(function ($d) {
            return [
                'fullName' => $d['fullName'],
                'relationship' => $d['relationship'],
                'licenseNo' => $d['licenseNo'],
            ];
        }, $v['authorizedDrivers']),
    ];
}

switch ($action) {
    case 'me':
        $vehicles = ownVehicles($pdo, $ownerId, false);
        sendResponse(200, [
            'student' => publicStudent($student),
            'summary' => [
                'vehicles' => count($vehicles),
                'banned' => count(array_filter($vehicles, fn($v) => (int)$v['is_banned'] === 1)),
                'openViolations' => openViolationCount($pdo, $ownerId),
                'unpaidVehicles' => count(array_filter($vehicles, fn($v) => ($v['payment_status'] ?? 'Paid') === 'Unpaid')),
                'activeAlerts' => heldIncidentCount($pdo, array_map(fn($v) => normalizePlate($v['plate_number']), $vehicles)),
            ],
        ]);

    case 'vehicles':
        sendResponse(200, array_map(fn($row) => studentVehicleView($pdo, $row), ownVehicles($pdo, $ownerId, false)));

    case 'notices':
        $stmt = $pdo->prepare("SELECT * FROM `owner_notices` WHERE `owner_id_number` = ? AND `kind` NOT IN ('Entry', 'Exit') ORDER BY `id` DESC LIMIT 30");
        $stmt->execute([$ownerId]);
        sendResponse(200, array_map('noticeView', $stmt->fetchAll()));

    case 'payments':
        $stmt = $pdo->prepare("SELECT * FROM `payments` WHERE `owner_id_number` = ? AND `status` <> 'Cancelled' ORDER BY `id` DESC LIMIT 100");
        $stmt->execute([$ownerId]);
        sendResponse(200, array_map('paymentView', $stmt->fetchAll()));

    case 'violations':
        $stmt = $pdo->prepare("SELECT vv.* FROM `vehicle_violations` vv
            JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
            WHERE v.`owner_id_number` = ? AND vv.`severity` = 'Violation'
            ORDER BY vv.`id` DESC LIMIT 200");
        $stmt->execute([$ownerId]);
        $rows = array_map(function ($r) {
            return [
                'id' => (int)$r['id'],
                'plateNumber' => $r['plate_number'],
                'violationType' => $r['violation_type'],
                'description' => $r['description'],
                'status' => $r['status'],
                'createdAt' => $r['created_at'],
                'resolvedAt' => $r['resolved_at'],
                'resolutionNotes' => $r['status'] === 'Pending' ? null : $r['resolution_notes'],
            ];
        }, $stmt->fetchAll());
        sendResponse(200, $rows);

    case 'cases':
        // Violations and security cases on the owner's vehicles, with a timeline that has no staff names or internal notes
        $plates = ownPlates($pdo, $ownerId);
        $stmt = $pdo->prepare("SELECT vv.*, v.`owner_name`, v.`owner_phone`, v.`owner_id_number`, v.`owner_role`
            FROM `vehicle_violations` vv JOIN `vehicles` v ON v.`id` = vv.`vehicle_id`
            WHERE v.`owner_id_number` = ? AND vv.`severity` = 'Violation' ORDER BY vv.`id` DESC LIMIT 50");
        $stmt->execute([$ownerId]);
        $vRows = $stmt->fetchAll();
        $iRows = [];
        if ($plates) {
            $stmt = $pdo->prepare("SELECT * FROM `security_incidents`
                WHERE `id` NOT IN (SELECT `incident_id` FROM `vehicle_violations` WHERE `incident_id` IS NOT NULL) AND " . plateInClause($plates) . "
                ORDER BY `id` DESC LIMIT 50");
            $stmt->execute($plates);
            $iRows = $stmt->fetchAll();
        }
        $keys = array_merge(array_map(fn($r) => 'V' . $r['id'], $vRows), array_map(fn($r) => 'I' . $r['id'], $iRows));
        $events = caseEventsFor($pdo, $keys);
        $evidenceIdx = ownerEvidenceIndex($pdo, $plates);
        $out = [];
        foreach ($vRows as $r) {
            $k = 'V' . $r['id']; $ev = $events[$k] ?? [];
            $s = caseSummary('violation', $r, $ev);
            $view = casePublicView($s, $ev, $pdo);
            $view['reference'] = $s['reference'];
            $view['evidence'] = evidenceFor($evidenceIdx, (int)$r['id'], $s['incidentId']);
            $out[] = $view;
        }
        foreach ($iRows as $r) {
            $k = 'I' . $r['id']; $ev = $events[$k] ?? [];
            $s = caseSummary('incident', $r, $ev);
            $view = casePublicView($s, $ev, $pdo);
            $view['reference'] = $s['reference'];
            $view['evidence'] = evidenceFor($evidenceIdx, null, (int)$r['id'], incidentLogId($pdo, $r));
            $out[] = $view;
        }
        usort($out, fn($a, $b) => strcmp((string)$b['openedAt'], (string)$a['openedAt']));
        sendResponse(200, $out);

    case 'activity':
        $plates = ownPlates($pdo, $ownerId);
        if (!$plates) sendResponse(200, []);
        $limit = max(1, min(200, (int)($_GET['limit'] ?? 50)));
        if (!empty($_GET['plate'])) {
            // Only one of the owner's own plates may be named; anything else is not found
            $wanted = normalizePlate($_GET['plate']);
            if (!in_array($wanted, $plates, true)) sendResponse(404, null, 'Vehicle not found.');
            $plates = [$wanted];
        }
        $stmt = $pdo->prepare("SELECT `id`, `plate_number`, `action`, `gate_type`, `gate_point`, `driver_name`, `driver_relationship`,
                `verified_driver_name`, `notes`, `logged_at`
            FROM `gate_logs`
            WHERE " . plateInClause($plates) . "
            ORDER BY `logged_at` DESC, `id` DESC LIMIT {$limit}");
        $stmt->execute($plates);
        $evidenceIdx = ownerEvidenceIndex($pdo, $plates);
        sendResponse(200, array_map(function ($r) use ($evidenceIdx) {
            $denied = strpos($r['action'], 'Denied') !== false;
            return [
                'id' => (int)$r['id'],
                'plateNumber' => $r['plate_number'],
                'action' => $r['action'],
                'gateType' => $r['gate_type'],
                'gatePoint' => $r['gate_point'],
                'driverName' => $r['driver_name'],
                'driverRelationship' => $r['driver_relationship'],
                'driverVerified' => !empty($r['verified_driver_name']),
                // The reason is shown for refused passages; routine approvals carry no owner-facing note
                'note' => $denied ? ownerSafeNote($r['notes']) : null,
                'loggedAt' => $r['logged_at'],
                'evidence' => evidenceFor($evidenceIdx, null, null, (int)$r['id']),
            ];
        }, $stmt->fetchAll()));

    case 'alerts':
        $plates = ownPlates($pdo, $ownerId);
        if (!$plates) sendResponse(200, ['active' => [], 'recent' => []]);
        $evidenceIdx = ownerEvidenceIndex($pdo, $plates);
        $stmt = $pdo->prepare("SELECT * FROM `security_incidents` WHERE `status` = 'Held' AND " . plateInClause($plates) . "
            ORDER BY `reported_at` DESC, `id` DESC LIMIT 20");
        $stmt->execute($plates);
        $active = array_map(fn($r) => incidentView($pdo, $r, $evidenceIdx), $stmt->fetchAll());

        $since = date('Y-m-d H:i:s', strtotime('-30 days'));
        $stmt = $pdo->prepare("SELECT * FROM `security_incidents` WHERE `status` <> 'Held' AND `reported_at` >= ? AND " . plateInClause($plates) . "
            ORDER BY `reported_at` DESC, `id` DESC LIMIT 10");
        $stmt->execute(array_merge([$since], $plates));
        sendResponse(200, ['active' => $active, 'recent' => array_map(fn($r) => incidentView($pdo, $r, $evidenceIdx), $stmt->fetchAll())]);

    case 'evidence':
        // One picture, and only when it was taken on one of this owner's own vehicles
        $stmt = $pdo->prepare("SELECT `id`, `kind`, `plate_number`, `data`, `created_at`, `purged_at` FROM `evidence_photos` WHERE `id` = ?");
        $stmt->execute([(int)($_GET['id'] ?? 0)]);
        $photo = $stmt->fetch();
        if (!$photo || !in_array(normalizePlate($photo['plate_number']), ownPlates($pdo, $ownerId), true)) sendResponse(404, null, 'Photo not found.');
        sendResponse(200, ['id' => (int)$photo['id'], 'kind' => $photo['kind'], 'takenAt' => $photo['created_at'],
            'purged' => $photo['purged_at'] !== null, 'image' => $photo['purged_at'] === null ? $photo['data'] : null]);

    default:
        sendResponse(400, null, 'Unknown action. Use me, vehicles, payments, notices, violations, cases, activity, alerts or evidence.');
}
