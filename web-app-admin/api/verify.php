<?php
/**
 * SecurePark API - Gate Pass Verification
 *
 * POST /api/verify.php  { qr_code?: string, plate?: string, gate_type?: "Ingress" | "Egress" }
 *
 * Checks pass integrity (HMAC signature), revocation, validity period, bans and
 * suspensions, and returns everything the guard needs to decide. Results:
 *
 *   VALID         Signed pass, all checks passed
 *   LEGACY        Pre-v2 unsigned pass, tolerated until SP_LEGACY_QR_CUTOFF (reissue advised)
 *   MANUAL        Manual plate lookup (no pass presented) - guard must verify identity
 *   FORGED        Bad / missing signature, or legacy pass after the cutoff      -> incident
 *   REVOKED       Pass was reissued or cancelled (old pass id / outdated pass)   -> incident
 *   EXPIRED       Permanent pass past its validity date
 *   EXPIRED_TEMP  Visitor day pass scanned on another date ("EXPIRED TEMPORARY PASS")
 *   BANNED        Vehicle banned by the 3-strike policy / violation
 *   SUSPENDED     Registration suspended by an administrator
 *   NOT_FOUND     No matching vehicle or visitor pass
 *
 * Every rejection decided here is written to the gate log automatically ("autoLogged").
 * Approvals are recorded by the guard through logs.php after confirming the driver.
 */

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/vehicles.php';
require_once __DIR__ . '/../lib/records.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(405, null, 'Method not allowed');
}

$actor = requireStaffOrScanner($pdo);
$data = getJsonInput();
$qrCode = isset($data['qr_code']) ? trim((string)$data['qr_code']) : '';
$plateInput = isset($data['plate']) ? trim((string)$data['plate']) : '';
$gateType = (isset($data['gate_type']) && $data['gate_type'] === 'Egress') ? 'Egress' : 'Ingress';

if ($qrCode === '' && $plateInput === '') {
    sendResponse(400, null, 'Provide a scanned qr_code or a plate to look up.');
}

$now = spNow();
$today = date('Y-m-d', $now);

$result = null;        // one of the result codes above
$passType = null;      // permanent | visitor_temp | legacy | manual
$vehicle = null;       // vehicles row
$visitor = null;       // visitor_passes row
$claimedPlate = '';    // plate claimed by the scanned pass (for logging forged attempts)
$reasonDetail = '';    // human explanation for the result
$warnings = [];

/* --------------------------------------------------------------------------
   1. Identify the pass / vehicle
   -------------------------------------------------------------------------- */
if ($qrCode !== '') {
    $parsed = parseScannedQr($qrCode);

    if ($parsed['kind'] === 'signed') {
        $pass = $parsed['pass'];
        $claimedPlate = $pass['plate_number'];
        $passType = $pass['type'] === 'visitor_temp' ? 'visitor_temp' : 'permanent';

        if (!$parsed['sigValid']) {
            $result = 'FORGED';
            $reasonDetail = 'QR signature is invalid. The pass was altered or not issued by SecurePark.';
            $vehicle = findVehicleByPlate($pdo, $claimedPlate);
        } elseif ($passType === 'visitor_temp') {
            $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `pass_code` = ? LIMIT 1");
            $stmt->execute([$pass['pid']]);
            $visitor = $stmt->fetch() ?: null;
            if (!$visitor) {
                $result = 'REVOKED';
                $reasonDetail = 'Visitor pass no longer exists in the system.';
            }
        } else {
            $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `pass_id` = ? LIMIT 1");
            $stmt->execute([$pass['pid']]);
            $vehicle = $stmt->fetch() ?: null;
            if (!$vehicle) {
                // Genuinely signed by us but no longer the current pass of any vehicle:
                // it was reissued, the plate changed, or the vehicle was removed.
                $vehicle = findVehicleByPlate($pdo, $claimedPlate);
                $result = 'REVOKED';
                $reasonDetail = $vehicle
                    ? 'This pass was replaced by a newer one. Only the latest issued pass is valid.'
                    : 'This pass has been retired (vehicle record changed or removed).';
            } elseif (normalizePlate($vehicle['plate_number']) !== normalizePlate($claimedPlate)) {
                $result = 'REVOKED';
                $reasonDetail = 'Plate on the pass no longer matches the registered vehicle.';
            } elseif ($pass['valid'] < $today) {
                $result = 'EXPIRED';
                $reasonDetail = "Pass expired on {$pass['valid']}.";
            }
        }
    } elseif ($parsed['kind'] === 'legacy') {
        $passType = 'legacy';
        $claimedPlate = $parsed['plate'];
        $vehicle = findVehicleByPlate($pdo, $claimedPlate);
        if (!legacyPassesAllowed($now)) {
            $result = 'FORGED';
            $reasonDetail = 'Unsigned (legacy) passes are no longer accepted since ' . SP_LEGACY_QR_CUTOFF . '.';
        } elseif (!$vehicle) {
            $result = 'NOT_FOUND';
            $reasonDetail = 'No registered vehicle matches this pass.';
        } elseif (!legacyPayloadMatches($parsed['json'], $vehicle['qr_pass_code'])) {
            $result = 'REVOKED';
            $reasonDetail = 'This legacy pass does not match the pass on record (outdated or altered).';
        } else {
            $result = 'LEGACY';
        }
    } else {
        // Plain text: an old pass code, or a plate typed / scanned into the box
        $code = $parsed['code'];
        $stmt = $pdo->prepare("SELECT * FROM `vehicles` WHERE `qr_pass_code` = ? LIMIT 1");
        $stmt->execute([$code]);
        $vehicle = $stmt->fetch() ?: null;
        if ($vehicle) {
            $passType = 'legacy';
            $claimedPlate = $vehicle['plate_number'];
            if (legacyPassesAllowed($now)) {
                $result = 'LEGACY';
            } else {
                $result = 'FORGED';
                $reasonDetail = 'Unsigned (legacy) passes are no longer accepted since ' . SP_LEGACY_QR_CUTOFF . '.';
            }
        } else {
            $plateInput = $code; // fall through to manual lookup
        }
    }
}

