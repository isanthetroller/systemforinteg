<?php
/**
 * SecurePark API - Staff Accounts (admin only)
 *
 * GET  /api/users.php                                   List staff accounts
 * POST /api/users.php  { username, full_name, role, badge_number, gate_assigned }
 *                                                       Create account; returns a one-time temporary password
 * PUT  /api/users.php  { id, action: "update", full_name, role, badge_number, gate_assigned }
 * PUT  /api/users.php  { id, action: "set_status", status: "Active" | "Inactive" }
 * PUT  /api/users.php  { id, action: "reset_password" } Returns a new one-time temporary password
 *
 * Accounts are never deleted (audit logs reference them); deactivate instead.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';

$admin = requireStaff($pdo, ['admin']);
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleListUsers($pdo);
        break;
    case 'POST':
        handleCreateUser($pdo);
        break;
    case 'PUT':
        handleUpdateUser($pdo, $admin);
        break;
    default:
        sendResponse(405, null, "Method {$method} not allowed");
}

function handleListUsers($pdo) {
    $rows = $pdo->query("SELECT * FROM `system_users` ORDER BY `status` ASC, `role` ASC, `full_name` ASC")->fetchAll();
    sendResponse(200, array_map('publicStaff', $rows));
}

function validRole($role) {
    return in_array($role, ['admin', 'guard'], true);
}

function handleCreateUser($pdo) {
    $data = getJsonInput();
    $username = isset($data['username']) ? strtolower(trim($data['username'])) : '';
    $fullName = isset($data['full_name']) ? trim($data['full_name']) : '';
    $role = isset($data['role']) ? $data['role'] : 'guard';
    $badge = isset($data['badge_number']) ? trim($data['badge_number']) : '';
    $gate = isset($data['gate_assigned']) ? trim($data['gate_assigned']) : 'Gate 1 (Main Ingress)';
    $customPassword = isset($data['password']) ? trim((string)$data['password']) : '';

    if (!preg_match('/^[a-z0-9._-]{3,50}$/', $username)) {
        sendResponse(400, null, 'Username must be 3-50 characters: letters, numbers, dot, dash or underscore.');
    }
    if ($fullName === '') {
        sendResponse(400, null, 'Full name is required.');
    }
    if (!validRole($role)) {
        sendResponse(400, null, 'Role must be admin or guard.');
    }

    $check = $pdo->prepare("SELECT `id` FROM `system_users` WHERE `username` = ? LIMIT 1");
    $check->execute([$username]);
    if ($check->fetch()) {
        sendResponse(409, null, "Username {$username} is already taken.");
    }

    if ($customPassword !== '') {
        if (strlen($customPassword) < 6) {
            sendResponse(400, null, 'Custom password must be at least 6 characters.');
        }
        $finalPassword = $customPassword;
        $mustChange = 0;
    } else {
        $finalPassword = generateTempPassword();
        // Guards are never forced to change password because they operate the gate mobile terminal
        $mustChange = ($role === 'admin') ? 1 : 0;
    }

    $stmt = $pdo->prepare("INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`) VALUES (?, ?, ?, ?, ?, ?, 'Active', ?)");
    $stmt->execute([$username, password_hash($finalPassword, PASSWORD_BCRYPT), $fullName, $role, $badge ?: null, $gate ?: null, $mustChange]);

    $row = fetchUser($pdo, (int)$pdo->lastInsertId());
    $msg = $customPassword !== ''
        ? "Account {$username} created with the specified password."
        : "Account {$username} created. Password: {$finalPassword}";
    sendResponse(201, ['user' => publicStaff($row), 'tempPassword' => $finalPassword], $msg);
}

function fetchUser($pdo, $id) {
    $stmt = $pdo->prepare("SELECT * FROM `system_users` WHERE `id` = ? LIMIT 1");
    $stmt->execute([$id]);
    return $stmt->fetch();
}

function countActiveAdmins($pdo) {
    return (int)$pdo->query("SELECT COUNT(*) FROM `system_users` WHERE `role` = 'admin' AND `status` = 'Active'")->fetchColumn();
}

function handleUpdateUser($pdo, $admin) {
    $data = getJsonInput();
    $id = isset($data['id']) ? (int)$data['id'] : 0;
    $action = isset($data['action']) ? $data['action'] : 'update';
    $row = $id > 0 ? fetchUser($pdo, $id) : null;
    if (!$row) {
        sendResponse(404, null, 'Staff account not found.');
    }
    $isSelf = (int)$row['id'] === (int)$admin['id'];
    $isLastAdmin = $row['role'] === 'admin' && $row['status'] === 'Active' && countActiveAdmins($pdo) <= 1;

    if ($action === 'set_status') {
        $status = isset($data['status']) ? $data['status'] : '';
        if (!in_array($status, ['Active', 'Inactive'], true)) {
            sendResponse(400, null, 'Status must be Active or Inactive.');
        }
        if ($status === 'Inactive' && $isSelf) {
            sendResponse(400, null, 'You cannot deactivate your own account.');
        }
        if ($status === 'Inactive' && $isLastAdmin) {
            sendResponse(400, null, 'You cannot deactivate the last active administrator.');
        }
        $pdo->prepare("UPDATE `system_users` SET `status` = ? WHERE `id` = ?")->execute([$status, $id]);
        if ($status === 'Inactive') {
            revokeUserTokens($pdo, 'staff', $id);
        }
        sendResponse(200, publicStaff(fetchUser($pdo, $id)), "Account {$row['username']} is now {$status}.");
    }

    if ($action === 'reset_password') {
        $customPassword = isset($data['password']) ? trim((string)$data['password']) : '';
        if ($customPassword !== '') {
            if (strlen($customPassword) < 6) {
                sendResponse(400, null, 'Custom password must be at least 6 characters.');
            }
            $finalPassword = $customPassword;
            $mustChange = 0;
        } else {
            $finalPassword = generateTempPassword();
            $mustChange = ($row['role'] === 'admin') ? 1 : 0;
        }
        $stmt = $pdo->prepare("UPDATE `system_users` SET `password_hash` = ?, `must_change_password` = ?, `failed_attempts` = 0, `locked_until` = NULL WHERE `id` = ?");
        $stmt->execute([password_hash($finalPassword, PASSWORD_BCRYPT), $mustChange, $id]);
        revokeUserTokens($pdo, 'staff', $id);
        sendResponse(200, ['user' => publicStaff(fetchUser($pdo, $id)), 'tempPassword' => $finalPassword],
            "Password for {$row['username']} was updated.");
    }

    if ($action === 'update') {
        $fullName = isset($data['full_name']) ? trim($data['full_name']) : $row['full_name'];
        $role = isset($data['role']) ? $data['role'] : $row['role'];
        $badge = array_key_exists('badge_number', $data) ? trim((string)$data['badge_number']) : $row['badge_number'];
        $gate = array_key_exists('gate_assigned', $data) ? trim((string)$data['gate_assigned']) : $row['gate_assigned'];

        if ($fullName === '') {
            sendResponse(400, null, 'Full name is required.');
        }
        if (!validRole($role)) {
            sendResponse(400, null, 'Role must be admin or guard.');
        }
        if ($role !== 'admin' && $row['role'] === 'admin') {
            if ($isSelf) sendResponse(400, null, 'You cannot remove your own admin role.');
            if ($isLastAdmin) sendResponse(400, null, 'You cannot demote the last active administrator.');
        }
        $stmt = $pdo->prepare("UPDATE `system_users` SET `full_name` = ?, `role` = ?, `badge_number` = ?, `gate_assigned` = ? WHERE `id` = ?");
        $stmt->execute([$fullName, $role, $badge ?: null, $gate ?: null, $id]);
        sendResponse(200, publicStaff(fetchUser($pdo, $id)), "Account {$row['username']} updated.");
    }

    sendResponse(400, null, 'Unknown action. Use update, set_status or reset_password.');
}
