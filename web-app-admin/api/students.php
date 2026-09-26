<?php
/**
 * SecurePark API - Student Portal Accounts (admin only)
 *
 * GET  /api/students.php?owner_id_number=...                 Account status for an owner
 * POST /api/students.php { owner_id_number, action: "issue" } Create the account or reset its password.
 *        Returns a one-time temporary password (must be changed at first sign-in).
 * POST /api/students.php { owner_id_number, action: "set_status", status: "Active"|"Inactive" }
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/students.php';

$admin = requireStaff($pdo, ['admin']);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $ownerId = trim((string)($_GET['owner_id_number'] ?? ''));
    if ($ownerId === '') sendResponse(400, null, 'owner_id_number is required.');
    $account = findStudentAccount($pdo, $ownerId);
    sendResponse(200, $account ? publicStudent($account) : null, $account ? '' : 'No portal account yet.');
}

if ($method !== 'POST') {
    sendResponse(405, null, "Method {$method} not allowed");
}

$data = getJsonInput();
$ownerId = trim((string)($data['owner_id_number'] ?? ''));
if ($ownerId === '') sendResponse(400, null, 'owner_id_number is required.');

// The owner must have at least one registered vehicle
$stmt = $pdo->prepare("SELECT `owner_name`, `owner_email` FROM `vehicles` WHERE `owner_id_number` = ? ORDER BY `id` DESC LIMIT 1");
$stmt->execute([$ownerId]);
$owner = $stmt->fetch();
if (!$owner) {
    sendResponse(404, null, "No registered vehicle belongs to owner ID {$ownerId}.");
}

$action = $data['action'] ?? '';
if ($action === 'issue') {
    $result = resetStudentPassword($pdo, $ownerId, $owner['owner_name'], $owner['owner_email']);
    sendResponse(200, $result, "Student portal login for {$ownerId} is ready. Share the temporary password in person; it is shown only once.");
}

if ($action === 'set_status') {
    $status = $data['status'] ?? '';
    if (!in_array($status, ['Active', 'Inactive'], true)) sendResponse(400, null, 'Status must be Active or Inactive.');
    $account = findStudentAccount($pdo, $ownerId);
    if (!$account) sendResponse(404, null, 'No portal account yet.');
    $pdo->prepare("UPDATE `student_accounts` SET `status` = ? WHERE `id` = ?")->execute([$status, $account['id']]);
    if ($status === 'Inactive') revokeUserTokens($pdo, 'student', (int)$account['id']);
    sendResponse(200, publicStudent(findStudentAccount($pdo, $ownerId)), "Portal account {$ownerId} is now {$status}.");
}

sendResponse(400, null, 'Unknown action. Use issue or set_status.');