if ($result === null && $vehicle === null && $visitor === null && $plateInput !== '') {
    $passType = 'manual';
    $claimedPlate = $plateInput;
    $vehicle = findVehicleByPlate($pdo, $plateInput);
    if (!$vehicle) {
        // A visitor with a day pass for today may be looked up by plate
        // Today's pass, or an older pass whose visitor entered and has not exited yet
        $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `plate_number` = ?
            AND (`valid_date` = ? OR (`entry_time` IS NOT NULL AND `exit_time` IS NULL))
            AND `status` IN ('Active', 'Used') ORDER BY `id` DESC LIMIT 1");
        $stmt->execute([normalizePlate($plateInput), $today]);
        $visitor = $stmt->fetch() ?: null;
    }
    if (!$vehicle && !$visitor) {
        $result = 'NOT_FOUND';
        $reasonDetail = "No registered vehicle or visitor pass found for plate {$plateInput}.";
    } else {
        $result = 'MANUAL';
        $warnings[] = 'Manual lookup: no pass was scanned. Verify the driver\'s identity and photo before approving.';
    }
}

/* --------------------------------------------------------------------------
   2. Visitor pass rules
   -------------------------------------------------------------------------- */
if ($visitor && ($result === null || $result === 'MANUAL')) {
    $passType = $passType === 'manual' ? 'manual' : 'visitor_temp';
    $claimedPlate = $visitor['plate_number'];
    if ($visitor['status'] === 'Revoked') {
        $result = 'REVOKED';
        $reasonDetail = 'This visitor pass was revoked.';
    } elseif ($visitor['status'] === 'Used' || !empty($visitor['exit_time'])) {
        $result = 'REVOKED';
        $reasonDetail = 'This single-day pass has already been used (entry and exit recorded).';
    } elseif ($visitor['valid_date'] !== $today) {
        if ($gateType === 'Ingress' || empty($visitor['entry_time'])) {
            $result = 'EXPIRED_TEMP';
            $reasonDetail = "EXPIRED TEMPORARY PASS - valid only on {$visitor['valid_date']}.";
        } else {
            $result = $result ?? 'VALID';
            $warnings[] = "Visitor pass was valid only on {$visitor['valid_date']}; the vehicle stayed past its pass date.";
        }
    } else {
        $result = $result ?? 'VALID';
    }
}

/* --------------------------------------------------------------------------
   3. Vehicle standing (bans / suspensions) for otherwise acceptable passes
   -------------------------------------------------------------------------- */
if ($vehicle && in_array($result, [null, 'VALID', 'LEGACY', 'MANUAL'], true)) {
    $prior = $result ?? 'VALID';
    if ((int)$vehicle['is_banned'] === 1) {
        $result = 'BANNED';
        $reasonDetail = 'Vehicle is banned under the 3-strike / violation policy until an administrator resolves it.';
    } elseif ($vehicle['registration_status'] === 'Suspended') {
        $result = 'SUSPENDED';
        $reasonDetail = 'Vehicle registration is suspended.';
    } else {
        $result = $prior;
    }
    if ($prior === 'LEGACY') {
        $warnings[] = 'Legacy (unsigned) pass. Accepted until ' . SP_LEGACY_QR_CUTOFF . '; ask the owner to get a new signed pass.';
    }
}

/* --------------------------------------------------------------------------
   4. Decision: which results allow passage for this gate direction
   -------------------------------------------------------------------------- */
$alwaysAccepted = ['VALID', 'LEGACY', 'MANUAL'];
// A vehicle already inside is allowed to leave (with an alert) so it is never trapped on campus
$egressAlsoAccepted = ['BANNED', 'SUSPENDED', 'EXPIRED', 'EXPIRED_TEMP'];
$accepted = in_array($result, $alwaysAccepted, true)
    || ($gateType === 'Egress' && in_array($result, $egressAlsoAccepted, true));

