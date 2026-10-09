<?php
/**
 * SecurePark API - Guard evidence photos
 *
 * POST /api/evidence.php  { kind: entry|exit|violation|incident, plate, image (JPEG/PNG, base64 or data URL),
 *                           gateLogId?, violationId?, incidentId?, plateRead? }
 *      Signed-in guard or admin. Stores the photo with the record it belongs to. When the phone read a plate off the photo
 *      (plateRead), the server compares it with the plate on the pass and stores the result (plateMatches).
 * GET  /api/evidence.php?violationId=N | gateLogId=N | incidentId=N | plate=ABC123   List photo details, no pictures (admin)
 * GET  /api/evidence.php?id=N             One photo including the picture as a data URL (admin)
 *
 * Photos are removed automatically after the `evidence_retention_days` setting (maintenance job); the row stays.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/audit.php';

const SP_EVIDENCE_MAX_BYTES = 600000;   // after base64 decode; the app downsizes photos to roughly 100-250 KB
const SP_EVIDENCE_MAX_PER_RECORD = 4;

$method = $_SERVER['REQUEST_METHOD'];

/** Plates compare equal when they differ only by the usual camera confusions (O/0, I/1, B/8, S/5, Z/2). */
function platesMatchLoosely($a, $b) {
    $fold = function ($p) { return strtr(normalizePlate($p), ['O' => '0', 'Q' => '0', 'I' => '1', 'L' => '1', 'B' => '8', 'S' => '5', 'Z' => '2']); };
    $na = $fold($a);
    return $na !== '' && $na === $fold($b);
}

function evidenceView($r, $withImage = false) {
    $out = [
        'id' => (int)$r['id'], 'kind' => $r['kind'], 'plateNumber' => $r['plate_number'], 'plateRead' => $r['plate_read'],
        'plateMatches' => $r['plate_matches'] === null ? null : (bool)(int)$r['plate_matches'],
        'gateLogId' => $r['gate_log_id'] !== null ? (int)$r['gate_log_id'] : null,
        'violationId' => $r['violation_id'] !== null ? (int)$r['violation_id'] : null,
        'incidentId' => $r['incident_id'] !== null ? (int)$r['incident_id'] : null,
        'sizeBytes' => (int)$r['size_bytes'], 'takenBy' => $r['taken_by_label'], 'createdAt' => $r['created_at'],
        'purged' => $r['purged_at'] !== null,
    ];
    if ($withImage) $out['image'] = $r['data'];
    return $out;
}

