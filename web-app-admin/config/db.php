<?php
/**
 * SecurePark - Database Configuration & PDO Handler
 * Configured for InfinityFree Free Hosting with Automatic SQLite Fallback
 */

// All dates and times operate in Philippine Standard Time (UTC+8)
date_default_timezone_set('Asia/Manila');

// Allow CORS for Web Admin, Student Portal and Mobile Application
// (auth uses bearer tokens in headers, never cookies, so a wildcard origin is safe)
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Auth-Token, X-Requested-With, X-Api-Key, Cache-Control, Accept, Origin");

// Respond immediately to preflight OPTIONS requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// -----------------------------------------------------------------------------
// Secrets (QR signing key, scanner device key, policy settings)
// -----------------------------------------------------------------------------
$secretPath = __DIR__ . '/secret.php';
if (!file_exists($secretPath)) {
    http_response_code(500);
    header("Content-Type: application/json; charset=UTF-8");
    echo json_encode([
        'status' => 'error',
        'success' => false,
        'message' => 'Server not configured: copy config/secret.example.php to config/secret.php and set its values.'
    ]);
    exit;
}
require_once $secretPath;

// Never leak PHP errors (file paths, SQL) to clients outside local debugging
ini_set('display_errors', SP_DEBUG ? '1' : '0');
error_reporting(E_ALL);

// -----------------------------------------------------------------------------
// Primary: InfinityFree / Local MySQL Database Configuration
// -----------------------------------------------------------------------------
// Environment variables win (local tools); otherwise secret.php (InfinityFree has no env vars)
$db_host = getenv('DB_HOST') ?: (defined('SP_DB_HOST') ? SP_DB_HOST : 'sql200.infinityfree.com');
$db_name = getenv('DB_NAME') ?: (defined('SP_DB_NAME') ? SP_DB_NAME : 'if0_42971238_securepark');
$db_user = getenv('DB_USER') ?: (defined('SP_DB_USER') ? SP_DB_USER : 'if0_42971238');
$db_pass = getenv('DB_PASS') !== false ? getenv('DB_PASS') : (defined('SP_DB_PASS') ? SP_DB_PASS : '');

$pdo = null;
$db_driver = 'mysql';

try {
    // Local development: DB_DRIVER=sqlite (env) or SP_FORCE_SQLITE (secret.php) skips MySQL entirely
    if (getenv('DB_DRIVER') === 'sqlite' || (defined('SP_FORCE_SQLITE') && SP_FORCE_SQLITE)) {
        throw new PDOException('MySQL skipped (DB_DRIVER=sqlite)');
    }
    $dsn = "mysql:host={$db_host};dbname={$db_name};charset=utf8mb4";
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::ATTR_TIMEOUT            => 3,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci, time_zone = '+08:00'"
    ];
    $pdo = new PDO($dsn, $db_user, $db_pass, $options);
} catch (PDOException $e) {
    // -------------------------------------------------------------------------
    // Fallback: Resilient Local SQLite Database
    // Automatically takes over when MySQL is unavailable or unconfigured.
    // -------------------------------------------------------------------------
    try {
        $dataDir = dirname(__DIR__) . '/data';
        if (!is_dir($dataDir)) {
            @mkdir($dataDir, 0755, true);
        }

        // Protect data directory from direct web browser access
        $htaccessPath = $dataDir . '/.htaccess';
        if (!file_exists($htaccessPath)) {
            @file_put_contents($htaccessPath, "Order deny,allow\nDeny from all\n");
        }

        $sqlitePath = $dataDir . '/securepark.sqlite';
        $pdo = new PDO("sqlite:" . $sqlitePath);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $db_driver = 'sqlite';

        // Register MySQL compatibility functions for SQLite queries
        $pdo->sqliteCreateFunction('NOW', function() { return date('Y-m-d H:i:s'); });
        $pdo->sqliteCreateFunction('CURDATE', function() { return date('Y-m-d'); });
        $pdo->sqliteCreateFunction('DATE', function($val) { return date('Y-m-d', strtotime($val)); });
        $pdo->sqliteCreateFunction('HOUR', function($val) { return (int)date('G', strtotime($val)); });
        $pdo->sqliteCreateFunction('DATE_FORMAT', function($val, $fmt) {
            if ($val === null || $val === '') return null;
            $map = ['%Y' => 'Y', '%y' => 'y', '%m' => 'm', '%d' => 'd', '%b' => 'M', '%M' => 'F',
                    '%H' => 'H', '%h' => 'h', '%i' => 'i', '%s' => 's', '%p' => 'A', '%e' => 'j'];
            return date(strtr($fmt, $map), strtotime($val));
        }, 2);
        $pdo->exec('PRAGMA foreign_keys = ON');

        // Ensure database tables exist
        initializeSqliteSchema($pdo);
    } catch (Exception $sqliteErr) {
        if (basename($_SERVER['PHP_SELF']) !== 'db.php') {
            http_response_code(500);
            header("Content-Type: application/json; charset=UTF-8");
            echo json_encode([
                'status' => 'error',
                'message' => 'Database initialization failed.',
                'mysql_error' => $e->getMessage(),
                'sqlite_error' => $sqliteErr->getMessage()
            ]);
            exit;
        }
    }
}

