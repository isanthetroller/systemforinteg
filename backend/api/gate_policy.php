<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/gate_policy.php';
if ($_SERVER['REQUEST_METHOD'] !== 'GET') sendResponse(405, null, 'Method not allowed');
$actor = requireStaff($pdo);
sendResponse(200, gatePolicy($pdo, $actor, $_GET['checkpoint'] ?? null));
