<?php
/** Side-effect-free scan preparation followed by an explicit, idempotent confirmation. */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/movements.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') sendResponse(405, null, 'Method not allowed');
$actor = requireStaff($pdo);
$data = getJsonInput();
if (($data['action'] ?? '') === 'prepare') {
    $spMovementPreparation = true;
    require __DIR__ . '/verify.php';
    exit;
}
if (($data['action'] ?? '') === 'report_discrepancy') {
    // A guard says the recorded state is wrong (for example a vehicle shows inside but already left without an exit scan).
    // It goes to the admin activity log for correction; it never holds the vehicle.
    require_once __DIR__ . '/../lib/audit.php';
    $plate = strtoupper(trim((string)($data['plate'] ?? '')));
    if ($plate === '' || mb_strlen($plate) > 20) sendResponse(400, null, 'A plate number is required.');
    $lane = strtoupper(trim((string)($data['direction'] ?? ''))) === 'OUT' ? 'exit' : 'entry';
    $note = mb_substr(trim((string)($data['note'] ?? '')), 0, 200);
    $recorded = ($data['recorded'] ?? '') === 'INSIDE' ? 'inside campus' : 'outside campus';
    auditLog($pdo, $actor, 'record.discrepancy', [
        'entityType' => 'vehicle', 'plate' => $plate,
        'detail' => "Scanned at the {$lane} lane but the record says the vehicle is {$recorded}. The guard reports the record is wrong." . ($note !== '' ? " Note: {$note}" : ''),
    ]);
    sendResponse(201, ['reported' => true], 'Reported. An admin will check the record.');
}
if (($data['action'] ?? '') !== 'confirm') sendResponse(400, null, 'Choose prepare, confirm or report_discrepancy.');
try {
    $result = confirmMovement($pdo, $actor, $data);
    sendResponse($result['duplicate'] ? 200 : 201, $result, $result['duplicate'] ? 'This confirmation was already saved.' : 'Movement saved.');
} catch (MovementFailure $e) {
    sendResponse($e->httpStatus, ['code' => $e->errorCode], $e->getMessage());
} catch (Throwable $e) {
    sendResponse(503, ['code' => 'CONFIRM_RETRY'], 'Could not confirm the movement. Retry this confirmation; do not scan again until its result is known.');
}