if ($method === 'POST') {
    $user = requireStaff($pdo, ['admin', 'guard']);
    $data = getJsonInput();

    $kind = strtolower(trim((string)($data['kind'] ?? '')));
    if (!in_array($kind, ['entry', 'exit', 'violation', 'incident'], true)) {
        sendResponse(400, null, "kind must be one of: entry, exit, violation, incident.");
    }
    $plate = normalizePlate((string)($data['plate'] ?? ''));
    if ($plate === '') sendResponse(400, null, 'The plate number is required.');

    $gateLogId = isset($data['gateLogId']) ? (int)$data['gateLogId'] : null;
    $violationId = isset($data['violationId']) ? (int)$data['violationId'] : null;
    $incidentId = isset($data['incidentId']) ? (int)$data['incidentId'] : null;
    if (!$gateLogId && !$violationId && !$incidentId) {
        sendResponse(400, null, 'Attach the photo to a gate log, violation or incident (gateLogId, violationId or incidentId).');
    }

    // The record must exist and be about this plate
    if ($gateLogId) {
        $stmt = $pdo->prepare("SELECT `plate_number` FROM `gate_logs` WHERE `id` = ?");
        $stmt->execute([$gateLogId]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, 'Gate log not found.');
        if (normalizePlate($row['plate_number']) !== $plate) sendResponse(400, null, 'That gate log belongs to a different plate.');
    }
    if ($violationId) {
        $stmt = $pdo->prepare("SELECT `plate_number` FROM `vehicle_violations` WHERE `id` = ?");
        $stmt->execute([$violationId]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, 'Violation not found.');
        if (normalizePlate($row['plate_number']) !== $plate) sendResponse(400, null, 'That violation belongs to a different plate.');
    }
    if ($incidentId) {
        $stmt = $pdo->prepare("SELECT `plate_number` FROM `security_incidents` WHERE `id` = ?");
        $stmt->execute([$incidentId]);
        $row = $stmt->fetch();
        if (!$row) sendResponse(404, null, 'Incident not found.');
        if (normalizePlate($row['plate_number']) !== $plate) sendResponse(400, null, 'That incident belongs to a different plate.');
    }

    $count = $pdo->prepare("SELECT COUNT(*) FROM `evidence_photos` WHERE (`gate_log_id` = ? AND ? > 0) OR (`violation_id` = ? AND ? > 0) OR (`incident_id` = ? AND ? > 0)");
    $count->execute([$gateLogId, (int)$gateLogId, $violationId, (int)$violationId, $incidentId, (int)$incidentId]);
    if ((int)$count->fetchColumn() >= SP_EVIDENCE_MAX_PER_RECORD) {
        sendResponse(409, ['code' => 'TOO_MANY_PHOTOS'], 'This record already has ' . SP_EVIDENCE_MAX_PER_RECORD . ' photos.');
    }

    // Decode and validate the picture
    $image = (string)($data['image'] ?? '');
    if (preg_match('#^data:image/(jpeg|jpg|png);base64,#i', $image, $m)) {
        $image = substr($image, strlen($m[0]));
    }
    $bin = base64_decode(str_replace(["\r", "\n", ' '], '', $image), true);
    if ($bin === false || $bin === '') sendResponse(400, null, 'The photo is missing or is not valid base64.');
    if (strlen($bin) > SP_EVIDENCE_MAX_BYTES) sendResponse(413, ['code' => 'PHOTO_TOO_LARGE'], 'The photo is too large (600 KB max). Take it at a lower quality.');
    $isJpeg = substr($bin, 0, 3) === "\xFF\xD8\xFF";
    $isPng = substr($bin, 0, 8) === "\x89PNG\r\n\x1a\n";
    if (!$isJpeg && !$isPng) sendResponse(400, null, 'Only JPEG or PNG photos are accepted.');
    $dataUrl = 'data:image/' . ($isPng ? 'png' : 'jpeg') . ';base64,' . base64_encode($bin);

    $plateRead = trim((string)($data['plateRead'] ?? ''));
    $plateRead = $plateRead !== '' ? strtoupper(mb_substr($plateRead, 0, 40)) : null;
    $matches = $plateRead === null ? null : (platesMatchLoosely($plateRead, $plate) ? 1 : 0);

    $pdo->prepare("INSERT INTO `evidence_photos` (`kind`, `gate_log_id`, `violation_id`, `incident_id`, `plate_number`, `plate_read`, `plate_matches`, `size_bytes`, `data`, `taken_by_user_id`, `taken_by_label`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        ->execute([$kind, $gateLogId ?: null, $violationId ?: null, $incidentId ?: null, $plate, $plateRead, $matches, strlen($bin), $dataUrl,
            actorUserId($user), actorLabel($user), date('Y-m-d H:i:s')]);
    $id = (int)$pdo->lastInsertId();

    if ($matches === 0) {
        auditLog($pdo, $user, 'evidence.plate_mismatch', ['entityType' => 'evidence', 'entityId' => $id, 'plate' => $plate,
            'detail' => "Plate on the photo reads \"{$plateRead}\" but the pass is for {$plate} ({$kind})"]);
    }
    sendResponse(201, ['id' => $id, 'plateMatches' => $matches === null ? null : (bool)$matches, 'plateRead' => $plateRead],
        $matches === 0 ? "Photo saved, but the plate on it (\"{$plateRead}\") does not match the pass ({$plate})." : 'Photo saved.');
}

if ($method === 'GET') {
    requireStaff($pdo, ['admin']);
    if (!empty($_GET['id'])) {
        $stmt = $pdo->prepare("SELECT * FROM `evidence_photos` WHERE `id` = ?");
        $stmt->execute([(int)$_GET['id']]);
        $r = $stmt->fetch();
        if (!$r) sendResponse(404, null, 'Photo not found.');
        sendResponse(200, evidenceView($r, true));
    }
    $where = [];
    $args = [];
    foreach (['violationId' => 'violation_id', 'gateLogId' => 'gate_log_id', 'incidentId' => 'incident_id'] as $param => $col) {
        if (!empty($_GET[$param])) { $where[] = "`{$col}` = ?"; $args[] = (int)$_GET[$param]; }
    }
    if (!empty($_GET['plate'])) { $where[] = '`plate_number` = ?'; $args[] = normalizePlate($_GET['plate']); }
    if (!$where) sendResponse(400, null, 'Give violationId, gateLogId, incidentId or plate.');
    $stmt = $pdo->prepare("SELECT * FROM `evidence_photos` WHERE " . implode(' AND ', $where) . " ORDER BY `id` DESC LIMIT 50");
    $stmt->execute($args);
    sendResponse(200, array_map('evidenceView', $stmt->fetchAll()));
}

sendResponse(405, null, "Method {$method} not allowed");