if ($accepted && in_array($result, $egressAlsoAccepted, true)) {
    $warnings[] = 'HOLD ALERT: exit allowed so the vehicle is not trapped, but ' . lcfirst($reasonDetail ?: 'this pass is not valid') . ' Notify an administrator.';
}

$currentlyInside = false;
if ($vehicle) {
    $currentlyInside = $vehicle['status'] === 'Inside Campus';
    if ($accepted && $gateType === 'Ingress' && $currentlyInside) {
        $warnings[] = 'Vehicle is already recorded inside campus (missed exit scan?).';
    }
    if ($accepted && $gateType === 'Egress' && !$currentlyInside) {
        $warnings[] = 'No entry record: this vehicle is not recorded as inside campus.';
    }
    $strikes = (int)$vehicle['warning_count'];
    if ($strikes > 0 && (int)$vehicle['is_banned'] === 0) {
        $warnings[] = "Strike {$strikes} of 3 on record for this vehicle.";
    }
} elseif ($visitor) {
    $currentlyInside = !empty($visitor['entry_time']) && empty($visitor['exit_time']);
}

/* --------------------------------------------------------------------------
   5. Side effects: log every rejection; open incidents for forged / revoked passes
   -------------------------------------------------------------------------- */
$autoLogged = false;
$incident = null;
if (!$accepted && $result !== 'NOT_FOUND') {
    $plateForLog = $vehicle['plate_number'] ?? ($visitor['plate_number'] ?? $claimedPlate);
    $ownerName = $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? null);
    $vehicleType = $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : null);

    if (in_array($result, ['FORGED', 'REVOKED'], true)) {
        $incident = openSecurityIncident($pdo, $actor, [
            'plate' => $plateForLog,
            'vehicleType' => $vehicleType,
            'ownerName' => $ownerName,
            'ownerRole' => $vehicle['owner_role'] ?? ($visitor ? 'Visitor' : null),
            'driverName' => 'Unverified (pass rejected)',
            'driverRelationship' => 'Unknown',
            'reason' => 'Revoked / Forged QR',
            'gatePoint' => defaultGatePoint($gateType),
            'notes' => "{$result}: {$reasonDetail}",
        ], 10);
    }

    recordGateLog($pdo, $actor, [
        'plate' => $plateForLog,
        'vehicleType' => $vehicleType,
        'ownerName' => $ownerName,
        'driverName' => 'Unverified (pass rejected)',
        'driverRelationship' => 'Unknown',
        'action' => $gateType === 'Egress' ? 'Exit Denied' : 'Entry Denied',
        'gateType' => $gateType,
        'status' => $gateType === 'Egress' ? 'Inside Campus' : 'Outside',
        'notes' => $result . ($reasonDetail ? ": {$reasonDetail}" : '') . ($incident ? " [{$incident['caseNumber']}]" : ''),
    ]);
    $autoLogged = true;
}

/* --------------------------------------------------------------------------
   6. Response
   -------------------------------------------------------------------------- */
$messages = [
    'VALID' => 'Pass verified.',
    'LEGACY' => 'Legacy pass accepted (reissue required).',
    'MANUAL' => 'Vehicle found by manual lookup.',
    'FORGED' => 'REVOKED / FORGED QR - access denied.',
    'REVOKED' => 'REVOKED PASS - access denied.',
    'EXPIRED' => 'EXPIRED PASS.',
    'EXPIRED_TEMP' => 'EXPIRED TEMPORARY PASS.',
    'BANNED' => 'VEHICLE BANNED.',
    'SUSPENDED' => 'REGISTRATION SUSPENDED.',
    'NOT_FOUND' => 'No matching vehicle or pass.',
];

$severity = !$accepted ? 'danger' : (empty($warnings) ? 'ok' : 'warning');

sendResponse(200, [
    'result' => $result,
    'accepted' => $accepted,
    'severity' => $severity,
    'message' => $messages[$result] ?? $result,
    'reason' => $reasonDetail,
    'warnings' => array_values(array_unique($warnings)),
    'gateType' => $gateType,
    'passType' => $passType,
    'autoLogged' => $autoLogged,
    'incident' => $incident,
    'currentlyInside' => $currentlyInside,
    'vehicle' => $vehicle ? vehicleForOutput($pdo, $vehicle, false) : null,
    'visitor' => $visitor ? formatVisitorForGate($pdo, $visitor) : null,
    'checkedAt' => date('Y-m-d H:i:s'),
]);

function formatVisitorForGate($pdo, $v) {
    return [
        'id' => (int)$v['id'],
        'passCode' => $v['pass_code'],
        'visitorName' => $v['visitor_name'],
        'contactNumber' => $v['contact_number'],
        'plateNumber' => $v['plate_number'],
        'vehicleModel' => $v['vehicle_model'],
        'purposeOfVisit' => $v['purpose_of_visit'],
        'personToVisit' => $v['person_to_visit'],
        'validDate' => $v['valid_date'],
        'entryTime' => $v['entry_time'],
        'exitTime' => $v['exit_time'],
        'status' => $v['status'],
        'items' => visitorPassItems($pdo, $v['id']),
    ];
}
