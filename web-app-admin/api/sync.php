<?php
/**
 * SecurePark API - Offline sync (batch)
 *
 * POST /api/sync.php  { events: [ { client_ref, type, occurred_at, payload }, ... ] }   (at most 50 per request)
 *   type: gate_log | visitor_exit | incident | visitor_pass
 *   client_ref:  the device's unique reference for the event (8-64 chars: letters, digits . _ : -)
 *   occurred_at: when it HAPPENED at the gate (ISO 8601; with a "Z" / offset it is unambiguous)
 *   payload:     the same fields the live endpoint takes (logs.php / incidents.php / visitors.php?action=exit)
 *
 * Response: { results: [ { client_ref, status: accepted | duplicate | rejected | retry, code?, message?, id?, flags? } ] }
 *   rejected = the server will never take this event (keep it for review); retry = a temporary problem, send it again
 *   The HTTP status is 200 whenever the batch was processed: a refused event never blocks the ones after it.
 *   A non-200 reply means "not processed, send it again" (offline, migration missing, server error).
 *
 * Rules for events that already happened at the gate:
 *   - They are ALWAYS recorded, never refused for standing: the vehicle is physically on campus. If the vehicle
 *     turned out to be banned / suspended / unregistered / on a revoked or expired pass, the log is flagged and a Held
 *     incident is opened for the security office.
 *   - The log keeps the real event time (logged_at); synced_at is when it reached the server.
 *   - A stale event never overwrites a newer vehicle / pass state.
 *   - A repeated client_ref returns "duplicate" instead of writing a second row.
 *   - A visitor pass issued offline keeps the pass code the phone gave the visitor, is valid on the day it was issued
 *     (not the day it syncs), and is marked with synced_at. If the plate belongs to a registered vehicle no pass is
 *     created (registered vehicles use their own pass): the entry is recorded against the vehicle and flagged.
 *   - Events older than SP_OFFLINE_MAX_HOURS (default 24) are refused (EVENT_TOO_OLD) and stay on the phone.
 *   - An event time more than 5 minutes in the future (phone clock ahead) is clamped to now and noted.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/records.php';

const SP_SYNC_MAX_BATCH = 50;

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(405, null, 'Method not allowed');
}

$actor = requireStaffOrScanner($pdo);

if (!columnExists($pdo, 'gate_logs', 'client_ref') || !columnExists($pdo, 'security_incidents', 'client_ref')) {
    sendResponse(503, ['code' => 'MIGRATION_REQUIRED'], 'Offline sync needs database migration 006 (send the events again later).');
}

$data = getJsonInput();
$events = $data['events'] ?? null;
if (!is_array($events) || !$events) {
    sendResponse(400, null, 'Send { "events": [ ... ] } with at least one event.');
}
if (count($events) > SP_SYNC_MAX_BATCH) {
    sendResponse(400, null, 'At most ' . SP_SYNC_MAX_BATCH . ' events per request.');
}

$now = time();
$maxHours = defined('SP_OFFLINE_MAX_HOURS') ? max(1, (int)SP_OFFLINE_MAX_HOURS) : 24;

/* Oldest first, so a vehicle's entry is recorded before its exit */
$queue = [];
foreach (array_values($events) as $i => $event) {
    $event = is_array($event) ? $event : [];
    $when = syncEventTime($event['occurred_at'] ?? '', $now, $maxHours);
    $queue[] = ['event' => $event, 'when' => $when, 'order' => $i];
}
usort($queue, function ($a, $b) {
    return [$a['when']['ts'] ?? PHP_INT_MAX, $a['order']] <=> [$b['when']['ts'] ?? PHP_INT_MAX, $b['order']];
});

$results = [];
foreach ($queue as $item) {
    $event = $item['event'];
    $ref = trim((string)($event['client_ref'] ?? ''));
    try {
        $results[] = syncOneEvent($pdo, $actor, $event, $ref, $item['when'], $now);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        $results[] = syncRecoverFromError($pdo, $ref, $e);
    }
}

