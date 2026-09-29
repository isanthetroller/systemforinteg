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
| Flutter gate scanner (mobile) | `lib/`, `android/`, `ios/` | Gate guards (unchanged in v2) |

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
- **CCTV simulation widget** (`web-app-admin/assets/cctv_simulation.mp4`, shows "NO SIGNAL" until added).
- **Staff Accounts** page; one-time temporary passwords; forced change at first sign-in.

**Student portal** (`web-app-student/`)
- Sign in with student / employee ID. Shows own vehicles, the signed QR pass (full-screen for the gate,
  save as image), authorized drivers, strike standing, warnings / violations and recent gate activity.

All times are **Asia/Manila (PHT, UTC+8)**.

---

## Folder layout

```
backend/                  <- the ONLY place PHP is edited
  api/                    endpoints (see API reference below)
  lib/                    auth, qr, vehicles, records, strikes, students
  config/                 db.php, secret.example.php, secret.php (git-ignored)
  database/               schema.sql (fresh install), migrations/ 001 to 004 (existing DB)
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
| `SP_SCANNER_API_KEY` | Device key for the mobile scanner app (`X-Api-Key` header). |
| `SP_SCANNER_KEY_REQUIRED` | `false` keeps the scanner endpoints (plate / QR lookup, gate log, incident) open to the current mobile app, which does not send the key yet. Set `true` after the app is updated. |
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
   `004_vehicle_status_outside.sql`. All are non-destructive
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
| `logs.php` | GET: staff · POST `{ plate, action, gate_type, driver_id | visitor_pass_id, items_verified }` | staff or scanner |
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

- **Mobile app (not changed in v2)**: still works through the open scanner endpoints. Recommended
  update: send `X-Api-Key`, call `verify.php` instead of decoding the QR itself, then set
  `SP_SCANNER_KEY_REQUIRED = true`.
- **No cron on InfinityFree**: the overnight check runs whenever a staff member has the portal open
  (on sign-in and every 10 minutes).
- **Password resets** are done by an admin (Staff Accounts / "Student Login" in the vehicle dossier);
  there is no email-based reset.
- **Existing printed passes** keep working until `SP_LEGACY_QR_CUTOFF`; reissue them from the vehicle dossier.
