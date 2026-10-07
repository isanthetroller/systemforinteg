<?php
/**
 * SecurePark - Parking capacity and occupancy
 *
 * The capacity is an admin setting (`parking_capacity`, 0 = not limited). The campus is "nearly full" from 90% and
 * "full" at 100%. Entry is NOT refused automatically (a guard may still admit an emergency or VIP vehicle); the
 * gate scan, the dashboard and the mobile app only warn.
 */

require_once __DIR__ . '/settings.php';

const SP_CAPACITY_WARN_PERCENT = 90;

/** Vehicles and visitors currently recorded inside campus: ['vehicles' => n, 'visitors' => n, 'total' => n]. */
function campusInsideCounts($pdo) {
    $vehicles = (int)$pdo->query("
        SELECT COUNT(*) AS cnt FROM `vehicles`
        WHERE `status` = 'Inside Campus'
           OR (`status` = 'Blocked / Alert' AND `last_entry_time` IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM `gate_logs`
               WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = REPLACE(REPLACE(UPPER(`vehicles`.`plate_number`), '-', ''), ' ', '')
                 AND `action` = 'Exit Approved'
                 AND `logged_at` >= `vehicles`.`last_entry_time`
           ))
    ")->fetch()['cnt'];
    $visitors = (int)$pdo->query("
        SELECT COUNT(*) AS cnt FROM `visitor_passes`
        WHERE `entry_time` IS NOT NULL AND `exit_time` IS NULL AND `status` IN ('Active', 'Revoked')
    ")->fetch()['cnt'];
    return ['vehicles' => $vehicles, 'visitors' => $visitors, 'total' => $vehicles + $visitors];
}

/**
 * ['inside' => n, 'capacity' => n, 'available' => n|null, 'percent' => n|null,
 *  'level' => 'unlimited'|'ok'|'nearly_full'|'full', 'message' => string|null]
 */
function campusOccupancy($pdo) {
    $counts = campusInsideCounts($pdo);
    $capacity = (int)spSetting($pdo, 'parking_capacity');
    $out = ['inside' => $counts['total'], 'insideVehicles' => $counts['vehicles'], 'insideVisitors' => $counts['visitors'],
        'capacity' => $capacity, 'available' => null, 'percent' => null, 'level' => 'unlimited', 'message' => null];
    if ($capacity <= 0) return $out;

    $out['available'] = max(0, $capacity - $counts['total']);
    $out['percent'] = (int)round($counts['total'] * 100 / $capacity);
    if ($counts['total'] >= $capacity) {
        $out['level'] = 'full';
        $out['message'] = "Campus parking is FULL ({$counts['total']} of {$capacity}).";
    } elseif ($out['percent'] >= SP_CAPACITY_WARN_PERCENT) {
        $out['level'] = 'nearly_full';
        $out['message'] = "Campus parking is nearly full ({$counts['total']} of {$capacity}, {$out['available']} space(s) left).";
    } else {
        $out['level'] = 'ok';
    }
    return $out;
}
