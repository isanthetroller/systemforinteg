<?php
/**
 * SecurePark API - Second-admin approvals (admin only)
 *
 * GET  /api/approvals.php[?status=Pending|Approved|Rejected]   Requests (newest first) + the number still pending
 * POST /api/approvals.php { id, decision: "approve" | "reject", note? }
 *        A request can only be decided by an administrator other than the one who made it.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/approvals.php';

$admin = requireStaff($pdo, ['admin']);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $status = $_GET['status'] ?? '';
    $sql = "SELECT * FROM `approval_requests`";
    $params = [];
    if (in_array($status, ['Pending', 'Approved', 'Rejected'], true)) {
        $sql .= " WHERE `status` = ?";
        $params[] = $status;
    }
    $stmt = $pdo->prepare($sql . " ORDER BY `id` DESC LIMIT 200");
    $stmt->execute($params);
    $pending = (int)$pdo->query("SELECT COUNT(*) FROM `approval_requests` WHERE `status` = 'Pending'")->fetchColumn();
    sendResponse(200, [
        'pending' => $pending,
        'secondAdminAvailable' => needsSecondAdmin($pdo),
        'me' => ['id' => actorUserId($admin)],
        'requests' => array_map('approvalView', $stmt->fetchAll()),
    ]);
}

if ($method === 'POST') {
    $data = getJsonInput();
    $decision = $data['decision'] ?? '';
    if (!in_array($decision, ['approve', 'reject'], true)) sendResponse(400, null, 'decision must be approve or reject.');
    $note = trim((string)($data['note'] ?? ''));
    if ($decision === 'reject' && mb_strlen($note) < 3) sendResponse(400, ['code' => 'REASON_REQUIRED'], 'Tell the requester why it was rejected.');

    $pdo->beginTransaction();
    try {
        $result = decideApproval($pdo, $admin, (int)($data['id'] ?? 0), $decision === 'approve', $note);
        if ($result['ok']) $pdo->commit(); else $pdo->rollBack();
    } catch (Exception $e) {
        $pdo->rollBack();
        sendResponse(500, null, 'Could not record the decision.' . (SP_DEBUG ? ' ' . $e->getMessage() : ''));
    }
    if (!$result['ok']) sendResponse($result['code'], null, $result['message']);
    sendResponse(200, ['request' => approvalView($result['request'])], $result['message']);
}

sendResponse(405, null, "Method {$method} not allowed");