/**
 * Initializes tables in SQLite if they don't already exist
 */
function initializeSqliteSchema($pdo) {
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS `vehicles` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `plate_number` TEXT NOT NULL UNIQUE,
            `vehicle_type` TEXT NOT NULL DEFAULT '4-Wheel (Sedan)',
            `category` TEXT NOT NULL DEFAULT 'plated',
            `make_model_color` TEXT NOT NULL,
            `owner_name` TEXT NOT NULL,
            `owner_role` TEXT NOT NULL DEFAULT 'Student',
            `department` TEXT NULL,
            `owner_id_number` TEXT NOT NULL,
            `owner_phone` TEXT NULL,
            `owner_email` TEXT NULL,
            `owner_photo` TEXT NULL,
            `vehicle_photo` TEXT NULL,
            `qr_pass_code` TEXT NULL UNIQUE,
            `status` TEXT NOT NULL DEFAULT 'Outside',
            `registration_status` TEXT NOT NULL DEFAULT 'Active',
            `sticker_year` TEXT NOT NULL DEFAULT '2026',
            `last_entry_time` TEXT NULL,
            `last_gate_point` TEXT NULL,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `authorized_drivers` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `vehicle_id` INTEGER NOT NULL,
            `full_name` TEXT NOT NULL,
            `relationship` TEXT NOT NULL DEFAULT 'Self (Owner)',
            `license_no` TEXT NOT NULL DEFAULT 'N/A',
            `phone` TEXT NULL,
            `photo_url` TEXT NULL,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles`(`id`) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS `gate_logs` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `plate_number` TEXT NOT NULL,
            `vehicle_type` TEXT NULL,
            `owner_name` TEXT NULL,
            `driver_name` TEXT NOT NULL,
            `driver_relationship` TEXT NOT NULL DEFAULT 'Self (Owner)',
            `gate_point` TEXT NOT NULL DEFAULT 'Gate 1 (Main Ingress)',
            `action` TEXT NOT NULL DEFAULT 'Entry Recorded',
            `status` TEXT NOT NULL DEFAULT 'Inside Campus',
            `guard_name` TEXT NOT NULL DEFAULT 'Gate Officer',
            `notes` TEXT NULL,
            `logged_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `security_incidents` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `case_number` TEXT NOT NULL UNIQUE,
            `plate_number` TEXT NOT NULL,
            `vehicle_type` TEXT NULL,
            `owner_name` TEXT NULL,
            `owner_role` TEXT NULL,
            `driver_name` TEXT NOT NULL,
            `driver_relationship` TEXT NULL,
            `reason` TEXT NOT NULL,
            `gate_point` TEXT NOT NULL DEFAULT 'Gate 1 (Main Ingress)',
            `officer` TEXT NOT NULL DEFAULT 'Gate Officer',
            `status` TEXT NOT NULL DEFAULT 'Held',
            `notes` TEXT NULL,
            `reported_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `resolved_at` TEXT NULL
        );

        CREATE TABLE IF NOT EXISTS `system_users` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `username` TEXT NOT NULL UNIQUE,
            `password_hash` TEXT NOT NULL,
            `full_name` TEXT NOT NULL,
            `role` TEXT NOT NULL DEFAULT 'guard',
            `badge_number` TEXT NULL,
            `gate_assigned` TEXT NULL DEFAULT 'Gate 1 (Main Ingress)',
            `status` TEXT NOT NULL DEFAULT 'Active',
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `student_accounts` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `owner_id_number` TEXT NOT NULL UNIQUE,
            `full_name` TEXT NOT NULL,
            `email` TEXT NULL,
            `password_hash` TEXT NOT NULL,
            `must_change_password` INTEGER NOT NULL DEFAULT 1,
            `status` TEXT NOT NULL DEFAULT 'Active',
            `failed_attempts` INTEGER NOT NULL DEFAULT 0,
            `locked_until` TEXT NULL,
            `last_login` TEXT NULL,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `auth_tokens` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `token_hash` TEXT NOT NULL UNIQUE,
            `user_type` TEXT NOT NULL,
            `user_id` INTEGER NOT NULL,
            `expires_at` TEXT NOT NULL,
            `revoked` INTEGER NOT NULL DEFAULT 0,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `vehicle_violations` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `vehicle_id` INTEGER NOT NULL,
            `plate_number` TEXT NOT NULL,
            `violation_type` TEXT NOT NULL,
            `description` TEXT NULL,
            `severity` TEXT NOT NULL DEFAULT 'Warning',
            `logged_by` TEXT NOT NULL,
            `logged_by_user_id` INTEGER NULL,
            `status` TEXT NOT NULL DEFAULT 'Pending',
            `counts_as_strike` INTEGER NOT NULL DEFAULT 0,
            `cleared_by_violation_id` INTEGER NULL,
            `incident_id` INTEGER NULL,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `resolved_at` TEXT NULL,
            `resolved_by` TEXT NULL,
            `resolution_notes` TEXT NULL,
            FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles`(`id`) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS `visitor_passes` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `pass_code` TEXT NOT NULL UNIQUE,
            `visitor_name` TEXT NOT NULL,
            `contact_number` TEXT NOT NULL,
            `plate_number` TEXT NOT NULL,
            `vehicle_model` TEXT NULL,
            `purpose_of_visit` TEXT NOT NULL,
            `person_to_visit` TEXT NOT NULL,
            `valid_date` TEXT NOT NULL,
            `entry_time` TEXT NULL,
            `exit_time` TEXT NULL,
            `status` TEXT NOT NULL DEFAULT 'Active',
            `created_by` TEXT NULL,
            `created_by_user_id` INTEGER NULL,
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS `visitor_pass_items` (
            `id` INTEGER PRIMARY KEY AUTOINCREMENT,
            `visitor_pass_id` INTEGER NOT NULL,
            `item_name` TEXT NOT NULL,
            `quantity` INTEGER NOT NULL DEFAULT 1,
            `description` TEXT NULL,
            FOREIGN KEY (`visitor_pass_id`) REFERENCES `visitor_passes`(`id`) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS `system_settings` (
            `setting_key` TEXT PRIMARY KEY,
            `setting_value` TEXT NOT NULL,
            `description` TEXT NULL,
            `updated_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
    ");

    $pdo->exec("
        INSERT OR IGNORE INTO `system_settings` (`setting_key`, `setting_value`, `description`)
        VALUES ('visitor_pass_validity_hours', '8', 'Validity duration for temporary visitor passes in hours');
    ");

    // Bring older SQLite databases up to the v2 structure
    ensureColumn($pdo, 'system_users', 'last_login', 'TEXT NULL');
    ensureColumn($pdo, 'system_users', 'failed_attempts', 'INTEGER NOT NULL DEFAULT 0');
    ensureColumn($pdo, 'system_users', 'locked_until', 'TEXT NULL');
    ensureColumn($pdo, 'system_users', 'must_change_password', 'INTEGER NOT NULL DEFAULT 0');
    ensureColumn($pdo, 'vehicles', 'warning_count', 'INTEGER NOT NULL DEFAULT 0');
    ensureColumn($pdo, 'vehicles', 'is_banned', 'INTEGER NOT NULL DEFAULT 0');
    ensureColumn($pdo, 'vehicles', 'pass_id', 'TEXT NULL');
    ensureColumn($pdo, 'vehicles', 'pass_valid_until', 'TEXT NULL');
    ensureColumn($pdo, 'gate_logs', 'verified_driver_name', 'TEXT NULL');
    ensureColumn($pdo, 'gate_logs', 'gate_type', "TEXT NOT NULL DEFAULT 'Ingress'");
    ensureColumn($pdo, 'gate_logs', 'logged_by_user_id', 'INTEGER NULL');
    ensureColumn($pdo, 'security_incidents', 'logged_by_user_id', 'INTEGER NULL');

    // Normalize legacy values (mirrors migrations/001_v2.sql)
    $pdo->exec("UPDATE `system_users` SET `role` = 'admin' WHERE `role` NOT IN ('admin', 'guard') AND (LOWER(`role`) LIKE '%admin%')");
    $pdo->exec("UPDATE `system_users` SET `role` = 'guard' WHERE `role` NOT IN ('admin', 'guard')");
    $pdo->exec("UPDATE `gate_logs` SET `action` = 'Entry Denied' WHERE `action` NOT IN ('Entry Recorded', 'Exit Approved', 'Entry Denied', 'Exit Denied')");

    // Clear any previous failed attempts or lockouts, and ensure guards are never locked out by must_change_password
    $pdo->exec("UPDATE `system_users` SET `failed_attempts` = 0, `locked_until` = NULL WHERE `locked_until` IS NOT NULL OR `failed_attempts` > 0");
    $pdo->exec("UPDATE `system_users` SET `must_change_password` = 0 WHERE `role` = 'guard'");
    $pdo->exec("UPDATE `student_accounts` SET `failed_attempts` = 0, `locked_until` = NULL WHERE `locked_until` IS NOT NULL OR `failed_attempts` > 0");

    // Seed baseline administrator and gate guards if empty
    $count = (int)$pdo->query("SELECT COUNT(*) FROM `system_users`")->fetchColumn();
    if ($count === 0) {
        $stmt = $pdo->prepare("INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`) VALUES (?, ?, ?, 'admin', ?, 'All Gates', 'Active', 0)");
        $stmt->execute(['admin', password_hash('Password123!', PASSWORD_BCRYPT), 'System Administrator', 'NCST-SEC-01']);
    }
    // Ensure default guard terminal accounts exist for instant gate operations
    $guardCheck = $pdo->prepare("SELECT `id` FROM `system_users` WHERE `username` = ? LIMIT 1");
    $guardCheck->execute(['guard1']);
    if (!$guardCheck->fetch()) {
        $stmt = $pdo->prepare("INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`) VALUES (?, ?, ?, 'guard', ?, ?, 'Active', 0)");
        $stmt->execute(['guard1', password_hash('password123', PASSWORD_BCRYPT), 'Officer Ramon Gomez', 'NCST-SEC-01', 'Gate 1 (Main Ingress)']);
    }
    $guardCheck->execute(['guard2']);
    if (!$guardCheck->fetch()) {
        $stmt = $pdo->prepare("INSERT INTO `system_users` (`username`, `password_hash`, `full_name`, `role`, `badge_number`, `gate_assigned`, `status`, `must_change_password`) VALUES (?, ?, ?, 'guard', ?, ?, 'Active', 0)");
        $stmt->execute(['guard2', password_hash('password123', PASSWORD_BCRYPT), 'Officer Elena Torres', 'NCST-SEC-02', 'Gate 2 (Main Egress)']);
    }
}

