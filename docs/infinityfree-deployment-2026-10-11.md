# InfinityFree test deployment — 11 October 2026

## Destination and result

- Admin portal: https://ncstparking-test.rf.gd/
- Student portal: https://ncstparking-test.rf.gd/student/
- Mobile API endpoint: https://ncstparking-test.rf.gd/api
- Current admin portal, student portal, and canonical PHP backend deployed successfully.
- Remote database credentials, QR signing key, scanner key, and existing data directory preserved. The remote configuration has debugging disabled and uses MySQL.
- All 114 deployable files checked across the upload attempts. Application code verified byte for byte. The host re-encodes images: JPEG verification checked format, dimensions, and small pixel differences; PNG verification checked identical RGB pixels and at most one alpha level of difference.

## Database preparation

The existing database lacked the payment, operational audit, case, evidence, and visitor-photo schema. A full SQL export was made before applying the existing migrations 007–012. All 16 migration statements completed successfully. The resulting database matched every table and column in the current schema, including the unique movement client reference index. Gate operation defaults to normal mode (Gate 1 entry, Gate 2 exit).

Existing record counts were preserved: 7 vehicles, 9 drivers, 61 gate logs, 7 incidents, 9 violations, 6 visitor passes, 12 visitor items, 7 owner accounts, 2 staff accounts, and 23 session records. No fresh-install schema import was performed.

Backups and machine-readable results are in `artifacts/infinityfree-deployment/` (Git-ignored). The full original file backup is `previous-files-20261011-182418.zip`; later archives contain files captured during resumed upload attempts. The database backup is `database-before-migrations.sql.gz`. Restore this SQL backup into an empty database. Backups contain private application data and must remain private.

## Live verification

Eight HTTPS smoke checks passed: admin page, student page, public settings JSON, authentication-required responses from gate policy/current session/statistics, method rejection from movements, and HTTP denial of direct configuration access.

Both portals loaded in a browser. Empty sign-in submissions produced the expected validation messages, and no browser console errors appeared during these checks.

A live Flutter test used the actual `ApiService.fetchSystemSettings(requireLive: true)` implementation against the deployed HTTPS API. It solved the hosting challenge, retrieved live settings, and confirmed normal gate mode. The test passed after the complete upload. An earlier attempt during the partial upload failed while backend dependencies were still being transferred.

Temporary privileged deployment scripts removed themselves after execution. Temporary result files and the server-side database export were retrieved and removed; final FTP inspection found no leftovers.

## Scope and remaining issues

These are deployment smoke checks, not authenticated end-to-end certification of every feature. No application sign-in credentials were supplied for live operational testing. A native device was not connected, so this deployment does not certify hardware camera or OCR behavior.

The unresolved defects documented in `adversarial-testing-report-2026-10-11.md` remain in this build. The deployment did not implement their fixes.

The mobile app still defaults to the main `securepark.site.je` server. To use this test deployment, choose a custom server URL of `https://ncstparking-test.rf.gd/api` on the mobile sign-in screen. FTP deployment does not install or update an Android APK.
