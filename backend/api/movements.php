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
if (($data['action'] ?? '') !== 'confirm') sendResponse(400, null, 'Choose prepare or confirm.');
try {
    $result = confirmMovement($pdo, $actor, $data);
    sendResponse($result['duplicate'] ? 200 : 201, $result, $result['duplicate'] ? 'This confirmation was already saved.' : 'Movement saved.');
} catch (MovementFailure $e) {
    sendResponse($e->httpStatus, ['code' => $e->errorCode], $e->getMessage());
} catch (Throwable $e) {
    sendResponse(503, ['code' => 'CONFIRM_RETRY'], 'Could not confirm the movement. Retry this confirmation; do not scan again until its result is known.');
}
