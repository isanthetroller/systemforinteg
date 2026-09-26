# SecurePark — Admin & Guard Portal

The web portal for NCST campus security. Setup, deployment and the API reference are in the
[main README](../README.md).

> The `api/`, `lib/`, `config/` and `database/` folders here are **generated** from `../backend/`
> by `python sync_backend.py`. Do not edit them directly.

## Pages

| Page | Admin | Guard |
|---|:---:|:---:|
| Gate Monitor — scan / look up, Ingress / Egress, confirm driver, approve or deny | ✓ | ✓ (landing page) |
| On Campus Now — everything inside, flag / report from the list | ✓ | ✓ |
| Dashboard — KPIs, CCTV, overtime & overnight panel, held cases | ✓ | ✓ |
| Vehicle Directory — dossiers, signed passes, reissue, student login | ✓ | view |
| Register Vehicle | ✓ | — |
| Visitor Day Passes — issue (with items brought in), view card / PNG, revoke | ✓ | issue & view |
| Audit Logs | ✓ | ✓ |
| Flagged & Blocked (security cases) | ✓ | view |
| Violations & Penalties — warnings, violations, resolve, reset strikes | ✓ | warnings & view |
| Staff Accounts | ✓ | — |

## Code map (`js/`)

| File | Responsibility |
|---|---|
| `api.js` | API client: bearer token, InfinityFree challenge solver, offline cache (never used for auth errors) |
| `auth.js` | Login screen, forced password change, role classes on `<body>` |
| `app.js` | Original dashboard / directory / registration / audit controller + `window.SP` bridge |
| `gate.js` | Gate Monitor |
| `cctv.js` | CCTV simulation widget |
| `violations.js` | Violations & Penalties, flag modal |
| `overnight.js` | Overtime & overnight attention panel |
| `visitors.js` | Visitor day passes (incl. items) and pass card |
| `oncampus.js` | On Campus Now list, visitor incident reports |
| `users.js` | Staff Accounts |

Role-restricted elements carry the `admin-only` class; the server enforces the same rules.

## Colours

Navy `#1B3676` / `#112552`, gold `#F5B800`, crimson `#D62828`, green `#16A34A` (from the NCST crest).
