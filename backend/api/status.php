<?php
/**
 * SecurePark API Health & Diagnostics Check
 */
require_once __DIR__ . '/../config/db.php';

$dbConnected = false;
$tablesFound = [];
$errorMsg = null;
$activeDriver = $db_driver ?? 'unknown';

if (isset($pdo) && $pdo !== null) {
    try {
        if ($activeDriver === 'sqlite') {
            $stmt = $pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
        } else {
            $stmt = $pdo->query("SHOW TABLES");
        }
        $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
        $dbConnected = true;
        $tablesFound = $tables;
    } catch (Exception $e) {
        $errorMsg = $e->getMessage();
    }
}

sendResponse(200, [
    'system' => 'SecurePark - Campus Gate & Custody Administration',
    'version' => '2.4.0',
    'status' => 'operational',
    'php_version' => phpversion(),
    'database' => [
        'connected' => $dbConnected,
        'driver' => $activeDriver,
        'tables_count' => count($tablesFound),
        'tables' => SP_DEBUG ? $tablesFound : null,
        // Connection details are only exposed while debugging locally
        'configured_host' => SP_DEBUG ? ($db_host ?? 'unknown') : null,
        'configured_db' => SP_DEBUG ? ($db_name ?? 'unknown') : null,
        'error' => SP_DEBUG ? $errorMsg : ($errorMsg ? 'Database query failed' : null)
    ],
    // How this request reached PHP. Open /api/status.php over https:// to confirm HTTPS works on the live host.
    'transport' => [
        'secure' => isSecureRequest(),
        'scheme' => isSecureRequest() ? 'https' : 'http',
        'https_var' => $_SERVER['HTTPS'] ?? null,
        'forwarded_proto' => $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? null,
        'port' => $_SERVER['SERVER_PORT'] ?? null,
        'hsts_sent' => isSecureRequest(),
    ],
    'server_time' => date('Y-m-d H:i:s')
], 'API status operational');