sendResponse(200, [
    'results' => $results,
    'serverTime' => date('Y-m-d H:i:s', $now),
    'maxAgeHours' => $maxHours,
], count($results) . ' event(s) processed.');

/* -------------------------------------------------------------------------- */

/**
 * An unexpected error (deadlock, lock timeout, dropped connection, two sends of the same event racing on the
 * client_ref unique index) says nothing about the event itself, so it is never reported as "rejected":
 *   - if a concurrent request already recorded the event, it is a "duplicate";
 *   - otherwise the device is told to "retry" and keeps the event queued.
 */
function syncRecoverFromError($pdo, $ref, Throwable $e) {
    try {
        if (preg_match('/^[A-Za-z0-9._:-]{8,64}$/', $ref)) {
            $stmt = $pdo->prepare("SELECT `id` FROM `gate_logs` WHERE `client_ref` = ? LIMIT 1");
            $stmt->execute([$ref]);
            if ($id = $stmt->fetchColumn()) {
                return syncResult($ref, 'duplicate', null, 'Already recorded.', ['id' => (int)$id]);
            }
            $stmt = $pdo->prepare("SELECT `id`, `case_number` FROM `security_incidents` WHERE `client_ref` = ? LIMIT 1");
            $stmt->execute([$ref]);
            if ($row = $stmt->fetch()) {
                return syncResult($ref, 'duplicate', null, 'Already recorded.', ['id' => (int)$row['id'], 'caseNumber' => $row['case_number']]);
            }
        }
    } catch (Throwable $ignored) {
        // the database is struggling: fall through to "retry"
    }
    return syncResult($ref, 'retry', 'TEMPORARY_ERROR', 'The server could not process this event right now. Send it again.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
}

function syncResult($ref, $status, $code = null, $message = null, array $extra = []) {
    $r = ['client_ref' => $ref, 'status' => $status];
    if ($code !== null) $r['code'] = $code;
    if ($message !== null) $r['message'] = $message;
    return $r + $extra;
}

/**
 * Parses the event time. Returns ['ts' => int, 'clamped' => bool] or ['error' => [code, message]].
 */
function syncEventTime($raw, $now, $maxHours) {
    $raw = trim((string)$raw);
    if ($raw === '') return ['error' => ['MISSING_OCCURRED_AT', 'occurred_at is required.']];
    $raw = preg_replace('/(\d{2}:\d{2}:\d{2})\.\d+/', '$1', $raw); // drop fractional seconds
    $ts = strtotime($raw);
    if ($ts === false) return ['error' => ['INVALID_OCCURRED_AT', 'occurred_at is not a valid date and time.']];
    $clamped = false;
    if ($ts > $now + 300) {
        $ts = $now;
        $clamped = true;
    }
    if ($ts < $now - $maxHours * 3600) {
        return ['error' => ['EVENT_TOO_OLD', "This event is older than {$maxHours} hours and can no longer be synced automatically. Give it to the security office."], 'ts' => $ts];
    }
    return ['ts' => $ts, 'clamped' => $clamped];
}

function syncOneEvent($pdo, $actor, array $event, $ref, array $when, $now) {
    if (!preg_match('/^[A-Za-z0-9._:-]{8,64}$/', $ref)) {
        return syncResult($ref, 'rejected', 'INVALID_CLIENT_REF', 'client_ref must be 8-64 characters (letters, digits . _ : -).');
    }
    $type = (string)($event['type'] ?? '');
    $payload = is_array($event['payload'] ?? null) ? $event['payload'] : [];

    if (!in_array($type, ['gate_log', 'visitor_exit', 'incident', 'visitor_pass'], true)) {
        return syncResult($ref, 'rejected', 'UNKNOWN_TYPE', 'Unknown event type.');
    }
    if (isset($when['error'])) {
        return syncResult($ref, 'rejected', $when['error'][0], $when['error'][1]);
    }

    $ts = $when['ts'];
    $notes = 'Recorded offline: event ' . date('Y-m-d H:i:s', $ts) . ', synced ' . date('Y-m-d H:i:s', $now)
        . ($when['clamped'] ? ' (device clock was ahead; event time set to sync time)' : '');

    // Test hook (SP_DEBUG only, like ?now=): simulate an unexpected failure before, or right after, the event is stored
    $forcedFailure = SP_DEBUG ? (string)($payload['_test_fail'] ?? '') : '';
    if ($forcedFailure === 'before') {
        throw new RuntimeException('forced failure before processing (test)');
    }

    if ($type === 'gate_log') $result = syncGateLog($pdo, $actor, $ref, $ts, $payload, $notes, $now);
    elseif ($type === 'incident') $result = syncIncident($pdo, $actor, $ref, $ts, $payload, $notes);
    elseif ($type === 'visitor_pass') $result = syncVisitorPass($pdo, $actor, $ref, $ts, $payload, $now);
    else $result = syncVisitorExit($pdo, $ref, $ts, $payload);

    if ($forcedFailure === 'after_commit') {
        throw new RuntimeException('forced failure after commit (test)');
    }
    return $result;
}

function syncGateLog($pdo, $actor, $ref, $ts, array $p, $offlineNote, $now) {
    $dup = $pdo->prepare("SELECT `id` FROM `gate_logs` WHERE `client_ref` = ? LIMIT 1");
    $dup->execute([$ref]);
    if ($existing = $dup->fetchColumn()) {
        return syncResult($ref, 'duplicate', null, 'Already recorded.', ['id' => (int)$existing]);
    }

    $plate = strtoupper(trim((string)($p['plate'] ?? $p['plateNumber'] ?? $p['plate_number'] ?? '')));
    if ($plate === '') return syncResult($ref, 'rejected', 'MISSING_PLATE', 'The event has no plate number.');
    $action = normalizeGateAction(trim((string)($p['action'] ?? 'Entry Recorded')));
    if ($action === null) return syncResult($ref, 'rejected', 'INVALID_ACTION', 'Unknown gate action.');

    $gateType = in_array($action, ['Exit Approved', 'Exit Denied'], true) ? 'Egress' : 'Ingress';
    $isApproval = in_array($action, ['Entry Recorded', 'Exit Approved'], true);
    $occurred = date('Y-m-d H:i:s', $ts);
    $eventDay = date('Y-m-d', $ts);

    $vehicle = findVehicleByPlate($pdo, $plate);
    $visitor = $vehicle ? null : findVisitorPassByPlate($pdo, $plate, $eventDay, true);
    $isVip = isVipVehicle($vehicle);

    /* What the server knows now that the guard could not know offline (entries only; exits are never questioned) */
    $flags = [];
    if ($isApproval && $gateType === 'Ingress') {
        if ($vehicle) {
            if ((int)$vehicle['is_banned'] === 1) $flags[] = 'BANNED';
            elseif ($vehicle['registration_status'] === 'Suspended') $flags[] = 'SUSPENDED';
            if ((int)($vehicle['is_retired'] ?? 0) === 1) $flags[] = 'RETIRED';
            if (($vehicle['payment_status'] ?? 'Paid') === 'Unpaid') $flags[] = 'UNPAID';
            if (vehiclePassExpired($vehicle, $eventDay)) $flags[] = 'EXPIRED_PASS';
            $syncDriver = trim((string)($p['driverName'] ?? $p['driver_name'] ?? ''));
            if (!$isVip && !findAuthorizedDriverByName($pdo, $vehicle['id'], $syncDriver)) $flags[] = 'DRIVER_NOT_LISTED';
        } elseif ($visitor) {
            $insideNow = !empty($visitor['entry_time']) && empty($visitor['exit_time']);
            if ($visitor['status'] === 'Revoked' && empty($visitor['exit_time'])) $flags[] = 'REVOKED';
            elseif ($visitor['valid_date'] > $eventDay) $flags[] = 'NOT_YET_VALID';
            elseif ($visitor['valid_date'] < $eventDay && !$insideNow) $flags[] = 'EXPIRED_TEMP';
            elseif (!empty($visitor['exit_time']) && $visitor['status'] !== 'Active') $flags[] = 'PASS_USED';
        } else {
            $flags[] = 'UNREGISTERED';
        }
    }

    $driverName = trim((string)($p['driverName'] ?? $p['driver_name'] ?? ''));
    $driverRelationship = trim((string)($p['driverRelationship'] ?? $p['driver_relationship'] ?? ''));
    if ($visitor && $isApproval && $driverName === '') {
        $driverName = $visitor['visitor_name'];
        $driverRelationship = 'Visitor (Day Pass)';
    }
    if ($driverName === '') $driverName = $isVip ? $vehicle['owner_name'] : 'Unverified';
    if ($driverRelationship === '') $driverRelationship = $isVip ? 'VIP (driver not checked)' : 'Unverified';

    $noteParts = [];
    if ($isVip) $noteParts[] = 'VIP pass';
    $original = trim((string)($p['notes'] ?? ''));
    if ($original !== '') $noteParts[] = $original;
    $noteParts[] = $offlineNote;
    if ($flags) $noteParts[] = 'FLAGGED AT SYNC: ' . implode(', ', $flags);
    $notes = implode(' | ', $noteParts);
    if (!empty($p['guardName'])) $notes .= ' [Mobile operator: ' . mb_substr((string)$p['guardName'], 0, 100) . ']';

    $storedPlate = $vehicle['plate_number'] ?? ($visitor['plate_number'] ?? $plate);
    $gatePoint = trim((string)($p['gatePoint'] ?? '')) ?: defaultGatePoint($gateType);
    $status = $isApproval ? ($gateType === 'Egress' ? 'Exited' : 'Inside Campus') : ($gateType === 'Egress' ? 'Inside Campus' : 'Outside');

    $incident = null;
    $pdo->beginTransaction();
    $logId = recordGateLog($pdo, $actor, [
        'plate' => $storedPlate,
        'vehicleType' => $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : ($p['vehicleType'] ?? null)),
        'ownerName' => $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? ($p['ownerName'] ?? $driverName)),
        'driverName' => $driverName,
        'driverRelationship' => $driverRelationship,
        'gatePoint' => $gatePoint,
        'action' => $action,
        'gateType' => $gateType,
        'status' => $status,
        'notes' => $notes,
        'loggedAt' => $occurred,
        'syncedAt' => date('Y-m-d H:i:s', $now),
        'clientRef' => $ref,
    ]);

    /* Vehicle / pass state follows the event only when no newer passage is already on record */
    if ($isApproval) {
        $newer = $pdo->prepare("SELECT COUNT(*) FROM `gate_logs` WHERE `plate_number` = ? AND `action` IN ('Entry Recorded', 'Exit Approved') AND `logged_at` > ? AND `id` <> ?");
        $newer->execute([normalizePlateForLog($storedPlate), $occurred, $logId]);
        $isLatest = (int)$newer->fetchColumn() === 0;

        if ($isLatest && $vehicle) {
            if ($gateType === 'Ingress') {
                $pdo->prepare("UPDATE `vehicles` SET `status` = 'Inside Campus', `last_entry_time` = ?, `last_gate_point` = ? WHERE `id` = ?")
                    ->execute([$occurred, $gatePoint, $vehicle['id']]);
            } else {
                $pdo->prepare("UPDATE `vehicles` SET `status` = 'Outside', `last_gate_point` = ? WHERE `id` = ?")
                    ->execute([$gatePoint, $vehicle['id']]);
            }
        }
        if ($visitor) {
            if ($gateType === 'Ingress') {
                $pdo->prepare("UPDATE `visitor_passes` SET `entry_time` = COALESCE(`entry_time`, ?) WHERE `id` = ?")->execute([$occurred, $visitor['id']]);
            } else {
                $pdo->prepare("UPDATE `visitor_passes` SET `exit_time` = COALESCE(`exit_time`, ?), `status` = 'Revoked' WHERE `id` = ?")
                    ->execute([$occurred, $visitor['id']]);
            }
        }
    }

    /* The vehicle is already on campus: tell the security office instead of pretending it was refused */
    if ($flags) {
        $incident = openSecurityIncident($pdo, $actor, [
            'plate' => $storedPlate,
            'vehicleType' => $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : ($p['vehicleType'] ?? null)),
            'ownerName' => $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? null),
            'ownerRole' => $vehicle['owner_role'] ?? ($visitor ? 'Visitor' : null),
            'driverName' => $driverName,
            'driverRelationship' => $driverRelationship,
            'reason' => 'Offline entry needs review',
            'gatePoint' => $gatePoint,
            'notes' => 'Admitted offline at ' . $occurred . '; at sync the server found: ' . implode(', ', $flags) . '. The vehicle is on campus.',
            'reportedAt' => date('Y-m-d H:i:s', $now),
        ], 60);
    }
    $pdo->commit();

    return syncResult($ref, 'accepted', null, null, [
        'id' => $logId,
        'flags' => $flags,
        'caseNumber' => $incident['caseNumber'] ?? null,
    ]);
}

