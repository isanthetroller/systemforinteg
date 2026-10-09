<?php
/**
 * SecurePark API - Periodic maintenance trigger
 *
 * POST /api/maintenance.php            Runs the periodic jobs if the last run was 5+ minutes ago (staff)
 * POST /api/maintenance.php?force=1    Runs them now (admin)
 * See lib/maintenance.php for what runs. Safe to call as often as you like.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/maintenance.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(405, null, 'Method not allowed');
}

$force = !empty($_GET['force']);
$actor = requireStaff($pdo, $force ? ['admin'] : ['admin', 'guard']);
$result = runMaintenance($pdo, $force);
sendResponse(200, $result, $result['skipped'] ? 'Nothing to do yet.' : 'Maintenance done.');
