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
 *   EXPIRED_TEMP  Visitor day pass scanned after its date ("EXPIRED TEMPORARY PASS")
 *   NOT_YET_VALID Visitor day pass scheduled for a later date
 *   BANNED        Vehicle on hold: unresolved violation (cannot enter or leave until an administrator resolves it)
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
require_once __DIR__ . '/../lib/campus.php';

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
$incident = null;

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
        if (!$vehicle) {
            $passId = $parsed['json']['passId'] ?? $parsed['json']['pass_code'] ?? '';
            $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE (`pass_code` = ? OR `plate_number` = ? OR REPLACE(REPLACE(`plate_number`, '-', ''), ' ', '') = ?) ORDER BY `id` DESC LIMIT 1");
            $stmt->execute([$passId, $claimedPlate, normalizePlate($claimedPlate)]);
            $visitor = $stmt->fetch() ?: null;
            if ($visitor) {
                $passType = 'visitor_temp';
            }
        }
        if (!$vehicle && !$visitor) {
            $result = 'NOT_FOUND';
            $reasonDetail = 'No registered vehicle or visitor pass matches this QR code.';
        } elseif ($vehicle) {
            if (!legacyPassesAllowed($now)) {
                $result = 'FORGED';
                $reasonDetail = 'Unsigned (legacy) passes are no longer accepted since ' . SP_LEGACY_QR_CUTOFF . '.';
            } elseif (!legacyPayloadMatches($parsed['json'], $vehicle['qr_pass_code'])) {
                if (legacyOwnerMatches($parsed['json'], $vehicle['owner_id_number'])) {
                    // Same owner, but the sticker is out of date: the server's record wins
                    $result = 'LEGACY';
                    $reasonDetail = 'Old pass accepted for the registered owner.';
                    $warnings[] = 'The details printed on this old pass are out of date. Check the driver against the roster shown here.';
                } else {
                    $result = 'REVOKED';
                    $reasonDetail = 'This legacy pass does not identify the registered owner (altered or not issued by the office).';
                }
            } else {
                $result = 'LEGACY';
            }
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
            $stmt = $pdo->prepare("SELECT * FROM `visitor_passes` WHERE `pass_code` = ? LIMIT 1");
            $stmt->execute([$code]);
            $visitor = $stmt->fetch() ?: null;
            if ($visitor) {
                $passType = 'visitor_temp';
                $claimedPlate = $visitor['plate_number'];
            } else {
                $plateInput = $code; // fall through to manual lookup
            }
        }
    }
}

if ($result === null && $vehicle === null && $visitor === null && $plateInput !== '') {
    $passType = 'manual';
    $claimedPlate = $plateInput;
    $vehicle = findVehicleByPlate($pdo, $plateInput);
    if (!$vehicle) {
        // Today's pass, a pass whose visitor is still inside, or an upcoming pass (reported as "not yet valid")
        $visitor = findVisitorPassByPlate($pdo, $plateInput, $today);
    }
    if (!$vehicle && !$visitor) {
        $result = 'NOT_FOUND';
        $reasonDetail = "No registered vehicle or visitor pass found for plate {$plateInput}.";
    } else {
        $result = 'MANUAL';
    }
}

/* --------------------------------------------------------------------------
   2. Visitor pass rules & security incident holds
   -------------------------------------------------------------------------- */
$revokedInside = $visitor && $visitor['status'] === 'Revoked'
    && !empty($visitor['entry_time']) && empty($visitor['exit_time']);

