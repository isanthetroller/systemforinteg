<?php
/**
 * SecurePark - Student / vehicle-owner portal accounts
 *
 * One account per owner ID number (student or employee ID), shared by all of that
 * owner's vehicles. Accounts are created by the security office when a vehicle is
 * registered; the temporary password is shown to the admin once and must be changed
 * at first sign-in.
 */

require_once __DIR__ . '/auth.php';

function findStudentAccount($pdo, $ownerIdNumber) {
    $stmt = $pdo->prepare("SELECT * FROM `student_accounts` WHERE `owner_id_number` = ? LIMIT 1");
    $stmt->execute([trim((string)$ownerIdNumber)]);
    return $stmt->fetch() ?: null;
}

/**
 * Creates the portal account for an owner if it does not exist yet.
 * Returns ['ownerIdNumber', 'created' => bool, 'tempPassword' => string|null].
 */
function ensureStudentAccount($pdo, $ownerIdNumber, $fullName, $email = null) {
    $ownerIdNumber = trim((string)$ownerIdNumber);
    if ($ownerIdNumber === '') return null;
    if (findStudentAccount($pdo, $ownerIdNumber)) {
        return ['ownerIdNumber' => $ownerIdNumber, 'created' => false, 'tempPassword' => null];
    }
    $temp = generateTempPassword();
    $stmt = $pdo->prepare("INSERT INTO `student_accounts`
        (`owner_id_number`, `full_name`, `email`, `password_hash`, `must_change_password`, `status`, `created_at`)
        VALUES (?, ?, ?, ?, 1, 'Active', ?)");
    $stmt->execute([$ownerIdNumber, $fullName, $email ?: null, password_hash($temp, PASSWORD_BCRYPT), date('Y-m-d H:i:s')]);
    return ['ownerIdNumber' => $ownerIdNumber, 'created' => true, 'tempPassword' => $temp];
}

/**
 * Issues a new temporary password (creating the account if needed) and signs the
 * student out everywhere.
 */
function resetStudentPassword($pdo, $ownerIdNumber, $fullName, $email = null) {
    $account = findStudentAccount($pdo, $ownerIdNumber);
    if (!$account) {
        return ensureStudentAccount($pdo, $ownerIdNumber, $fullName, $email);
    }
    $temp = generateTempPassword();
    $pdo->prepare("UPDATE `student_accounts` SET `password_hash` = ?, `must_change_password` = 1,
        `failed_attempts` = 0, `locked_until` = NULL, `status` = 'Active', `full_name` = ? WHERE `id` = ?")
        ->execute([password_hash($temp, PASSWORD_BCRYPT), $fullName ?: $account['full_name'], $account['id']]);
    revokeUserTokens($pdo, 'student', (int)$account['id']);
    return ['ownerIdNumber' => $account['owner_id_number'], 'created' => false, 'tempPassword' => $temp];
}
