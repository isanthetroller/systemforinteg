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
        'tables' => $tablesFound,
        'configured_host' => $db_host ?? 'unknown',
        'configured_db' => $db_name ?? 'unknown',
        'error' => $errorMsg
    ],
    'server_time' => date('Y-m-d H:i:s')
], 'API status operational');
