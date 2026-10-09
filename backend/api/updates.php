<?php
/** Authenticated snapshot revisions. No database writes or long-lived PHP workers.
 * Every response checks the current session. Fingerprints detect inserts, edits and deletions,
 * including changes made outside this API. Clients acknowledge revisions only after reconciliation.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
if ($_SERVER['REQUEST_METHOD'] !== 'GET') sendResponse(405, null, 'Method not allowed');
header('Cache-Control: no-store, private');
$auth = resolveAuth($pdo);
if (!$auth) sendResponse(401, ['code' => 'AUTH_REQUIRED'], 'Your session has ended. Please sign in again.');
$user = $auth['type'] === 'student' ? requireStudent($pdo) : requireStaff($pdo);
$isOwner = $auth['type'] === 'student';
$isAdmin = !$isOwner && $user['role'] === 'admin';
$owner = $isOwner ? $user['owner_id_number'] : null;
$ownVehicle = 'SELECT id FROM vehicles WHERE owner_id_number = ?';
$ownPlate = "SELECT REPLACE(REPLACE(UPPER(plate_number), '-', ''), ' ', '') FROM vehicles WHERE owner_id_number = ?";
$plateFilter = "REPLACE(REPLACE(UPPER(plate_number), '-', ''), ' ', '') IN ($ownPlate)";
$groups = [
 'vehicles' => ['vehicles', 'authorized_drivers'], 'movements' => ['gate_logs'],
 'cases' => ['vehicle_violations', 'security_incidents', 'case_events', 'exit_releases'],
];
if (!$isOwner) $groups += ['visitors' => ['visitor_passes', 'visitor_pass_items'], 'shifts' => ['guard_shifts'], 'settings' => ['system_settings'], 'evidence' => ['evidence_photos']];
if ($isOwner || $isAdmin) $groups['payments'] = ['payments'];
if ($isOwner) $groups['notices'] = ['owner_notices'];
if ($isAdmin) $groups += ['staff' => ['system_users'], 'approvals' => ['approval_requests'], 'activity' => ['audit_log']];
$revisions = [];
foreach ($groups as $domain => $tables) {
    $hash = hash_init('sha256', HASH_HMAC, SP_QR_SECRET);
    foreach ($tables as $table) {
        $where = ''; $params = [];
        if ($isOwner) {
            switch ($table) {
                case 'vehicles': case 'payments': case 'owner_notices': $where = 'owner_id_number = ?'; break;
                case 'authorized_drivers': case 'vehicle_violations': case 'exit_releases': $where = "vehicle_id IN ($ownVehicle)"; break;
                case 'gate_logs': case 'security_incidents': $where = $plateFilter; break;
                case 'case_events':
                    $where = "case_key IN (SELECT " . ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite' ? "'V' || id" : "CONCAT('V', id)") . " FROM vehicle_violations WHERE vehicle_id IN ($ownVehicle)) OR case_key IN (SELECT " . ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite' ? "'I' || id" : "CONCAT('I', id)") . " FROM security_incidents WHERE $plateFilter)";
                    $params = [$owner, $owner]; break;
            }
            if (!$params) $params = [$owner];
        }
        $columns = $table === 'system_users' ? 'id, username, full_name, role, gate_assigned, badge_number, status, must_change_password' : '*';
        $order = $table === 'system_settings' ? 'setting_key' : 'id';
        $stmt = $pdo->prepare("SELECT $columns FROM `$table`" . ($where ? " WHERE $where" : '') . " ORDER BY $order");
        $stmt->execute($params);
        hash_update($hash, $table);
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) hash_update($hash, json_encode($row, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE));
    }
    $revisions[$domain] = hash_final($hash);
}
$public = $isOwner ? publicStudent($user) : publicStaff($user);
$revisions['clock'] = (string)floor(time() / 60);
$revisions['session'] = hash_hmac('sha256', json_encode($public), SP_QR_SECRET);
sendResponse(200, ['revisions' => $revisions, 'user' => $public, 'serverTime' => date('c'), 'intervalMs' => 5000]);
