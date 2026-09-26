<?php
/**
 * SecurePark API - Authentication Endpoint
 *
 * POST /api/auth.php?action=login            { username, password }           Staff login (admin / guard)
 * POST /api/auth.php?action=login&realm=student { username, password }        Student login (username = student ID)
 * POST /api/auth.php?action=logout                                             Revoke current token
 * GET  /api/auth.php?action=me                                                 Validate token, return profile
 * POST /api/auth.php?action=change_password  { current_password, new_password } Change own password
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';

$method = $_SERVER['REQUEST_METHOD'];
$action = isset($_GET['action']) ? $_GET['action'] : '';

if ($method === 'POST' && $action === 'login') {
    handleLogin($pdo);
} elseif ($method === 'POST' && $action === 'logout') {
    handleLogout($pdo);
} elseif ($method === 'GET' && $action === 'me') {
    handleMe($pdo);
} elseif ($method === 'POST' && $action === 'change_password') {
    handleChangePassword($pdo);
} else {
    sendResponse(400, null, 'Unknown auth action. Use login, logout, me or change_password.');
}

function handleLogin($pdo) {
    $data = getJsonInput();
    $realm = (isset($_GET['realm']) ? $_GET['realm'] : (isset($data['realm']) ? $data['realm'] : 'staff')) === 'student' ? 'student' : 'staff';
    $username = isset($data['username']) ? trim($data['username']) : '';
    $password = isset($data['password']) ? (string)$data['password'] : '';

    if ($username === '' || $password === '') {
        sendResponse(400, null, 'Username and password are required.');
    }

    if ($realm === 'student') {
        $stmt = $pdo->prepare("SELECT * FROM `student_accounts` WHERE `owner_id_number` = ? LIMIT 1");
        $stmt->execute([$username]);
        $row = $stmt->fetch();
        verifyLoginOrFail($pdo, 'student_accounts', $row, $password);
        [$token, $expires] = issueToken($pdo, 'student', (int)$row['id']);
        sendResponse(200, [
            'token' => $token,
            'expiresAt' => $expires,
            'realm' => 'student',
            'student' => publicStudent($row),
        ], 'Signed in successfully.');
    }

    $stmt = $pdo->prepare("SELECT * FROM `system_users` WHERE `username` = ? LIMIT 1");
    $stmt->execute([$username]);
    $row = $stmt->fetch();
    verifyLoginOrFail($pdo, 'system_users', $row, $password);
    [$token, $expires] = issueToken($pdo, 'staff', (int)$row['id']);
    sendResponse(200, [
        'token' => $token,
        'expiresAt' => $expires,
        'realm' => 'staff',
        'user' => publicStaff($row),
    ], 'Signed in successfully.');
}

function handleLogout($pdo) {
    $raw = getBearerToken();
    if ($raw) {
        revokeToken($pdo, $raw);
    }
    sendResponse(200, null, 'Signed out.');
}

function handleMe($pdo) {
    $auth = resolveAuth($pdo);
    if (!$auth) {
        sendResponse(401, ['code' => 'AUTH_REQUIRED'], 'Session expired or invalid. Please sign in again.');
    }
    if ($auth['type'] === 'student') {
        sendResponse(200, ['realm' => 'student', 'student' => publicStudent($auth['user'])]);
    }
    sendResponse(200, ['realm' => 'staff', 'user' => publicStaff($auth['user'])]);
}

function handleChangePassword($pdo) {
    $auth = resolveAuth($pdo);
    if (!$auth) {
        sendResponse(401, ['code' => 'AUTH_REQUIRED'], 'Please sign in to continue.');
    }
    $data = getJsonInput();
    $current = isset($data['current_password']) ? (string)$data['current_password'] : '';
    $new = isset($data['new_password']) ? (string)$data['new_password'] : '';

    if (!password_verify($current, $auth['user']['password_hash'])) {
        sendResponse(400, ['code' => 'WRONG_PASSWORD'], 'Current password is incorrect.');
    }
    if ($current === $new) {
        sendResponse(400, null, 'New password must be different from the current one.');
    }
    $policy = passwordPolicyError($new);
    if ($policy) {
        sendResponse(400, null, $policy);
    }

    $table = $auth['type'] === 'student' ? 'student_accounts' : 'system_users';
    $stmt = $pdo->prepare("UPDATE `{$table}` SET `password_hash` = ?, `must_change_password` = 0 WHERE `id` = ?");
    $stmt->execute([password_hash($new, PASSWORD_BCRYPT), $auth['user']['id']]);

    // Sign out every other session of this account
    revokeUserTokens($pdo, $auth['type'], (int)$auth['user']['id'], $auth['token']);

    sendResponse(200, null, 'Password changed successfully.');
}
