<?php
/**
 * SecurePark - input formats shared by the vehicle forms.
 *
 * Philippine mobile numbers are stored as "+63 927 910 0511" and driver's license numbers as "N01-23-456789"
 * (a letter, then 2, 2 and 6 digits). A value that is already stored on the record is accepted unchanged, so editing an
 * older record never fails because of a number it already had.
 */

/** "09279100511", "+63 927 910 0511", "639279100511" or "9279100511" -> "+63 927 910 0511"; null when it is not a PH mobile number. */
function normalizePhMobile($raw) {
    $s = trim((string)$raw);
    if ($s === '' || preg_match('/[^0-9+()\-.\s]/', $s)) return null;
    $d = preg_replace('/\D/', '', $s);
    if (strlen($d) === 11 && strpos($d, '09') === 0) $d = '63' . substr($d, 1);
    elseif (strlen($d) === 10 && $d[0] === '9') $d = '63' . $d;
    elseif (!(strlen($d) === 12 && strpos($d, '639') === 0)) return null;
    return '+63 ' . substr($d, 2, 3) . ' ' . substr($d, 5, 3) . ' ' . substr($d, 8, 4);
}

/** "n0123456789" or "N01-23-456789" -> "N01-23-456789"; null when it does not have that shape. */
function normalizePhLicense($raw) {
    $c = strtoupper(preg_replace('/[\s\-]/', '', trim((string)$raw)));
    if (!preg_match('/^([A-Z]\d{2})(\d{2})(\d{6})$/', $c, $m)) return null;
    return "{$m[1]}-{$m[2]}-{$m[3]}";
}

/** Empty stays empty; a valid number is returned in the stored format; anything else answers 400. $legacy = values already stored. */
function formatPhoneOrFail($value, $label, array $legacy = []) {
    $v = trim((string)$value);
    if ($v === '') return $v;
    if (in_array($v, array_map(fn($x) => trim((string)$x), $legacy), true)) return $v;
    $n = normalizePhMobile($v);
    if ($n === null) sendResponse(400, ['code' => 'INVALID_PHONE'], "{$label} must be a Philippine mobile number, for example 0927 910 0511.");
    return $n;
}

/** Blank or N/A means no license on file. */
function formatLicenseOrFail($value, $label, array $legacy = []) {
    $v = trim((string)$value);
    if ($v === '' || strcasecmp($v, 'N/A') === 0) return 'N/A';
    if (in_array($v, array_map(fn($x) => trim((string)$x), $legacy), true)) return $v;
    $n = normalizePhLicense($v);
    if ($n === null) sendResponse(400, ['code' => 'INVALID_LICENSE'], "{$label} must look like N01-23-456789 (a letter, then 2, 2 and 6 digits). Leave it blank if there is none.");
    return $n;
}

/** [license, phone] of one authorized driver entry, validated. Phone is null when the entry has none. */
function driverFormatsOrFail(array $drv, array $legacyLicenses = [], array $legacyPhones = []) {
    $name = trim((string)($drv['fullName'] ?? $drv['full_name'] ?? 'driver'));
    $rawLic = $drv['licenseNo'] ?? $drv['license_no'] ?? 'N/A';
    $license = formatLicenseOrFail($rawLic, "License number of {$name}", $legacyLicenses);
    $phone = array_key_exists('phone', $drv) && $drv['phone'] !== null ? formatPhoneOrFail($drv['phone'], "Phone of {$name}", $legacyPhones) : null;
    return [$license, $phone];
}
