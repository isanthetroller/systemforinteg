<?php
/**
 * SecurePark - Periodic maintenance (the free host has no cron)
 *
 * runMaintenance() is triggered by POST /api/maintenance.php, which the staff web app calls on sign-in and every
 * 10 minutes while open. Every step is idempotent (reminders carry a unique key), so repeated runs do nothing new.
 *   1. Pass-expiry notices to owners (once at the warning window, once when it has expired)
 *   2. Reminders while a violation stays unresolved (every N days)
 *   3. Guard shifts left open for 16 hours are closed
 *   4. Guard photos older than the retention setting are deleted
 */

require_once __DIR__ . '/notices.php';
require_once __DIR__ . '/renewals.php';
require_once __DIR__ . '/violations.php';

function runMaintenance($pdo, $force = false) {
    $now = time();
    $last = (int)spSetting($pdo, 'maintenance_last_run', 0);
    if (!$force && $last > 0 && ($now - $last) < 300) {
        return ['skipped' => true, 'lastRun' => date('Y-m-d H:i:s', $last)];
    }
    spSetSetting($pdo, 'maintenance_last_run', $now);

    $out = ['skipped' => false, 'expiryNotices' => 0, 'holdReminders' => 0, 'shiftsClosed' => 0, 'photosPurged' => 0];
    $today = date('Y-m-d', $now);

    // 1. Pass-expiry notices
    try {
        $warnDays = (int)spSetting($pdo, 'expiry_warning_days');
        $cutoff = date('Y-m-d', strtotime("+{$warnDays} days", $now));
        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `is_retired` = 0 AND `pass_valid_until` IS NOT NULL AND `pass_valid_until` <= ? AND `payment_status` <> 'Unpaid' LIMIT 500");
        $stmt->execute([$cutoff]);
        foreach ($stmt->fetchAll() as $v) {
            $info = renewalInfo($pdo, $v, $today);
            $fee = $info['fee'] > 0 ? 'Renewal fee: PHP ' . number_format($info['fee'], 2) . '.' : 'Renewal is free.';
            if ($info['expired']) {
                $id = queueOwnerNotice($pdo, $v, 'Expiry', "Pass expired: {$v['plate_number']}",
                    "The campus pass of your vehicle {$v['plate_number']} expired on {$v['pass_valid_until']}. It cannot enter campus until it is renewed. {$fee}",
                    ['refKey' => "expired:{$v['id']}:{$v['pass_valid_until']}"]);
            } else {
                $id = queueOwnerNotice($pdo, $v, 'Expiry', "Pass expiring: {$v['plate_number']}",
                    "The campus pass of your vehicle {$v['plate_number']} expires on {$v['pass_valid_until']} ({$info['daysLeft']} day(s) left). {$fee}",
                    ['refKey' => "expiry:{$v['id']}:{$v['pass_valid_until']}"]);
            }
            if ($id) $out['expiryNotices']++;
        }
    } catch (Exception $e) {
        error_log('[Maintenance] expiry notices: ' . $e->getMessage());
    }

    // 2. Unresolved violation reminders
    try {
        $every = max(1, (int)spSetting($pdo, 'hold_reminder_days'));
        $stmt = $pdo->prepare("SELECT * FROM `vehicle_violations` WHERE `severity` = 'Violation' AND `status` = 'Pending' AND `created_at` <= ? LIMIT 200");
        $stmt->execute([date('Y-m-d H:i:s', strtotime("-{$every} days", $now))]);
        foreach ($stmt->fetchAll() as $viol) {
            $age = (int)floor(($now - strtotime($viol['created_at'])) / 86400);
            $n = intdiv($age, $every);
            if ($n < 1) continue;
            $stmtV = $pdo->prepare("SELECT * FROM `vehicles` WHERE `id` = ?");
            $stmtV->execute([$viol['vehicle_id']]);
            $v = $stmtV->fetch();
            if (!$v) continue;
            $id = queueOwnerNotice($pdo, $v, 'Reminder', "Reminder: unresolved violation on {$v['plate_number']}",
                "Your vehicle {$v['plate_number']} still has an unresolved violation ({$viol['violation_type']}) recorded on " . date('M j, Y', strtotime($viol['created_at']))
                . " ({$age} days ago). It cannot enter or leave campus until it is resolved.",
                ['refKey' => "holdremind:{$viol['id']}:{$n}", 'violationId' => (int)$viol['id']]);
            if ($id) $out['holdReminders']++;
        }
    } catch (Exception $e) {
        error_log('[Maintenance] hold reminders: ' . $e->getMessage());
    }

    // 3. Stale guard shifts
    try {
        $stmt = $pdo->prepare("UPDATE `guard_shifts` SET `ended_at` = ?, `handover_notes` = '(shift closed automatically after 16 hours)' WHERE `ended_at` IS NULL AND `started_at` < ?");
        $stmt->execute([date('Y-m-d H:i:s', $now), date('Y-m-d H:i:s', strtotime('-16 hours', $now))]);
        $out['shiftsClosed'] = $stmt->rowCount();
    } catch (Exception $e) {
        error_log('[Maintenance] shifts: ' . $e->getMessage());
    }

    // 4. Evidence photo retention
    try {
        $days = (int)spSetting($pdo, 'evidence_retention_days');
        $stmt = $pdo->prepare("UPDATE `evidence_photos` SET `data` = NULL, `purged_at` = ? WHERE `purged_at` IS NULL AND `created_at` < ?");
        $stmt->execute([date('Y-m-d H:i:s', $now), date('Y-m-d H:i:s', strtotime("-{$days} days", $now))]);
        $out['photosPurged'] = $stmt->rowCount();
    } catch (Exception $e) {
        error_log('[Maintenance] evidence: ' . $e->getMessage());
    }

    // 5. E-mails still waiting (entry / exit mails on a host that cannot send after the response)
    try {
        $out['emailsSent'] = spMailConfigured() ? deliverPendingNotices($pdo) : 0;
    } catch (Throwable $e) {
        error_log('[Maintenance] mail: ' . $e->getMessage());
        $out['emailsSent'] = 0;
    }

    return $out;
}