/**
 * Adds a column to a SQLite table if it does not exist yet
 */
function ensureColumn($pdo, $table, $column, $definition) {
    $cols = $pdo->query("PRAGMA table_info(`{$table}`)")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($cols as $c) {
        if ($c['name'] === $column) return;
    }
    $pdo->exec("ALTER TABLE `{$table}` ADD COLUMN `{$column}` {$definition}");
}

/**
 * Current Manila time, overridable with ?now= only when SP_DEBUG is enabled (for testing time rules)
 */
function spNow() {
    if (defined('SP_DEBUG') && SP_DEBUG && !empty($_GET['now'])) {
        $ts = strtotime($_GET['now']);
        if ($ts !== false) return $ts;
    }
    return time();
}

/**
 * Standard JSON response helper
 */
function sendResponse($statusCode, $data = null, $message = '') {
    http_response_code($statusCode);
    header("Content-Type: application/json; charset=UTF-8");
    $ok = ($statusCode >= 200 && $statusCode < 300);
    // `status` is kept for the mobile app; `success` is the v2 response contract
    $response = [
        'status' => $ok ? 'success' : 'error',
        'success' => $ok
    ];
    if ($message !== '') {
        $response['message'] = $message;
    }
    if ($data !== null) {
        $response['data'] = $data;
    }
    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Helper to parse incoming JSON request body
 */
function getJsonInput() {
    $raw = file_get_contents('php://input');
    if (empty($raw)) return [];
    $data = jsonDecodeSafe($raw);
    return is_array($data) ? $data : [];
}

function jsonDecodeSafe($str) {
    $data = json_decode($str, true);
    return (json_last_error() === JSON_ERROR_NONE) ? $data : [];
}
