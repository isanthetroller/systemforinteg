<?php
/**
 * SecurePark - Database Configuration & PDO Handler
 * Configured for InfinityFree Free Hosting with Automatic SQLite Fallback
 */

// Allow CORS for Web Admin and Mobile Application
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Api-Key, Cache-Control, Accept, Origin");

// Respond immediately to preflight OPTIONS requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// -----------------------------------------------------------------------------
// Primary: InfinityFree / Local MySQL Database Configuration
// -----------------------------------------------------------------------------
$db_host = getenv('DB_HOST') ?: 'sql200.infinityfree.com';
$db_name = getenv('DB_NAME') ?: 'if0_42971238_securepark';
$db_user = getenv('DB_USER') ?: 'if0_42971238';
$db_pass = getenv('DB_PASS') !== false ? getenv('DB_PASS') : '';

$pdo = null;
$db_driver = 'mysql';

try {
    $dsn = "mysql:host={$db_host};dbname={$db_name};charset=utf8mb4";
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::ATTR_TIMEOUT            => 3,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci"
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
            `officer` TEXT NOT NULL DEFAULT 'Sgt. R. Mendoza',
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
            `role` TEXT NOT NULL DEFAULT 'Gate Officer',
            `badge_number` TEXT NULL,
            `gate_assigned` TEXT NULL DEFAULT 'Gate 1 (Main Ingress)',
            `status` TEXT NOT NULL DEFAULT 'Active',
            `created_at` TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
    ");
}

/**
 * Standard JSON response helper
 */
function sendResponse($statusCode, $data = null, $message = '') {
    http_response_code($statusCode);
    header("Content-Type: application/json; charset=UTF-8");
    $response = [
        'status' => ($statusCode >= 200 && $statusCode < 300) ? 'success' : 'error'
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
