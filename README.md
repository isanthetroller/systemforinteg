# SecurePark — NCST QR Digital Custody & Exit Verification

Campus vehicle gate system for the National College of Science and Technology (NCST).
Vehicles carry a **signed QR pass**; guards verify the pass and the driver at the gate,
every entry and exit is logged, repeat offenders are banned by a **3-strike policy**, and
visitors get **single-day passes**.

| Part | Folder | Users |
|---|---|---|
| Admin & guard web portal | `web-app-admin/` | Security administrators, gate guards |
| Student / owner web portal | `web-app-student/` | Registered vehicle owners (students & employees) |
| PHP REST API + MySQL | `backend/` (mirrored into `web-app-admin/`) | Both portals and the mobile app |
| Flutter gate scanner (mobile) | `mobile-app/` (see its README) | Gate guards |

---

## Features

**Admin & guard portal** (`web-app-admin/`)
- Sign-in with roles. **Admin**: everything. **Guard**: Gate Monitor, lookups, warnings, visitor passes.
- **Gate Monitor**: Ingress / Egress toggle, camera or USB scanner or typed plate, pass verification,
  mandatory driver confirmation, approve / deny (denials open a security case).
- **Signed QR passes** (HMAC-SHA256, server-side only). Reissuing a pass revokes every older QR.
  Forged / tampered / revoked passes are rejected and flagged automatically.
- **Violations & 3-strike policy**: every warning is a strike; the 3rd strike (or a manual violation)
  bans the vehicle until an admin resolves it with written notes.
- **On Campus Now**: every vehicle currently inside (registered and visitors) with entry time, hours inside,
  who drove in, who admitted it, contact and strike standing; flag a warning / violation or report a visitor
  incident straight from the list.
- **Overtime & overnight detection** after the 22:00 curfew, with an attention panel (call owner, flag strike).
- **Visitor day passes**: valid all day on one date. Guards issue passes for today; an admin can pick a later day
  (up to 60 days ahead) and the QR is refused as "not yet valid" before it. Screenshot-ready card / PNG. Passes can list the
  **items the visitor brings in** (e.g. 40 event chairs); guards must tick them off on entry and exit and the
  item list is written to the gate log.
- **VIP passes** (permanent vehicles, e.g. the school president): an administrator ticks "VIP pass" when registering or
  editing a vehicle. VIP vehicles are exempt from strikes and bans, overnight / overtime checks and the gate's
  driver-confirmation step, and show a gold VIP banner. The pass is still signed and can be revoked, and every passage
  is logged as a VIP passage. The class is stored in the database (not in the QR), with who granted it and when.
