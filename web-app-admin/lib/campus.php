<?php
/**
 * SecurePark - Shared "who is on campus" helpers
 * Used by overnight_check.php and oncampus.php so both agree on entry times and curfew windows.
 */

require_once __DIR__ . '/qr.php';

/**
 * Curfew timestamp that opened the night containing $now (Asia/Manila).
 */
function currentNightStart($now) {
    $curfewToday = strtotime(date('Y-m-d', $now) . ' ' . SP_CURFEW_TIME . ':00');
    return $now >= $curfewToday ? $curfewToday : strtotime('-1 day', $curfewToday);
}

/**
 * Most recent approved entry for a vehicle: ['logId', 'time' => ts, 'driver', 'gatePoint', 'guard'] or null.
 * Falls back to vehicles.last_entry_time for records without a gate log.
 */
function lastEntryLog($pdo, $vehicle) {
    $stmt = $pdo->prepare("SELECT `id`, `logged_at`, `driver_name`, `verified_driver_name`, `gate_point`, `guard_name`
        FROM `gate_logs`
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? AND `action` = 'Entry Recorded'
        ORDER BY `logged_at` DESC, `id` DESC LIMIT 1");
    $stmt->execute([normalizePlate($vehicle['plate_number'])]);
    $row = $stmt->fetch();
    if ($row && ($ts = strtotime($row['logged_at']))) {
        return [
            'logId' => (int)$row['id'],
            'time' => $ts,
            'driver' => $row['verified_driver_name'] ?: $row['driver_name'],
            'gatePoint' => $row['gate_point'],
            'guard' => $row['guard_name'],
        ];
    }
    if (!empty($vehicle['last_entry_time']) && ($ts = strtotime($vehicle['last_entry_time']))) {
        return ['logId' => null, 'time' => $ts, 'driver' => null, 'gatePoint' => $vehicle['last_gate_point'] ?? null, 'guard' => null];
    }
    return null;
}