function syncIncident($pdo, $actor, $ref, $ts, array $p, $offlineNote) {
    $dup = $pdo->prepare("SELECT `id`, `case_number` FROM `security_incidents` WHERE `client_ref` = ? LIMIT 1");
    $dup->execute([$ref]);
    if ($row = $dup->fetch()) {
        return syncResult($ref, 'duplicate', null, 'Already recorded.', ['id' => (int)$row['id'], 'caseNumber' => $row['case_number']]);
    }
    $plate = strtoupper(trim((string)($p['plateNumber'] ?? $p['plate'] ?? '')));
    if ($plate === '') return syncResult($ref, 'rejected', 'MISSING_PLATE', 'The incident has no plate number.');

    $vehicle = findVehicleByPlate($pdo, $plate);
    $original = trim((string)($p['notes'] ?? ''));
    $notes = ($original !== '' ? $original . ' | ' : '') . $offlineNote;
    if (!empty($p['officer'])) $notes .= ' [Mobile operator: ' . mb_substr((string)$p['officer'], 0, 100) . ']';

    $pdo->beginTransaction();
    $incident = openSecurityIncident($pdo, $actor, [
        'plate' => $vehicle['plate_number'] ?? $plate,
        'vehicleType' => $vehicle['vehicle_type'] ?? ($p['vehicleType'] ?? 'Vehicle'),
        'ownerName' => $vehicle['owner_name'] ?? ($p['ownerName'] ?? 'Unknown'),
        'ownerRole' => $vehicle['owner_role'] ?? ($p['ownerRole'] ?? 'Visitor'),
        'driverName' => $p['driverName'] ?? 'Unknown',
        'driverRelationship' => $p['driverRelationship'] ?? 'Unregistered Driver',
        'reason' => trim((string)($p['reason'] ?? '')) ?: 'Security Verification',
        'gatePoint' => $p['gatePoint'] ?? 'Gate 1 (Main Ingress)',
        'notes' => $notes,
        'reportedAt' => date('Y-m-d H:i:s', $ts),
        'clientRef' => $ref,
        'notifyOwner' => true,
    ]);
    if ($vehicle && $vehicle['status'] === 'Inside Campus') {
        $pdo->prepare("UPDATE `vehicles` SET `status` = 'Blocked / Alert' WHERE `id` = ?")->execute([$vehicle['id']]);
    }
    $pdo->commit();
    return syncResult($ref, 'accepted', null, null, ['id' => $incident['id'], 'caseNumber' => $incident['caseNumber']]);
}