- **Offline sync**: when the gate has no connection the mobile app keeps each event with the time it happened and sends it
  to `sync.php` the moment a connection is back (it checks every few seconds and when the app returns to the foreground).
  The log keeps the real event time; rows that arrived late are marked "OFFLINE, synced hh:mm". Every event has a unique
  reference, so a resend never duplicates a log. Entries that already happened are always recorded: if the vehicle turns
  out to be banned, unregistered or on a revoked / expired pass, the log is flagged and a Held incident is opened.
  Events older than 24 hours (`SP_OFFLINE_MAX_HOURS`) are refused and stay on the phone.
  **Visitor passes can be issued offline too**: the phone gives the visitor the QR as usual, and the pass reaches the server
  when the connection returns, with the same pass code and dated the day it was issued (the list shows "ISSUED OFFLINE, synced
  hh:mm"). An offline QR is not server-signed; the server accepts it by its pass code. If the plate turns out to belong to a
  registered vehicle, no pass is created and a Held incident is opened.
- **CCTV simulation widget** (`web-app-admin/assets/cctv_simulation.mp4`, shows "NO SIGNAL" until added).
- **5 second gate clips** (simulation): every entry/exit in the audit log and every vehicle on the On Campus page has a "5s clip" player. Shows "CLIP PLACEHOLDER" until `assets/cctv_clip_placeholder.mp4` (shared) or `assets/cctv_clips/log-<id>.mp4` (per passage) is added; see `web-app-admin/assets/README.txt`.
- **On Campus Now** lists vehicles and visitors in arrival order (first in, first listed), numbered #1, #2, ...
- **Staff Accounts** page; one-time temporary passwords; forced change at first sign-in.

**Student portal** (`web-app-student/`)
- Sign in with student / employee ID. Shows own vehicles, the signed QR pass (full-screen for the gate,
  save as image), authorized drivers, strike standing, warnings / violations and recent gate activity.

All times are **Asia/Manila (PHT, UTC+8)**.

### Mobile: shared IN / OUT scanner

Both guards now use **Scan IN / OUT**. The server reads the vehicle's shared campus status:
Outside suggests Entry; Inside Campus suggests Exit. The guard sees the vehicle, current status,
suggested movement, and authenticated checkpoint, then confirms or cancels. No gate log or status
change is created by scan preparation. The same checkpoint can handle both movements.

`POST api/movements.php` accepts `action: prepare` with `qr_code`, then `action: confirm` with
the returned `ticket`, `driver_id` for ordinary vehicles, and `items_verified` for visitors with
declared items. These operations require a named staff session, not just a scanner device key.
Confirmation rechecks current state and security standing under a database lock. A changed record
requires a fresh scan. Retrying the same ticket returns the original saved transaction without
creating a reverse movement. Tickets expire after five minutes; an already-saved ticket still
returns its saved result on retry. The automatic workflow follows the existing verification
restrictions for security holds, bans, and suspension at both directions.

This confirmed workflow needs an online connection. An interrupted confirmation keeps the same
ticket on screen for retry and is not put into the historical offline-event queue. Existing offline
visitor issuance and historical synchronization remain available.

No new tables or columns are needed. Production must already have migration
`006_offline_sync.sql` (`gate_logs.client_ref` and its unique index). Apply this existing migration
only if it has not already been applied. Existing registrations and QR formats remain unchanged.

Tests: `python tests/movement_integration.py` uses two real PHP workers and a disposable SQLite
database. `--smoke` also runs the existing API suite in a separate disposable database;
`--baseline-smoke` checks the same suite against the original PHP endpoints from Git HEAD.

---

## Folder layout

```
backend/                  <- the ONLY place PHP is edited
  api/                    endpoints (see API reference below)
  lib/                    auth, qr, vehicles, records, strikes, students
  config/                 db.php, secret.example.php, secret.php (git-ignored)
  database/               schema.sql (fresh install), migrations/ 001 to 006 (existing DB)
web-app-admin/            admin & guard portal (+ generated copy of backend/api, lib, config, database)
web-app-student/          student portal (own HTML / CSS / JS, calls ../api)
tests/api_smoke.py        API smoke test (local only)
sync_backend.py           copies backend/ into web-app-admin/
deploy_to_infinityfree.py FTP deploy with safety checks (dry run by default)
```

> **Always edit PHP in `backend/`, then run `python sync_backend.py`.**
> `python sync_backend.py --check` reports whether the copy is out of date.

---

## Run locally

Requirements: PHP 8.1+ (with `pdo_sqlite`), Python 3.10+ (for the scripts).

1. Create the local config (git-ignored):
   ```bash
   cp backend/config/secret.example.php backend/config/secret.php
   ```
   Set random values for `SP_QR_SECRET` and `SP_SCANNER_API_KEY`
   (`php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"`), and for local work also
   `define('SP_DEBUG', true);` and `define('SP_FORCE_SQLITE', true);`. Then `python sync_backend.py`.
2. Start the server from the repo root:
   ```bash
   php -S localhost:8000 -t .
   ```
   (or `DB_DRIVER=sqlite php -S localhost:8000 -t .` without `SP_FORCE_SQLITE`). Data is stored in
   `web-app-admin/data/securepark.sqlite`.
3. Open:
   - Admin / guard portal: http://localhost:8000/web-app-admin/
   - Student portal: http://localhost:8000/web-app-student/
4. First sign-in: **`admin` / `Password123!`** — you must change it immediately. Create guard accounts
   under **Staff Accounts**. Registering a vehicle creates the owner's student login and shows its
   temporary password once.

### Smoke test

```bash
python tests/api_smoke.py --fresh
```
Runs ~170 API checks against the local server (refuses non-localhost URLs). `--fresh` deletes the
local SQLite database first. Requires `SP_DEBUG` (time-travel checks use `?now=`).

---

## Configuration (`backend/config/secret.php`)

| Setting | Purpose |
|---|---|
| `SP_QR_SECRET` | HMAC key that signs every QR pass. **Set once and never change in production** — changing it invalidates every issued pass. |
| `SP_SCANNER_API_KEY` | Device key for the mobile scanner app (`X-Api-Key` header). Build the app with the same value: `flutter build apk --dart-define=SCANNER_API_KEY=<key>` (never commit it). |
| `SP_OFFLINE_MAX_HOURS` | How old (hours) an event the mobile app recorded offline may be when it syncs (default 24). Older events are refused and stay on the phone. |
| `SP_SCANNER_KEY_REQUIRED` | **`true` (the default, keep it)**: the scanner endpoints (plate / QR lookup, verify, gate log, incident, sync) need a staff sign-in or the device key. `false` opens them to anyone on the internet and is for local testing only. |
| `SP_LEGACY_QR_CUTOFF` | Last day old unsigned (pre-v2) passes are accepted with a "reissue" warning. |
| `SP_CURFEW_TIME`, `SP_OVERTIME_HOURS` | Overnight curfew (default `22:00`) and overtime threshold (default 12 h). |
| `SP_STAFF_TOKEN_HOURS`, `SP_STUDENT_TOKEN_HOURS` | Session lifetimes (12 h staff, 7 days students). |
| `SP_DEBUG` | Local only. Shows PHP errors and enables `?now=` time overrides. **Must be `false` in production.** |
| `SP_FORCE_SQLITE` | Local only. Skip MySQL and use the SQLite file. |

---

## Deploy to InfinityFree

Nothing is deployed automatically. Steps, in order:

1. **Back up** the live database (phpMyAdmin → Export).
2. **Migrate the existing database** — phpMyAdmin → SQL → run, in order and **once each**,
   `backend/database/migrations/001_v2.sql`, `002_visitor_items.sql`, `003_system_settings.sql`, then
   `004_vehicle_status_outside.sql`, `005_vip_pass_class.sql`, then `006_offline_sync.sql`. All are non-destructive
   (keep vehicles, drivers, logs, incidents).
   Do **not** run `schema.sql` on the live database: it drops every table (fresh installs only).
3. Create **`backend/config/secret.production.php`** (git-ignored) from `secret.example.php` with
   *new* production keys, `SP_DEBUG = false`, no `SP_FORCE_SQLITE`.
4. Enable **SSL** for the domain in the InfinityFree control panel — the Gate Monitor camera only works
   over HTTPS (USB scanners / typing work either way).
5. Upload the CCTV video to `web-app-admin/assets/cctv_simulation.mp4` (optional, ≤ 10 MB).
6. Dry run, then deploy:
   ```bash
   python deploy_to_infinityfree.py          # lists files, uploads nothing
   python deploy_to_infinityfree.py --yes    # needs FTP_USER and FTP_PASS env vars
   ```
   The script refuses to upload if `web-app-admin/` is out of sync with `backend/`, or if the production
   secret is missing, weak, reuses the local key or has debug on. It uploads the production secret as
   `htdocs/config/secret.php` and never uploads local data, SQL files or the local `secret.php`.
7. Sign in as `admin` / `Password123!`, change the password, create staff accounts.

Server layout: `htdocs/` = admin portal, `htdocs/api/` = API, `htdocs/student/` = student portal.

---

## API reference (`/api`)

All responses: `{ "status": "success"|"error", "success": bool, "message"?: string, "data"?: any }`.
Staff and students authenticate with `Authorization: Bearer <token>` (fallback header `X-Auth-Token`).

| Endpoint | Methods | Who |
|---|---|---|
| `auth.php?action=login` (`&realm=student`) / `logout` / `me` / `change_password` | POST / GET | anyone / signed in |
| `users.php` | GET, POST, PUT | admin |
| `vehicles.php` | GET list: staff (admins also get `qrPayload`) · GET `?plate=` / `?qr=`: staff or scanner · POST / PUT / DELETE: admin | |
| `passes.php` (reissue) | POST | admin |
| `verify.php` | POST `{ qr_code | plate, gate_type }` | staff or scanner |
| `logs.php` | GET: staff · POST `{ plate, action, gate_type, driver_id | visitor_pass_id, items_verified, client_ref? }` (a repeated `client_ref` is ignored) | staff or scanner |
| `sync.php` | POST `{ events: [{ client_ref, type: gate_log \| visitor_exit \| incident, occurred_at, payload }] }` (max 50): the mobile app's offline queue | staff or scanner |
| `incidents.php` | GET: staff · POST: staff or scanner · PUT (resolve): admin | |
| `violations.php` | GET / POST (guards: warnings only) · PUT resolve / dismiss / reset: admin | staff |
| `overnight_check.php` | GET report · POST run / `{ vehicle_id }` flag | staff |
| `oncampus.php` | GET registered vehicles + visitors currently inside | staff |
| `visitors.php` | GET (`?date=` / `?upcoming=1` / `?id=`) / POST `{ ..., items: [{ name, quantity, description }], valid_date? }`: staff (only an admin may set `valid_date` to a later day) · PUT revoke: admin (a visitor still inside gets a Held incident and may still leave) | staff |
| `students.php` | GET / POST issue login | admin |
| `student.php?action=me|vehicles|violations|activity` | GET | student (own data only) |
| `stats.php`, `status.php` | GET | staff / public health check |

Verification results: `VALID`, `LEGACY`, `MANUAL`, `FORGED`, `REVOKED`, `EXPIRED`, `EXPIRED_TEMP`, `NOT_YET_VALID`,
`BANNED`, `SUSPENDED`, `NOT_FOUND`. Entries are refused for banned / suspended / expired passes; exits
are always allowed (with a hold alert) so vehicles are never trapped on campus.

---

## Known limitations & follow-ups

- **Mobile app**: it sends the device key and calls `verify.php` for every scan, and it syncs offline
  events (see Offline sync). It does not know about VIP vehicles or about passes scheduled for a later day yet.
  It cannot be built or tested without the Flutter SDK (run `flutter analyze` and `flutter test` in `mobile-app/`).
- **Rejected offline events**: an event the server refuses for good (for example older than 24 hours) is kept
  in the phone's local "rejected" list; there is no screen to review it yet.
- **No cron on InfinityFree**: the overnight check runs whenever a staff member has the portal open
  (on sign-in and every 10 minutes).
- **Password resets** are done by an admin (Staff Accounts / "Student Login" in the vehicle dossier);
  there is no email-based reset.
- **Existing printed passes** keep working until `SP_LEGACY_QR_CUTOFF`; reissue them from the vehicle dossier.
