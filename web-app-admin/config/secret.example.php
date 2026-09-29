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

// MySQL (InfinityFree control panel > MySQL Databases). There are no built-in database credentials:
// with these missing, the site silently uses a NEW, EMPTY local SQLite file (data/securepark.sqlite).
// That is right for local development; for production all four are required, and
// deploy_to_infinityfree.py refuses to upload a production secret without them.
// define('SP_DB_HOST', 'sqlXXX.infinityfree.com');
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

// How old (hours) an event recorded offline by the mobile app may be when it finally syncs.
// Older events are refused and stay on the phone for review.
define('SP_OFFLINE_MAX_HOURS', 24);

// Session lifetimes (hours)
define('SP_STAFF_TOKEN_HOURS', 12);
define('SP_STUDENT_TOKEN_HOURS', 168);

// Local development only: use the SQLite fallback without trying MySQL first.
// define('SP_FORCE_SQLITE', true);

// Local debugging only: allows ?now=YYYY-MM-DD HH:MM:SS overrides on time-based endpoints. Keep false in production.
define('SP_DEBUG', false);
