<?php
/**
 * SecurePark API - Admin action log (admin only, read-only)
 *
 * GET /api/audit.php?q=&action=&from=YYYY-MM-DD&to=YYYY-MM-DD&page=1&limit=25
 *   q matches plate, actor, detail or reason. Newest first.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/audit.php';

requireStaff($pdo, ['admin']);
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse(405, null, 'Method not allowed');
}

$where = [];
$params = [];
$q = trim((string)($_GET['q'] ?? ''));
if ($q !== '') {
    $where[] = "(`plate_number` LIKE ? OR REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') LIKE ? OR `actor_label` LIKE ? OR `detail` LIKE ? OR `reason` LIKE ?)";
    array_push($params, "%{$q}%", '%' . strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $q)) . '%', "%{$q}%", "%{$q}%", "%{$q}%");
}
$action = trim((string)($_GET['action'] ?? ''));
if ($action !== '') {
    $where[] = "`action` LIKE ?";
    $params[] = $action . '%'; // 'vehicle' matches every vehicle.* action
}
foreach (['from' => '>=', 'to' => '<='] as $key => $op) {
    $d = (string)($_GET[$key] ?? '');
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $d)) {
        $where[] = "`created_at` {$op} ?";
        $params[] = $key === 'from' ? "{$d} 00:00:00" : "{$d} 23:59:59";
    }
}
$whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';

$limit = max(1, min(100, (int)($_GET['limit'] ?? 25)));
$page = max(1, (int)($_GET['page'] ?? 1));
$offset = ($page - 1) * $limit;

$count = $pdo->prepare("SELECT COUNT(*) FROM `audit_log` {$whereSql}");
$count->execute($params);
$total = (int)$count->fetchColumn();

$stmt = $pdo->prepare("SELECT * FROM `audit_log` {$whereSql} ORDER BY `id` DESC LIMIT {$limit} OFFSET {$offset}");
$stmt->execute($params);

$actions = $pdo->query("SELECT DISTINCT `action` FROM `audit_log` ORDER BY `action`")->fetchAll(PDO::FETCH_COLUMN);

sendResponse(200, [
    'total' => $total,
    'page' => $page,
    'limit' => $limit,
    'actions' => $actions,
    'rows' => array_map('auditView', $stmt->fetchAll()),
]);