if ($visitor && ($result === null || $result === 'MANUAL')) {
    $passType = $passType === 'manual' ? 'manual' : 'visitor_temp';
    $claimedPlate = $visitor['plate_number'];

    // Check for active security incident hold on this visitor
    $normPlate = normalizePlate($visitor['plate_number']);
    $passCode = $visitor['pass_code'] ?? '';
    $visIncStmt = $pdo->prepare("SELECT `id`, `case_number`, `reason`, `notes` FROM `security_incidents` 
        WHERE (REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? OR `reason` LIKE ? OR `notes` LIKE ?)
          AND `status` = 'Held' 
        ORDER BY `id` DESC LIMIT 1");
    $visIncStmt->execute([$normPlate, "%{$passCode}%", "%{$passCode}%"]);
    $activeVisitorIncident = $visIncStmt->fetch();

    if ($activeVisitorIncident) {
        $result = 'REVOKED';
        $reasonDetail = "Security Incident Hold [Case #{$activeVisitorIncident['case_number']}]: {$activeVisitorIncident['reason']}. The visitor cannot proceed until cleared by administration.";
        $incident = [
            'id' => (int)$activeVisitorIncident['id'],
            'caseNumber' => $activeVisitorIncident['case_number'],
            'reason' => $activeVisitorIncident['reason'],
            'status' => 'Held',
        ];
    } elseif ($visitor['status'] === 'Revoked') {
        $result = 'REVOKED';
        $reasonDetail = $revokedInside
            ? 'This visitor pass was revoked while the visitor was on campus.'
            : (!empty($visitor['exit_time'])
                ? 'This single-day pass has already been used (entry and exit recorded) and was revoked when the visitor exited.'
                : 'This visitor pass was revoked.');
    } elseif ($visitor['status'] === 'Used' || !empty($visitor['exit_time'])) {
        $result = 'REVOKED';
        $reasonDetail = 'This single-day pass has already been used (entry and exit recorded).';
    } elseif ($visitor['valid_date'] > $today) {
        $result = 'NOT_YET_VALID';
        $reasonDetail = "This day pass becomes active on {$visitor['valid_date']}.";
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
   3. Vehicle standing (bans / suspensions / security holds)
   -------------------------------------------------------------------------- */
$activeVehIncident = null;
if ($vehicle) {
    $normPlate = normalizePlate($vehicle['plate_number']);
    $vehIncStmt = $pdo->prepare("SELECT `id`, `case_number`, `reason`, `notes` FROM `security_incidents` 
        WHERE REPLACE(REPLACE(UPPER(`plate_number`), '-', ''), ' ', '') = ? 
          AND `status` = 'Held' 
        ORDER BY `id` DESC LIMIT 1");
    $vehIncStmt->execute([$normPlate]);
    $activeVehIncident = $vehIncStmt->fetch();
}

if ($vehicle && in_array($result, [null, 'VALID', 'LEGACY', 'MANUAL'], true)) {
    $prior = $result ?? 'VALID';
    if ($activeVehIncident || $vehicle['status'] === 'Blocked / Alert') {
        $caseNum = $activeVehIncident ? $activeVehIncident['case_number'] : 'HOLD';
        $holdReason = $activeVehIncident ? $activeVehIncident['reason'] : 'Security hold on vehicle';
        $result = 'BANNED';
        $reasonDetail = (int)$vehicle['is_banned'] === 1
            ? "Violation hold [Case #{$caseNum}]: {$holdReason}. The vehicle cannot enter or leave campus until an administrator resolves the violation."
            : "Security Incident Hold [Case #{$caseNum}]: {$holdReason}. The vehicle cannot proceed until cleared by administration.";
        if ($activeVehIncident) {
            $incident = [
                'id' => (int)$activeVehIncident['id'],
                'caseNumber' => $activeVehIncident['case_number'],
                'reason' => $activeVehIncident['reason'],
                'status' => 'Held',
            ];
        }
    } elseif ((int)$vehicle['is_banned'] === 1) {
        $result = 'BANNED';
        $reasonDetail = 'This vehicle has an unresolved violation. It cannot enter or leave campus until the violation is resolved at the Security Office.';
    } elseif ($vehicle['registration_status'] === 'Suspended') {
        $result = 'SUSPENDED';
        $reasonDetail = 'Vehicle registration is suspended.';
    } elseif ($gateType !== 'Egress' && vehiclePassExpired($vehicle, $today)) {
        // The pass date is checked for every lookup, not only for scanned signed QR codes
        $result = 'EXPIRED';
        $reasonDetail = "Pass expired on {$vehicle['pass_valid_until']}. Renew it at the Security Office.";
    } elseif (($vehicle['payment_status'] ?? 'Paid') === 'Unpaid' && $gateType !== 'Egress') {
        // Entry needs a paid registration; a vehicle already inside is never trapped by this
        $result = 'UNPAID';
        $reasonDetail = 'Registration fee not paid. The owner must pay online (student portal) or at the cashier before this vehicle can enter.';
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
$accepted = in_array($result, $alwaysAccepted, true);

$hasSecurityHold = ($incident !== null && !empty($incident))
    || (!empty($activeVisitorIncident))
    || (!empty($activeVehIncident))
    || ($vehicle && $vehicle['status'] === 'Blocked / Alert')
    || ($vehicle && (int)$vehicle['is_banned'] === 1)
    || ($vehicle && $vehicle['registration_status'] === 'Suspended')
    || ($visitor && $visitor['status'] === 'Revoked');

// Security holds, bans, suspensions, and revoked passes strictly PREVENT passage at both Ingress and Egress
if ($hasSecurityHold) {
    $accepted = false;
} elseif ($gateType === 'Egress' && $result === 'EXPIRED_TEMP' && !empty($visitor['entry_time'])) {
    // A visitor whose pass expired while on campus with no security holds can leave with an alert
    $accepted = true;
    $warnings[] = "Visitor stayed past pass date ({$visitor['valid_date']}).";
}

if ($result === 'MANUAL') {
    $warnings[] = 'Manual lookup: no pass was scanned. Verify the driver\'s identity and photo before approving.';
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
} elseif ($visitor) {
    $currentlyInside = !empty($visitor['entry_time']) && empty($visitor['exit_time']);
}

/* --------------------------------------------------------------------------
   5. Side effects: log every rejection; open incidents for forged / revoked passes
   -------------------------------------------------------------------------- */
$autoLogged = false;
if (!$accepted && $result !== 'NOT_FOUND') {
    $plateForLog = $vehicle['plate_number'] ?? ($visitor['plate_number'] ?? $claimedPlate);
    $ownerName = $vehicle['owner_name'] ?? ($visitor['visitor_name'] ?? null);
    $vehicleType = $vehicle['vehicle_type'] ?? ($visitor ? 'Visitor Vehicle' : null);

    if (in_array($result, ['FORGED', 'REVOKED'], true) && $incident === null) {
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
            'notifyOwner' => true,
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
    'NOT_YET_VALID' => 'PASS NOT YET VALID.',
    'BANNED' => 'VIOLATION HOLD - unresolved violation.',
    'SUSPENDED' => 'REGISTRATION SUSPENDED.',
    'UNPAID' => 'REGISTRATION FEE UNPAID.',
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
    // Where it is and who to call: shown to the guard when a vehicle that is already inside is scanned again
    'onCampus' => ($vehicle && $currentlyInside) ? onCampusDetails($pdo, $vehicle, $now) : null,
    'vehicle' => $vehicle ? vehicleForOutput($pdo, $vehicle, false) : null,
    'visitor' => $visitor ? formatVisitorForGate($pdo, $visitor) : null,
    'checkedAt' => date('Y-m-d H:i:s'),
]);

function onCampusDetails($pdo, $vehicle, $now) {
    $entry = lastEntryLog($pdo, $vehicle);
    return [
        'entryTime' => $entry ? date('Y-m-d H:i:s', $entry['time']) : null,
        'hoursInside' => $entry ? round(max(0, ($now - $entry['time']) / 3600), 1) : null,
        'gatePoint' => $entry['gatePoint'] ?? null,
        'enteredBy' => $entry['driver'] ?? null,
        'admittedBy' => $entry['guard'] ?? null,
        'ownerPhone' => $vehicle['owner_phone'] ?: null,
    ];
}

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