function syncVisitorExit($pdo, $ref, $ts, array $p) {
    $passCode = trim((string)($p['passId'] ?? $p['pass_code'] ?? ''));
    $plate = trim((string)($p['plateNumber'] ?? $p['plate'] ?? ''));
    $occurred = date('Y-m-d H:i:s', $ts);

    $pass = null;
    if ($passCode !== '') {
        $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `pass_code` = ? LIMIT 1");
        $stmt->execute([$passCode]);
        $pass = $stmt->fetch() ?: null;
    }
    if (!$pass && $plate !== '') {
        $pass = findVisitorPassByPlate($pdo, $plate, date('Y-m-d', $ts), true);
    }
    if (!$pass) return syncResult($ref, 'rejected', 'NOT_FOUND', 'No visitor pass matches this checkout.');

    // Checking out twice is harmless: the first exit time is kept
    $pdo->prepare("UPDATE `visitor_passes` SET `exit_time` = COALESCE(`exit_time`, ?), `status` = 'Revoked' WHERE `id` = ?")
        ->execute([$occurred, $pass['id']]);
    return syncResult($ref, 'accepted', null, null, ['id' => (int)$pass['id']]);
}

function syncVisitorPass($pdo, $actor, $ref, $ts, array $p, $now) {
    $pick = function (array $keys, $max) use ($p) {
        foreach ($keys as $k) {
            if (isset($p[$k]) && trim((string)$p[$k]) !== '') return mb_substr(trim((string)$p[$k]), 0, $max);
        }
        return '';
    };
    $name = $pick(['visitor_name', 'visitorName'], 150);
    $contact = $pick(['contact_number', 'contactNumber', 'contact'], 20);
    $plate = normalizePlate($pick(['plate', 'plate_number', 'plateNumber'], 20));
    $model = $pick(['vehicle_model', 'vehicleModel'], 100);
    $purpose = $pick(['purpose', 'purpose_of_visit', 'purposeOfVisit'], 255);
    $host = $pick(['person_to_visit', 'personToVisit'], 150);

    $missing = [];
    if ($name === '') $missing[] = 'visitor name';
    if ($contact === '') $missing[] = 'contact number';
    if ($plate === '') $missing[] = 'plate number';
    if ($purpose === '') $missing[] = 'purpose of visit';
    if ($host === '') $missing[] = 'person / department to visit';
    if ($missing) {
        return syncResult($ref, 'rejected', 'MISSING_FIELDS', 'Missing: ' . implode(', ', $missing) . '.');
    }
    if (strlen($plate) < 2) return syncResult($ref, 'rejected', 'INVALID_PLATE', 'The plate number is not valid.');

    // The visitor already has this pass in hand, so validation is deliberately lenient (no phone-number format check)
    $items = [];
    $rawItems = $p['items'] ?? [];
    if ($rawItems !== null && $rawItems !== '' && !is_array($rawItems)) {
        return syncResult($ref, 'rejected', 'INVALID_ITEMS', 'items must be a list.');
    }
    foreach (array_values((array)$rawItems) as $item) {
        if (!is_array($item)) return syncResult($ref, 'rejected', 'INVALID_ITEMS', 'Each item needs a name and quantity.');
        $itemName = mb_substr(trim((string)($item['name'] ?? '')), 0, 100);
        $desc = mb_substr(trim((string)($item['description'] ?? '')), 0, 255);
        $qty = $item['quantity'] ?? 1;
        if ($itemName === '' && $desc === '') continue;
        if ($itemName === '') return syncResult($ref, 'rejected', 'INVALID_ITEMS', 'An item has no name.');
        if (!is_numeric($qty) || (int)$qty != $qty || (int)$qty < 1 || (int)$qty > 9999) {
            return syncResult($ref, 'rejected', 'INVALID_ITEMS', "Quantity for \"{$itemName}\" must be a whole number from 1 to 9999.");
        }
        $items[] = ['name' => $itemName, 'quantity' => (int)$qty, 'description' => $desc !== '' ? $desc : null];
    }
    if (count($items) > 20) return syncResult($ref, 'rejected', 'INVALID_ITEMS', 'A day pass can list at most 20 items.');

    $eventDay = date('Y-m-d', $ts);
    $occurred = date('Y-m-d H:i:s', $ts);

    /* Registered vehicles use their own permanent pass. The guard already admitted it, so tell the security office. */
    if ($vehicle = findVehicleByPlate($pdo, $plate)) {
        $pdo->beginTransaction();
        $incident = openSecurityIncident($pdo, $actor, [
            'plate' => $vehicle['plate_number'],
            'vehicleType' => $vehicle['vehicle_type'],
            'ownerName' => $vehicle['owner_name'],
            'ownerRole' => $vehicle['owner_role'],
            'driverName' => $name,
            'driverRelationship' => 'Visitor (day pass issued offline)',
            'reason' => 'Offline visitor pass for a registered vehicle',
            'gatePoint' => $p['gatePoint'] ?? defaultGatePoint('Ingress'),
            'notes' => "A visitor pass was issued offline at {$occurred} for {$vehicle['plate_number']}, which is a registered campus vehicle"
                . ((int)$vehicle['is_banned'] === 1 ? ' and is BANNED' : '') . '. No pass was created; the vehicle must use its own pass.',
            'reportedAt' => date('Y-m-d H:i:s', $now),
        ], 60);
        $pdo->commit();
        return syncResult($ref, 'accepted', null, null, ['flags' => ['PLATE_REGISTERED'], 'caseNumber' => $incident['caseNumber']]);
    }

    $code = $pick(['passCode', 'passId', 'pass_code'], 40);
    if (!preg_match('/^[A-Za-z0-9._-]{6,40}$/', $code)) {
        $code = newVisitorPassCode($pdo, $eventDay); // the phone sent no usable code: the server assigns one
    }

    $stmt = $pdo->prepare("SELECT `id`, `plate_number` FROM `visitor_passes` WHERE `pass_code` = ? LIMIT 1");
    $stmt->execute([$code]);
    if ($existing = $stmt->fetch()) {
        if ($existing['plate_number'] === $plate) {
            return syncResult($ref, 'duplicate', null, 'This pass was already recorded.', ['id' => (int)$existing['id'], 'passCode' => $code]);
        }
        return syncResult($ref, 'rejected', 'CODE_CONFLICT', 'That pass code already belongs to a different vehicle.');
    }
    $stmt = $pdo->prepare("SELECT `id`, `pass_code` FROM `visitor_passes` WHERE `plate_number` = ? AND `valid_date` = ? AND `status` = 'Active' LIMIT 1");
    $stmt->execute([$plate, $eventDay]);
    if ($sameDay = $stmt->fetch()) {
        return syncResult($ref, 'duplicate', null, 'An active pass for this plate already exists for that day; it is used for the entry.',
            ['id' => (int)$sameDay['id'], 'passCode' => $sameDay['pass_code']]);
    }

    $createdBy = actorLabel($actor);
    if (!empty($p['registeredByGuard'])) $createdBy .= ' / ' . mb_substr((string)$p['registeredByGuard'], 0, 100);

    $columns = ['pass_code', 'visitor_name', 'contact_number', 'plate_number', 'vehicle_model', 'purpose_of_visit', 'person_to_visit',
        'valid_date', 'status', 'created_by', 'created_by_user_id', 'created_at'];
    $values = [$code, $name, $contact, $plate, $model !== '' ? $model : null, $purpose, $host, $eventDay, 'Active', $createdBy, actorUserId($actor), $occurred];
    if (columnExists($pdo, 'visitor_passes', 'synced_at')) {
        $columns[] = 'synced_at';
        $values[] = date('Y-m-d H:i:s', $now);
    }
    $pdo->beginTransaction();
    $marks = implode(', ', array_fill(0, count($columns), '?'));
    $pdo->prepare("INSERT INTO `visitor_passes` (`" . implode('`, `', $columns) . "`) VALUES ({$marks})")->execute($values);
    $passId = (int)$pdo->lastInsertId();
    $itemStmt = $pdo->prepare("INSERT INTO `visitor_pass_items` (`visitor_pass_id`, `item_name`, `quantity`, `description`) VALUES (?, ?, ?, ?)");
    foreach ($items as $item) {
        $itemStmt->execute([$passId, $item['name'], $item['quantity'], $item['description']]);
    }
    $pdo->commit();

    return syncResult($ref, 'accepted', null, null, ['id' => $passId, 'passCode' => $code, 'flags' => []]);
}
