<?php
/**
 * SecurePark - Secret Configuration TEMPLATE
 *
 * Copy this file to `secret.php` (same folder) and replace every value.
 * `secret.php` is git-ignored and must never be committed.
 *
 * Generate strong random values with:
 *   php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
 */

// MySQL (InfinityFree control panel > MySQL Databases). Leave SP_DB_PASS out to use the
// local SQLite fallback instead (data/securepark.sqlite on the server).
// define('SP_DB_HOST', 'sql200.infinityfree.com');
// define('SP_DB_NAME', 'if0_XXXXXXXX_securepark');
// define('SP_DB_USER', 'if0_XXXXXXXX');
// define('SP_DB_PASS', 'your-mysql-password');

// HMAC-SHA256 key used to sign and verify QR passes (server-side only)
define('SP_QR_SECRET', 'CHANGE_ME_64_HEX_CHARS');

// Temporary device key for the mobile gate scanner app (sent as X-Api-Key header)
define('SP_SCANNER_API_KEY', 'CHANGE_ME_SCANNER_KEY');

// true (recommended): the scanner endpoints (vehicle lookup, gate log, incident report, verify)
// need either a staff sign-in or the X-Api-Key header. Build the mobile app with the same key:
//   flutter build apk --dart-define=SCANNER_API_KEY=<SP_SCANNER_API_KEY>
// false = anyone on the internet can call those endpoints without signing in. Local testing only.
define('SP_SCANNER_KEY_REQUIRED', true);

// Unsigned (legacy JSON) QR passes are accepted with a warning until this date, then rejected as forged
define('SP_LEGACY_QR_CUTOFF', '2026-12-31');

// Overnight curfew (Asia/Manila, 24h HH:MM) and overtime threshold in hours
define('SP_CURFEW_TIME', '22:00');
define('SP_OVERTIME_HOURS', 12);

// Session lifetimes (hours)
define('SP_STAFF_TOKEN_HOURS', 12);
define('SP_STUDENT_TOKEN_HOURS', 168);

// Local development only: use the SQLite fallback without trying MySQL first.
// define('SP_FORCE_SQLITE', true);

// Local debugging only: allows ?now=YYYY-MM-DD HH:MM:SS overrides on time-based endpoints. Keep false in production.
define('SP_DEBUG', false);
