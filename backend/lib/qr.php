<?php
/**
 * SecurePark - QR Pass Signing & Verification (server-side only)
 *
 * Signed pass payload (compact JSON, no photos or personal data):
 *   {"v":1,"pid":"SP-7Q2K9XH4TD","plate_number":"NDK4821","type":"permanent","valid":"2026-12-31","sig":"..."}
 *
 * sig = base64url( first 16 bytes of HMAC-SHA256( "v|pid|plate_number|type|valid", SP_QR_SECRET ) )
 *
 * The secret never leaves the server. Clients only render payloads the server produced.
 */

const SP_QR_VERSION = 1;
const SP_PASS_TYPES = ['permanent', 'visitor_temp'];

function base64UrlEncode($bin) {
    return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
}

function normalizePlate($plate) {
    return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)$plate));
}

function qrCanonicalString($pid, $plate, $type, $valid) {
    return implode('|', [SP_QR_VERSION, $pid, normalizePlate($plate), $type, $valid]);
}

function qrSignature($pid, $plate, $type, $valid) {
    $mac = hash_hmac('sha256', qrCanonicalString($pid, $plate, $type, $valid), SP_QR_SECRET, true);
    return base64UrlEncode(substr($mac, 0, 16));
}

/**
 * Builds the signed payload string to encode into a QR code.
 */
function signPassPayload($pid, $plate, $type, $valid) {
    if (!in_array($type, SP_PASS_TYPES, true)) {
        throw new InvalidArgumentException("Unknown pass type {$type}");
    }
    if (!defined('SP_QR_SECRET') || strlen(SP_QR_SECRET) < 32 || strpos(SP_QR_SECRET, 'CHANGE_ME') !== false) {
        throw new RuntimeException('SP_QR_SECRET is not configured. Set a strong random value in config/secret.php.');
    }
    return json_encode([
        'v' => SP_QR_VERSION,
        'pid' => $pid,
        'plate_number' => normalizePlate($plate),
        'type' => $type,
        'valid' => $valid,
        'sig' => qrSignature($pid, $plate, $type, $valid),
    ], JSON_UNESCAPED_SLASHES);
}

/**
 * Classifies a raw scanned string.
 *
 * Returns one of:
 *   ['kind' => 'signed',  'pass' => [...], 'sigValid' => bool]
 *   ['kind' => 'legacy',  'plate' => 'ABC1234', 'raw' => '...']   (old v1 JSON pass, no signature)
 *   ['kind' => 'code',    'code' => '...']                           (plain text: old pass code or typed plate)
 */
function parseScannedQr($raw) {
    $raw = trim((string)$raw);
    $decoded = (strlen($raw) > 1 && $raw[0] === '{') ? json_decode($raw, true) : null;

    if (is_array($decoded)) {
        // Anything that claims to be a signed pass is judged strictly as one
        if (array_key_exists('sig', $decoded) || array_key_exists('pid', $decoded)) {
            $pass = [
                'v' => $decoded['v'] ?? null,
                'pid' => is_string($decoded['pid'] ?? null) ? $decoded['pid'] : '',
                'plate_number' => is_string($decoded['plate_number'] ?? null) ? $decoded['plate_number'] : '',
                'type' => is_string($decoded['type'] ?? null) ? $decoded['type'] : '',
                'valid' => is_string($decoded['valid'] ?? null) ? $decoded['valid'] : '',
                'sig' => is_string($decoded['sig'] ?? null) ? $decoded['sig'] : '',
            ];
            $wellFormed = (int)$pass['v'] === SP_QR_VERSION
                && $pass['pid'] !== '' && $pass['plate_number'] !== '' && $pass['sig'] !== ''
                && in_array($pass['type'], SP_PASS_TYPES, true)
                && preg_match('/^\d{4}-\d{2}-\d{2}$/', $pass['valid']);
            $sigValid = $wellFormed && hash_equals(
                qrSignature($pass['pid'], $pass['plate_number'], $pass['type'], $pass['valid']),
                $pass['sig']
            );
            return ['kind' => 'signed', 'pass' => $pass, 'sigValid' => $sigValid];
        }

        $plate = $decoded['plateNumber'] ?? $decoded['plate_number'] ?? $decoded['plate'] ?? '';
        return ['kind' => 'legacy', 'plate' => is_string($plate) ? $plate : '', 'raw' => $raw, 'json' => $decoded];
    }

    return ['kind' => 'code', 'code' => $raw];
}

/**
 * Legacy (unsigned) passes are tolerated until SP_LEGACY_QR_CUTOFF (inclusive).
 */
function legacyPassesAllowed($now = null) {
    $today = date('Y-m-d', $now ?? time());
    return defined('SP_LEGACY_QR_CUTOFF') && $today <= SP_LEGACY_QR_CUTOFF;
}

/**
 * A legacy JSON pass is only accepted when it is the exact pass the office printed,
 * i.e. it matches the payload stored in vehicles.qr_pass_code (compared structurally).
 */
function legacyPayloadMatches($scannedJson, $storedPayload) {
    if (!is_string($storedPayload) || $storedPayload === '' || $storedPayload[0] !== '{') return false;
    $stored = json_decode($storedPayload, true);
    if (!is_array($stored) || !is_array($scannedJson)) return false;
    return canonicalJson($stored) === canonicalJson($scannedJson);
}

/**
 * A legacy pass is only trusted when it names the vehicle's registered owner ID. Printed stickers
 * go stale (renamed owner, new model, changed driver list) so the rest of the payload is ignored
 * and the server's record wins; but JSON that merely names a plate is not a pass.
 */
function legacyOwnerMatches($scannedJson, $ownerIdNumber) {
    if (!is_array($scannedJson)) return false;
    $claimed = $scannedJson['ownerStudentId'] ?? $scannedJson['owner_id_number'] ?? $scannedJson['ownerIdNumber'] ?? '';
    $claimed = is_string($claimed) ? strtoupper(trim($claimed)) : '';
    $actual = strtoupper(trim((string)$ownerIdNumber));
    return $claimed !== '' && $actual !== '' && hash_equals($actual, $claimed);
}

function canonicalJson($value) {
    if (is_array($value)) {
        $isList = array_keys($value) === range(0, count($value) - 1);
        if (!$isList) ksort($value);
        foreach ($value as $k => $v) $value[$k] = canonicalJson($v);
    }
    return $value;
}

function newPassId() {
    // 10 chars from an unambiguous alphabet, e.g. SP-7Q2K9XH4TD
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $id = '';
    for ($i = 0; $i < 10; $i++) {
        $id .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
    return 'SP-' . $id;
}

/**
 * Default validity of a permanent pass: end of its sticker year.
 */
function defaultPassValidUntil($stickerYear) {
    $year = preg_match('/^\d{4}$/', (string)$stickerYear) ? $stickerYear : date('Y');
    return "{$year}-12-31";
}
