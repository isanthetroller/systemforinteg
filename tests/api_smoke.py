"""
SecurePark v2 - API smoke test (standard library only).

Runs against a LOCAL dev server using the SQLite fallback, never production:

    # terminal 1 (repo root) - DB_DRIVER=sqlite uses the local SQLite fallback only
    DB_DRIVER=sqlite php -S localhost:8000 -t .

    # terminal 2
    python tests/api_smoke.py            # uses http://localhost:8000/web-app-admin/api
    python tests/api_smoke.py --fresh    # delete the local SQLite DB first

The script refuses to run against a non-localhost URL.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get('SP_API', 'http://localhost:8000/web-app-admin/api')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQLITE_DB = os.path.join(ROOT, 'web-app-admin', 'data', 'securepark.sqlite')
ADMIN_PASSWORD = 'Admin-Pass-2026'


def _scanner_key():
    """Device key of the local dev server (backend/config/secret.php, git-ignored)."""
    import re
    try:
        with open(os.path.join(ROOT, 'backend', 'config', 'secret.php'), encoding='utf-8') as f:
            m = re.search(r"define\('SP_SCANNER_API_KEY',\s*'([^']+)'", f.read())
            return m.group(1) if m else ''
    except OSError:
        return ''


SCANNER = {'X-Api-Key': _scanner_key(), 'User-Agent': 'SecurePark-GateScanner/2.4'}

if not BASE.startswith(('http://localhost', 'http://127.0.0.1')):
    sys.exit(f'Refusing to run against non-local API: {BASE}')

passed = 0
failed = 0


def call(method, path, body=None, token=None, headers=None):
    req = urllib.request.Request(f'{BASE}/{path}', method=method)
    req.add_header('Accept', 'application/json')
    if body is not None:
        req.add_header('Content-Type', 'application/json')
        req.data = json.dumps(body).encode()
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as res:
            return res.status, json.loads(res.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {'raw': raw}


def check(name, condition, detail=''):
    global passed, failed
    if condition:
        passed += 1
        print(f'  PASS  {name}')
    else:
        failed += 1
        print(f'  FAIL  {name}  {detail}')


def section(title):
    print(f'\n== {title}')


def login(username, password, realm=None):
    path = 'auth.php?action=login' + (f'&realm={realm}' if realm else '')
    return call('POST', path, {'username': username, 'password': password})


def test_auth():
    section('Authentication & first-login password change')
    code, res = call('GET', 'stats.php')
    check('stats without token -> 401', code == 401, code)
    check('response has v2 success flag and legacy status', res.get('success') is False and res.get('status') == 'error', res)

    code, res = login('admin', 'wrong-password')
    check('wrong password -> 401', code == 401, code)

    code, res = login('admin', 'Password123!')
    check('seed admin login -> 200', code == 200, res)
    token = res['data']['token']
    check('seed admin must change password', res['data']['user']['mustChangePassword'] is True, res)

    code, _ = call('GET', 'stats.php', token=token)
    check('pending password change blocks data -> 403', code == 403, code)

    code, res = call('GET', 'auth.php?action=me', token=token)
    check('me works while password change pending', code == 200 and res['data']['user']['username'] == 'admin', res)

    code, res = call('POST', 'auth.php?action=change_password', {'current_password': 'Password123!', 'new_password': 'short'}, token)
    check('weak password rejected', code == 400, res)

    code, res = call('POST', 'auth.php?action=change_password', {'current_password': 'Password123!', 'new_password': ADMIN_PASSWORD}, token)
    check('change password -> 200', code == 200, res)

    code, _ = call('GET', 'stats.php', token=token)
    check('stats with token after change -> 200', code == 200, code)

    code, _ = call('POST', 'auth.php?action=logout', token=token)
    code, _ = call('GET', 'stats.php', token=token)
    check('token revoked after logout -> 401', code == 401, code)

    code, res = login('admin', ADMIN_PASSWORD)
    check('login with new password', code == 200, res)
    return res['data']['token']


def test_staff_accounts(admin):
    section('Staff accounts & role enforcement')
    code, res = call('POST', 'users.php', {'username': 'guard.one', 'full_name': 'Guard One', 'role': 'guard', 'badge_number': 'NCST-SEC-07'}, admin)
    check('admin creates guard -> 201', code == 201 and res['data'].get('tempPassword'), res)
    guard_id = res['data']['user']['id']
    temp = res['data']['tempPassword']

    code, _ = call('POST', 'users.php', {'username': 'guard.one', 'full_name': 'Dup', 'role': 'guard'}, admin)
    check('duplicate username -> 409', code == 409, code)

    code, res = login('guard.one', temp)
    guard = res['data']['token']
    call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Guard-Pass-2026'}, guard)

    code, _ = call('GET', 'users.php', token=guard)
    check('guard cannot list staff -> 403', code == 403, code)
    code, _ = call('POST', 'vehicles.php', {'plateNumber': 'X', 'ownerName': 'Y', 'ownerIdNumber': 'Z'}, guard)
    check('guard cannot register vehicle -> 403', code == 403, code)
    code, _ = call('GET', 'vehicles.php', token=guard)
    check('guard can read vehicles -> 200', code == 200, code)

    code, res = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Entry Recorded'}, guard)
    check('staff cannot admit an unregistered plate -> 403', code == 403 and res['data']['code'] == 'UNREGISTERED', res)
    code, res = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Entry Denied', 'guardName': 'Spoofed Name'}, guard)
    check('guard gate log attributed to account, not body', code == 201 and res['data']['guardName'] == 'Guard One (NCST-SEC-07)', res)
    code, res = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Party Time'}, guard)
    check('invalid gate action rejected -> 400', code == 400, res)
    code, res = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Flagged & Held'}, guard)
    check('legacy action mapped to Entry Denied', code == 201 and res['data']['action'] == 'Entry Denied', res)

    me = call('GET', 'auth.php?action=me', token=admin)[1]['data']['user']
    code, res = call('PUT', 'users.php', {'id': me['id'], 'action': 'set_status', 'status': 'Inactive'}, admin)
    check('admin cannot deactivate self', code == 400, res)
    code, res = call('PUT', 'users.php', {'id': me['id'], 'action': 'update', 'role': 'guard'}, admin)
    check('admin cannot demote self', code == 400, res)

    code, _ = call('PUT', 'users.php', {'id': guard_id, 'action': 'set_status', 'status': 'Inactive'}, admin)
    code2, _ = call('GET', 'vehicles.php', token=guard)
    check('deactivated guard is signed out immediately', code == 200 and code2 == 401, (code, code2))
    code, res = login('guard.one', 'Guard-Pass-2026')
    check('deactivated guard cannot log in -> 403', code == 403, res)
    call('PUT', 'users.php', {'id': guard_id, 'action': 'set_status', 'status': 'Active'}, admin)

    code, res = call('PUT', 'users.php', {'id': guard_id, 'action': 'reset_password'}, admin)
    check('reset password returns new temp password', code == 200 and res['data'].get('tempPassword'), res)


def test_lockout():
    section('Login lockout')
    codes = [login('guard.one', 'nope')[0] for _ in range(5)]
    check('5th failure locks the account -> 423', codes[-1] == 423, codes)
    code, _ = login('guard.one', 'still-locked')
    check('locked account stays locked', code == 423, code)


def test_mobile_compat():
    section('Mobile scanner (device key, no token)')
    code, _ = call('GET', 'vehicles.php?plate=ABC1234', headers={'User-Agent': 'SecurePark-GateScanner/2.4'})
    check('scanner lookup without the device key -> 401', code == 401, code)
    code, _ = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Entry Recorded'})
    check('gate log without the device key -> 401', code == 401, code)
    code, _ = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Entry Recorded'},
                   headers={'X-Api-Key': 'wrong-key'})
    check('gate log with a wrong device key -> 401', code == 401, code)
    code, _ = call('POST', 'verify.php', {'plate': 'ABC1234'})
    check('verify without the device key -> 401', code == 401, code)
    code, res = call('GET', 'vehicles.php?plate=ABC1234', headers=SCANNER)
    check('mobile vehicle lookup with device key', code in (200, 404) and 'status' in res, (code, res))
    code, res = call('POST', 'logs.php', {'plateNumber': 'ABC 1234', 'driverName': 'Juan', 'action': 'Entry Recorded'}, headers=SCANNER)
    check('mobile entry for an unregistered plate refused -> 403 UNREGISTERED', code == 403 and res['data'].get('code') == 'UNREGISTERED', res)
    code, _ = call('GET', 'logs.php')
    check('audit log list still requires staff -> 401', code == 401, code)


def verify(body, token=None, now=None):
    path = 'verify.php' + (f'?now={urllib.parse.quote(now)}' if now else '')
    code, res = call('POST', path, body, token, headers=None if token else SCANNER)
    return code, res.get('data', {}) if isinstance(res, dict) else {}


def open_incidents_for(admin, plate):
    _, res = call('GET', 'incidents.php?status=Held', token=admin)
    return [i for i in res.get('data', []) if i['plateNumber'] == plate]


def test_signed_passes(admin):
    section('Signed QR passes & verification')
    code, res = call('POST', 'vehicles.php', {
        'plateNumber': 'NDK 4821', 'ownerName': 'Juan Dela Cruz', 'ownerIdNumber': 'NCST-2024-0001',
        'ownerPhone': '09171234567', 'makeModelColor': 'White Toyota Vios', 'stickerYear': '2026',
        'authorizedDrivers': [{'fullName': 'Juan Dela Cruz', 'relationship': 'Self (Owner)'},
                              {'fullName': 'Pedro Dela Cruz', 'relationship': 'Brother'}]}, admin)
    check('register vehicle -> 201 with signed payload', code == 201 and res['data'].get('qrPayload'), res)
    veh = res['data']
    payload = json.loads(veh['qrPayload'])
    check('payload is compact (pid, plate, type, valid, sig only)',
          set(payload) == {'v', 'pid', 'plate_number', 'type', 'valid', 'sig'} and payload['valid'] == '2026-12-31', payload)

    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    _, res = call('GET', 'vehicles.php', token=guard)
    check('guard vehicle list has no signed payloads', all('qrPayload' not in v for v in res['data']), res)
    code, _ = call('GET', 'vehicles.php')
    check('anonymous full vehicle list -> 401', code == 401, code)
    code, res = call('GET', 'vehicles.php?plate=NDK-4821', headers=SCANNER)
    check('scanner plate lookup OK, without payload', code == 200 and 'qrPayload' not in res['data'], res)

    code, v = verify({'qr_code': veh['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('valid pass -> VALID, accepted', v.get('result') == 'VALID' and v.get('accepted') is True, v)
    check('verify returns drivers for confirmation', len(v['vehicle']['authorizedDrivers']) == 2, v)

    tampered = dict(payload, plate_number='ABC1234')
    code, v = verify({'qr_code': json.dumps(tampered), 'gate_type': 'Ingress'}, guard)
    check('altered plate -> FORGED, denied, auto-logged', v.get('result') == 'FORGED' and not v['accepted'] and v['autoLogged'], v)
    extended = dict(payload, valid='2030-12-31')
    code, v = verify({'qr_code': json.dumps(extended), 'gate_type': 'Ingress'}, guard)
    check('extended validity date -> FORGED', v.get('result') == 'FORGED', v)
    check('forged scan opens "Revoked / Forged QR" incident', any(i['reason'] == 'Revoked / Forged QR' for i in open_incidents_for(admin, 'NDK 4821')), '')
    code, v = verify({'qr_code': json.dumps(extended), 'gate_type': 'Ingress'}, guard)
    check('repeat forged scan does not duplicate incident', len(open_incidents_for(admin, 'NDK 4821')) == 1, open_incidents_for(admin, 'NDK 4821'))

    code, v = verify({'qr_code': veh['qrPayload'], 'gate_type': 'Ingress'}, guard, now='2027-01-05 08:00:00')
    check('expired pass on entry -> EXPIRED, denied', v.get('result') == 'EXPIRED' and not v['accepted'], v)
    code, v = verify({'qr_code': veh['qrPayload'], 'gate_type': 'Egress'}, guard, now='2027-01-05 08:00:00')
    check('expired pass on exit -> allowed with hold alert', v.get('accepted') is True and any('HOLD' in w for w in v['warnings']), v)

    code, res = call('POST', 'passes.php', {'vehicle_id': veh['id'], 'action': 'reissue'}, guard)
    check('guard cannot reissue passes -> 403', code == 403, code)
    code, res = call('POST', 'passes.php', {'vehicle_id': veh['id'], 'action': 'reissue'}, admin)
    check('admin reissues pass', code == 200 and res['data']['qrPayload'] != veh['qrPayload'], res)
    new_payload = res['data']['qrPayload']
    code, v = verify({'qr_code': veh['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('old pass after reissue -> REVOKED', v.get('result') == 'REVOKED' and not v['accepted'], v)
    code, v = verify({'qr_code': new_payload, 'gate_type': 'Ingress'}, guard)
    check('new pass after reissue -> VALID', v.get('result') == 'VALID', v)

    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'makeModelColor': 'Silver Toyota Vios'}, admin)
    check('edit without plate change keeps the same pass', code == 200 and res['data']['qrPayload'] == new_payload, res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'plateNumber': 'NDK 4822'}, admin)
    check('plate change reissues the pass', code == 200 and res['data']['qrPayload'] != new_payload, res)
    code, v = verify({'qr_code': new_payload, 'gate_type': 'Ingress'}, guard)
    check('pass for the old plate -> REVOKED', v.get('result') == 'REVOKED', v)
    new_payload = res['data']['qrPayload']
    call('PUT', 'vehicles.php', {'id': veh['id'], 'plateNumber': 'NDK 4821'}, admin)
    new_payload = call('GET', 'vehicles.php?plate=NDK4821', token=admin)[1]['data']['qrPayload']
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passValidUntil': '2026-02-30'}, admin)
    check('invalid validity date rejected -> 400', code == 400, res)

    code, v = verify({'plate': 'ndk4821', 'gate_type': 'Ingress'}, guard)
    check('manual plate lookup -> MANUAL with identity warning', v.get('result') == 'MANUAL' and v['accepted'] and v['warnings'], v)
    code, v = verify({'plate': 'ZZZ 999', 'gate_type': 'Ingress'}, guard)
    check('unknown plate -> NOT_FOUND, not logged', v.get('result') == 'NOT_FOUND' and not v['autoLogged'], v)

    call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)
    code, v = verify({'qr_code': new_payload, 'gate_type': 'Ingress'}, guard)
    check('suspended vehicle entry -> SUSPENDED, denied', v.get('result') == 'SUSPENDED' and not v['accepted'], v)
    code, v = verify({'qr_code': new_payload, 'gate_type': 'Egress'}, guard)
    check('suspended vehicle exit -> allowed with hold alert', v.get('accepted') is True, v)
    call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)

    code, v = verify({'qr_code': new_payload, 'gate_type': 'Ingress'})
    check('mobile scanner (device key) can verify', code == 200 and v.get('result') == 'VALID', v)


def test_legacy_passes(admin):
    section('Legacy (pre-v2) passes')
    import sqlite3
    legacy_json = json.dumps({'ownerStudentId': 'NCST-2023-0099', 'ownerFullName': 'Ana Reyes', 'plateNumber': 'LEG 1001',
                              'stickerYear': '2026', 'authorizedDrivers': [{'fullName': 'Ana Reyes', 'relationship': 'Self (Owner)', 'licenseNo': 'N/A'}]})
    db = sqlite3.connect(SQLITE_DB)
    db.execute("INSERT INTO vehicles (plate_number, make_model_color, owner_name, owner_id_number, qr_pass_code) VALUES (?,?,?,?,?)",
               ('LEG 1001', 'Red Honda City', 'Ana Reyes', 'NCST-2023-0099', legacy_json))
    db.execute("INSERT INTO vehicles (plate_number, make_model_color, owner_name, owner_id_number, qr_pass_code) VALUES (?,?,?,?,?)",
               ('LEG 2002', 'Blue Mio', 'Ben Cruz', 'NCST-2023-0100', 'NCST-QR-LEG2002'))
    db.commit()
    db.close()

    code, v = verify({'qr_code': legacy_json, 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check('exact legacy pass before cutoff -> LEGACY accepted with reissue warning',
          v.get('result') == 'LEGACY' and v['accepted'] and any('Legacy' in w for w in v['warnings']), v)
    edited = json.loads(legacy_json)
    edited['authorizedDrivers'].append({'fullName': 'Stranger', 'relationship': 'Friend', 'licenseNo': 'N/A'})
    code, v = verify({'qr_code': json.dumps(edited), 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check('stale legacy pass, same owner ID -> LEGACY (server roster wins), with a warning',
          v.get('result') == 'LEGACY' and v['accepted'] and any('out of date' in w for w in v['warnings']), v)
    check('  ...the driver list on the sticker is not trusted', 'Stranger' not in json.dumps(v.get('vehicle', {}).get('authorizedDrivers', [])), v)
    code, v = verify({'qr_code': json.dumps({'plateNumber': 'LEG 1001'}), 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check('hand-made legacy JSON (plate only) -> REVOKED', v.get('result') == 'REVOKED' and not v['accepted'], v)
    code, v = verify({'qr_code': json.dumps({'plateNumber': 'LEG 1001', 'ownerStudentId': 'NCST-2023-0100'}), 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check("legacy JSON with another owner's ID -> REVOKED", v.get('result') == 'REVOKED' and not v['accepted'], v)
    code, v = verify({'qr_code': json.dumps({'plateNumber': 'LEG 1001', 'ownerStudentId': ' ncst-2023-0099 '}), 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check('owner ID compared without case or spacing -> LEGACY', v.get('result') == 'LEGACY', v)
    code, v = verify({'qr_code': legacy_json, 'gate_type': 'Ingress'}, admin, now='2027-01-02 08:00:00')
    check('legacy pass after cutoff -> FORGED', v.get('result') == 'FORGED', v)
    code, v = verify({'qr_code': 'NCST-QR-LEG2002', 'gate_type': 'Ingress'}, admin, now='2026-10-01 08:00:00')
    check('old plain pass code -> LEGACY', v.get('result') == 'LEGACY', v)
    _, res = call('GET', 'vehicles.php?plate=LEG1001', token=admin)
    check('legacy vehicle gets a pass id + signed payload on first read', res['data'].get('passId') and res['data'].get('qrPayload'), res)


def test_gate_flow(admin):
    section('Gate flow: ingress / egress with driver confirmation')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    _, res = call('GET', 'vehicles.php?plate=NDK4821', token=admin)
    veh = res['data']
    drivers = {d['fullName']: int(d['id']) for d in veh['authorizedDrivers']}
    _, res = call('GET', 'vehicles.php?plate=QAX1', token=admin)

    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Entry Recorded', 'gate_type': 'Ingress'}, guard)
    check('approval without driver confirmation -> 400', code == 400 and res['data']['code'] == 'DRIVER_CONFIRMATION_REQUIRED', res)
    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': 999999}, guard)
    check('driver from another vehicle rejected -> 400', code == 400 and res['data']['code'] == 'DRIVER_NOT_AUTHORIZED', res)
    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Exit Approved', 'gate_type': 'Ingress', 'driver_id': drivers['Pedro Dela Cruz']}, guard)
    check('action / gate_type mismatch rejected -> 400', code == 400, res)

    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': drivers['Pedro Dela Cruz']}, guard)
    check('ingress with confirmed driver -> 201', code == 201 and res['data']['verifiedDriverName'] == 'Pedro Dela Cruz'
          and res['data']['gateType'] == 'Ingress' and res['data']['driverRelationship'] == 'Brother', res)
    _, res = call('GET', 'vehicles.php?plate=NDK4821', token=admin)
    check('vehicle now Inside Campus', res['data']['status'] == 'Inside Campus', res['data']['status'])

    code, v = verify({'qr_code': res['data']['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('second entry scan warns vehicle already inside', any('already recorded inside' in w for w in v['warnings']), v)

    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': drivers['Juan Dela Cruz']}, guard)
    check('egress with confirmed driver -> 201', code == 201 and res['data']['status'] == 'Exited' and res['data']['gateType'] == 'Egress', res)
    _, res = call('GET', 'vehicles.php?plate=NDK4821', token=admin)
    check('vehicle now Outside (never "Exited")', res['data']['status'] == 'Outside', res['data']['status'])

    _, logs = call('GET', 'logs.php?plate=NDK%204821', token=admin)
    latest = logs['data'][0]
    check('gate log stores gate type, verified driver and server time', latest['gateType'] == 'Egress'
          and latest['verifiedDriverName'] == 'Juan Dela Cruz' and len(latest['loggedAt']) == 19, latest)

    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Entry Denied', 'gate_type': 'Ingress', 'driverName': 'Unknown Person', 'notes': 'Unauthorized / Unregistered Driver'}, guard)
    check('denial recorded without changing vehicle status', code == 201 and res['data']['status'] == 'Outside', res)
    _, res = call('GET', 'vehicles.php?plate=NDK4821', token=admin)
    check('vehicle status unchanged by denial', res['data']['status'] == 'Outside', res['data']['status'])

    # Server-side ban / suspension re-check cannot be bypassed by the client
    call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)
    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': drivers['Juan Dela Cruz']}, guard)
    check('entry for suspended vehicle refused server-side -> 403', code == 403 and res['data']['code'] == 'VEHICLE_SUSPENDED', res)
    code, res = call('POST', 'logs.php', {'plateNumber': 'NDK 4821', 'driverName': 'Juan', 'action': 'Entry Recorded'}, headers=SCANNER)
    check('mobile entry for suspended vehicle also refused', code == 403, res)
    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': drivers['Juan Dela Cruz']}, guard)
    check('exit for suspended vehicle still allowed', code == 201, res)
    call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)


def test_violations(admin):
    section('Violations & 3-strike policy')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'STR 3001', 'ownerName': 'Rico Santos', 'ownerIdNumber': 'NCST-2024-3001',
                                             'authorizedDrivers': [{'fullName': 'Rico Santos', 'relationship': 'Self (Owner)'}]}, admin)
    veh = res['data']
    payload = veh['qrPayload']
    driver_id = int(veh['authorizedDrivers'][0]['id'])

    def warn(token, type_='Parking in Fire Lane / Restricted Zone', severity='Warning', notes='Observed by patrol'):
        return call('POST', 'violations.php', {'vehicle_id': veh['id'], 'type': type_, 'severity': severity, 'notes': notes}, token)

    code, res = warn(guard, severity='Violation')
    check('guard cannot issue a Violation -> 403', code == 403, res)
    code, res = warn(guard, type_='Speeding Wildly')
    check('unknown violation type rejected -> 400', code == 400, res)
    code, res = warn(guard, type_='Other', notes='')
    check('"Other" requires notes -> 400', code == 400, res)

    code, res = warn(guard)
    check('1st warning -> strike 1, not banned', code == 201 and res['data']['strikes'] == 1 and not res['data']['banned'], res)
    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('verify shows "Strike 1 of 3"', any('Strike 1 of 3' in w for w in v['warnings']), v)
    code, res = warn(guard, type_='Unauthorized Driver at Helm')
    check('2nd warning -> strike 2', res['data']['strikes'] == 2 and not res['data']['banned'], res)
    code, res = warn(admin, type_='Overnight / Unauthorized Overtime Parking')
    check('3rd warning -> automatic violation + ban', res['data']['strikes'] == 3 and res['data']['banned'] and res['data']['autoViolationId'], res)
    auto_id = res['data']['autoViolationId']
    check('banned vehicle registration Suspended', res['data']['vehicle']['isBanned'] and res['data']['vehicle']['registrationStatus'] == 'Suspended', res['data']['vehicle'])
    check('ban opens "3-Strike Policy Enforced" incident', any(i['reason'] == '3-Strike Policy Enforced' for i in open_incidents_for(admin, 'STR 3001')), '')

    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('banned vehicle entry -> BANNED, denied, logged', v.get('result') == 'BANNED' and not v['accepted'] and v['autoLogged'], v)
    code, res = call('POST', 'logs.php', {'plate': 'STR 3001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver_id}, guard)
    check('entry for banned vehicle refused server-side -> 403', code == 403 and res['data']['code'] == 'VEHICLE_BANNED', res)

    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)
    check('suspend/activate toggle cannot lift a ban -> 409', code == 409, res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'registrationStatus': 'Active'}, admin)
    check('editing registration to Active cannot lift a ban -> 409', code == 409, res)
    inc = [i for i in open_incidents_for(admin, 'STR 3001') if i['reason'] == '3-Strike Policy Enforced'][0]
    code, res = call('PUT', 'incidents.php', {'id': inc['id'], 'notes': 'cleared'}, admin)
    check('clearing the incident directly is refused -> 409', code == 409 and res['data']['code'] == 'VIOLATION_PENDING', res)

    code, res = call('PUT', 'violations.php', {'violation_id': auto_id, 'action': 'resolve', 'notes': 'x'}, guard)
    check('guard cannot resolve -> 403', code == 403, code)
    code, res = call('PUT', 'violations.php', {'violation_id': auto_id, 'action': 'resolve', 'notes': ''}, admin)
    check('resolution notes are mandatory -> 400', code == 400, res)
    code, res = call('PUT', 'violations.php', {'violation_id': auto_id, 'action': 'resolve', 'notes': 'Fine paid / clearance signed (OR #1234)'}, admin)
    check('resolving the violation lifts the ban and resets strikes', code == 200 and res['data']['banLifted']
          and res['data']['vehicle']['warningCount'] == 0 and not res['data']['vehicle']['isBanned']
          and res['data']['vehicle']['registrationStatus'] == 'Active', res)
    _, res = call('GET', f"violations.php?vehicle_id={veh['id']}", token=admin)
    warnings = [x for x in res['data'] if x['severity'] == 'Warning']
    check('the 3 strike warnings are marked cleared by the violation',
          len(warnings) == 3 and all(w['status'] == 'Resolved' and w['clearedByViolationId'] == auto_id for w in warnings), warnings)
    check('3-strike incident closed with the violation', not any(i['reason'] == '3-Strike Policy Enforced' for i in open_incidents_for(admin, 'STR 3001')), '')
    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('vehicle can enter again after resolution', v.get('result') == 'VALID' and v['accepted'], v)
    code, res = call('PUT', 'violations.php', {'violation_id': auto_id, 'action': 'resolve', 'notes': 'again'}, admin)
    check('resolving twice -> 409', code == 409, res)

    # Dismissing a mistaken warning gives the strike back
    code, res = warn(guard)
    wid = res['data']['violation']['id']
    code, res = call('PUT', 'violations.php', {'violation_id': wid, 'action': 'resolve', 'notes': 'n/a'}, admin)
    check('warnings cannot be resolved individually -> 400', code == 400, res)
    code, res = call('PUT', 'violations.php', {'violation_id': wid, 'action': 'dismiss', 'notes': 'Wrong plate noted by patrol'}, admin)
    check('dismissing a warning removes its strike', code == 200 and res['data']['vehicle']['warningCount'] == 0, res)

    # Manual violation bans immediately
    code, res = warn(admin, type_='Reckless / Prohibited Driving on Campus', severity='Violation', notes='Overspeeding near the chapel')
    check('manual violation bans immediately', code == 201 and res['data']['banned'] and res['data']['vehicle']['isBanned'], res)
    vid = res['data']['violation']['id']
    code, res = call('PUT', 'violations.php', {'violation_id': vid, 'action': 'dismiss', 'notes': 'Issued to the wrong vehicle'}, admin)
    check('dismissing a mistaken violation lifts the ban', code == 200 and res['data']['banLifted'] and not res['data']['vehicle']['isBanned'], res)

    # Reset strikes
    warn(guard)
    warn(guard)
    code, res = call('PUT', 'violations.php', {'vehicle_id': veh['id'], 'action': 'reset', 'notes': 'Clearance signed by the Dean of Students'}, admin)
    check('reset strikes & lift suspension', code == 200 and res['data']['vehicle']['warningCount'] == 0 and not res['data']['vehicle']['isBanned'], res)
    _, res = call('GET', 'violations.php?status=Pending&plate=STR3001', token=guard)
    check('guard can list active violations; none pending after reset', isinstance(res['data'], list) and len(res['data']) == 0, res)

def test_overnight(admin):
    section('Overtime & overnight parking detection')
    import sqlite3
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def seed(plate, owner, entered_at):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': owner, 'ownerIdNumber': 'ID-' + plate.replace(' ', ''),
                                                 'ownerPhone': '0917 555 0000'}, admin)
        db = sqlite3.connect(SQLITE_DB)
        db.execute("UPDATE vehicles SET status = 'Inside Campus' WHERE id = ?", (res['data']['id'],))
        db.execute("INSERT INTO gate_logs (plate_number, driver_name, action, gate_type, status, guard_name, logged_at) VALUES (?, ?, 'Entry Recorded', 'Ingress', 'Inside Campus', 'QA', ?)",
                   (plate, owner, entered_at))
        db.commit()
        db.close()
        return res['data']['id']

    night_id = seed('OVN 1001', 'Nora Night', '2026-09-20 08:00:00')
    over_id = seed('OVT 2002', 'Omar Overtime', '2026-09-20 06:00:00')

    def report(now, method='GET', body=None, token=None):
        path = 'overnight_check.php?now=' + urllib.parse.quote(now)
        return call(method, path, body, token or guard)

    code, res = report('2026-09-20 19:00:00')
    items = {i['plateNumber']: i for i in res['data']['items']}
    check('before curfew: long stay listed as overtime only', 'OVN 1001' not in items and items.get('OVT 2002', {}).get('category') == 'overtime', res['data'])
    check('list includes owner phone and elapsed hours', items['OVT 2002']['ownerPhone'] == '0917 555 0000' and items['OVT 2002']['elapsedHours'] == 13.0, items)

    code, res = report('2026-09-20 19:00:00', 'POST')
    check('automatic run does not strike overtime vehicles', code == 200 and res['data']['flagged'] == [], res)

    code, res = report('2026-09-20 19:00:00', 'POST', {'vehicle_id': over_id})
    check('manual "Flag Overnight Strike" on overtime vehicle -> 201', code == 201 and res['data']['strikes'] == 1, res)
    code, res = report('2026-09-20 19:30:00', 'POST', {'vehicle_id': over_id})
    check('flagging the same stay twice -> 409', code == 409 and res['data']['code'] == 'ALREADY_FLAGGED', res)

    code, res = report('2026-09-20 23:00:00', 'POST')
    flagged = {f['plateNumber'] for f in res['data']['flagged']}
    check('after curfew: both vehicles get an overnight strike', flagged == {'OVN 1001', 'OVT 2002'}, res['data'])
    check('strike count shown as "Strike N of 3"', {i['plateNumber']: i['warningCount'] for i in res['data']['items']} == {'OVN 1001': 1, 'OVT 2002': 2}, res['data']['items'])

    code, res = report('2026-09-20 23:30:00', 'POST')
    check('running again the same night adds nothing (idempotent)', res['data']['flagged'] == [], res['data'])
    code, res = report('2026-09-21 01:00:00', 'POST')
    check('after midnight is still the same night', res['data']['flagged'] == [], res['data'])

    code, res = report('2026-09-21 22:30:00', 'POST')
    check('next night -> one more strike each', {f['plateNumber'] for f in res['data']['flagged']} == {'OVN 1001', 'OVT 2002'}, res['data'])
    banned = {f['plateNumber']: f['banned'] for f in res['data']['flagged']}
    check('3rd strike from overnight check bans the vehicle', banned.get('OVT 2002') is True and banned.get('OVN 1001') is False, banned)

    _, res = call('GET', f'violations.php?vehicle_id={night_id}', token=admin)
    check('overnight strikes are logged by "System (Overnight Check)"',
          all(v['loggedBy'] == 'System (Overnight Check)' and v['violationType'].startswith('Overnight') for v in res['data']), res['data'])

    # A vehicle that exits is no longer reported
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Outside' WHERE id = ?", (night_id,))
    db.commit()
    db.close()
    code, res = report('2026-09-22 23:00:00', 'POST')
    check('exited vehicle is not flagged again', 'OVN 1001' not in {f['plateNumber'] for f in res['data']['flagged']}, res['data'])

    code, _ = call('GET', 'overnight_check.php')
    check('overnight report requires sign-in -> 401', code == 401, code)

def test_visitor_passes(admin):
    section('Single-day visitor passes')
    import datetime
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    today = datetime.date.today()
    tomorrow = (today + datetime.timedelta(days=1)).isoformat() + ' 09:00:00'
    base = {'visitor_name': 'Vicente Visitor', 'contact_number': '0918 123 4567', 'plate': 'vis 9001',
            'vehicle_model': 'White Hilux', 'purpose': 'Thesis defense panel', 'person_to_visit': 'CCS Dean’s Office'}

    code, res = call('POST', 'visitors.php', dict(base, contact_number=''), guard)
    check('missing contact number -> 400', code == 400, res)
    code, res = call('POST', 'visitors.php', dict(base, plate='NDK 4821'), guard)
    check('registered plate cannot get a visitor pass -> 409', code == 409 and res['data']['code'] == 'PLATE_REGISTERED', res)

    code, res = call('POST', 'visitors.php', base, guard)
    check('guard issues a day pass -> 201', code == 201 and res['data']['passCode'].startswith('VP-'), res)
    vp = res['data']
    payload = json.loads(vp['qrPayload'])
    check('pass valid only today, signed as visitor_temp', vp['validDate'] == today.isoformat()
          and payload['type'] == 'visitor_temp' and payload['valid'] == today.isoformat() and payload['pid'] == vp['passCode'], vp)
    code, res = call('POST', 'visitors.php', dict(base, visitor_name='Someone Else'), guard)
    check('second active pass for the same plate today -> 409', code == 409 and res['data']['code'] == 'PASS_EXISTS', res)
    code, res = call('POST', 'visitors.php', dict(base, plate='VIS 9002', valid_date='2030-01-01'), guard)
    check('a guard cannot choose the validity date -> 403', code == 403 and res['data']['code'] == 'ADMIN_ONLY_SCHEDULE', res)
    code, res = call('POST', 'visitors.php', dict(base, plate='VIS 9002'), guard)
    check('the pass a guard issues is valid today', code == 201 and res['data']['validDate'] == today.isoformat(), res)
    other = res['data']

    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('visitor pass today -> VALID with visitor details', v.get('result') == 'VALID' and v['visitor']['visitorName'] == 'Vicente Visitor', v)
    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Ingress'}, guard, now=tomorrow)
    check('visitor pass on another date -> EXPIRED_TEMP, denied, logged', v.get('result') == 'EXPIRED_TEMP' and not v['accepted']
          and v['autoLogged'] and 'EXPIRED TEMPORARY PASS' in v['reason'], v)
    forged = json.loads(vp['qrPayload'])
    forged['valid'] = tomorrow[:10]
    code, v = verify({'qr_code': json.dumps(forged), 'gate_type': 'Ingress'}, guard, now=tomorrow)
    check('visitor pass with altered date -> FORGED', v.get('result') == 'FORGED', v)

    code, res = call('POST', 'logs.php', {'plate': 'VIS 9001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': vp['id']}, guard)
    check('visitor entry recorded -> 201, driver = visitor', code == 201 and res['data']['verifiedDriverName'] == 'Vicente Visitor', res)
    code, v = verify({'plate': 'VIS9001', 'gate_type': 'Egress'}, guard)
    check('manual plate lookup finds the visitor inside', v.get('result') == 'MANUAL' and v['visitor'] and v['currentlyInside'], v)
    code, res = call('POST', 'logs.php', {'plate': 'VIS 9001', 'action': 'Exit Approved', 'gate_type': 'Egress', 'visitor_pass_id': vp['id']}, guard)
    check('visitor exit recorded -> 201', code == 201, res)
    _, res = call('GET', f"visitors.php?id={vp['id']}", token=guard)
    check('pass marked Used with entry and exit times', res['data']['status'] == 'Used' and res['data']['entryTime'] and res['data']['exitTime'], res)
    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('used pass cannot enter again -> REVOKED', v.get('result') == 'REVOKED', v)
    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Egress'}, guard)
    check('used pass cannot exit again either', v.get('result') == 'REVOKED', v)
    code, res = call('POST', 'logs.php', {'plate': 'VIS 9001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': vp['id']}, guard)
    check('server refuses re-entry on a used pass -> 403', code == 403 and res['data']['code'] == 'PASS_USED', res)

    # Visitor who entered and stays past the pass date can still leave
    code, res = call('POST', 'logs.php', {'plate': 'VIS 9002', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': other['id']}, guard)
    code, v = verify({'qr_code': other['qrPayload'], 'gate_type': 'Egress'}, guard, now=tomorrow)
    check('overstaying visitor may exit the next day, with a warning', v.get('accepted') is True and v['warnings'], v)

    # Revocation and listing
    code, res = call('POST', 'visitors.php', dict(base, plate='VIS 9003', visitor_name='Rita Revoked'), guard)
    rv = res['data']
    code, res = call('PUT', 'visitors.php', {'id': rv['id'], 'action': 'revoke'}, guard)
    check('guard cannot revoke -> 403', code == 403, code)
    code, res = call('PUT', 'visitors.php', {'id': rv['id'], 'action': 'revoke'}, admin)
    check('admin revokes a pass', code == 200 and res['data']['status'] == 'Revoked', res)
    code, v = verify({'qr_code': rv['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('revoked visitor pass -> REVOKED', v.get('result') == 'REVOKED', v)

    code, res = call('POST', 'visitors.php', dict(base, plate='VIS 9004', visitor_name='Nora No-show'), guard)
    code, res = call('GET', 'visitors.php', token=guard)
    check("today's list contains the passes", {'VIS9001', 'VIS9002', 'VIS9003', 'VIS9004'} <= {p['plateNumber'] for p in res['data']}, res['data'])
    code, res = call('GET', 'visitors.php?now=' + urllib.parse.quote(tomorrow) + '&date=' + tomorrow[:10], token=guard)
    plates = {p['plateNumber']: p for p in res['data']}
    check('next day: unused pass expired, overstaying visitor still listed', 'VIS9004' not in plates and plates.get('VIS9002', {}).get('isInside') is True, res['data'])
    _, res = call('GET', 'visitors.php?date=' + today.isoformat(), token=guard)
    check('never-used pass shows as Expired afterwards', {p['plateNumber']: p['status'] for p in res['data']}.get('VIS9004') == 'Expired', res['data'])

def test_student_portal(admin):
    section('Student portal accounts & scoping')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    owner_id = 'NCST-2025-7777'
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'STU 7001', 'ownerName': 'Sam Student', 'ownerIdNumber': owner_id,
                                             'authorizedDrivers': [{'fullName': 'Sam Student', 'relationship': 'Self (Owner)', 'licenseNo': 'N01-11-111111'}]}, admin)
    acct = res['data']['studentAccount']
    check('registering a vehicle creates the owner portal login', code == 201 and acct['created'] and acct['tempPassword'], acct)
    temp = acct['tempPassword']
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'STU 7002', 'ownerName': 'Sam Student', 'ownerIdNumber': owner_id}, admin)
    check('second vehicle of the same owner reuses the account (no new password)', res['data']['studentAccount']['created'] is False
          and res['data']['studentAccount']['tempPassword'] is None, res['data']['studentAccount'])
    stranger_payload = call('GET', 'vehicles.php?plate=NDK4821', token=admin)[1]['data']['qrPayload']

    code, res = login(owner_id, temp)
    check('student ID cannot sign in to the staff portal', code == 401, code)
    code, res = login(owner_id, temp, realm='student')
    check('student login with temp password', code == 200 and res['data']['student']['mustChangePassword'] is True, res)
    tok = res['data']['token']
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    check('pending password change blocks portal data -> 403', code == 403 and res['data']['code'] == 'PASSWORD_CHANGE_REQUIRED', res)
    code, res = call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Student-Pass-2026'}, tok)
    check('student changes password', code == 200, res)

    code, res = call('GET', 'student.php?action=me', token=tok)
    check('me: profile + summary', code == 200 and res['data']['student']['ownerIdNumber'] == owner_id and res['data']['summary']['vehicles'] == 2, res)
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    plates = sorted(v['plateNumber'] for v in res['data'])
    check('vehicles: only own vehicles', plates == ['STU 7001', 'STU 7002'], plates)
    own = res['data'][0]
    check('own vehicle includes signed QR, drivers, standing', own['qrPayload'] and own['authorizedDrivers'][0]['fullName'] == 'Sam Student'
          and 'warningCount' in own and 'isBanned' in own and 'ownerPhone' not in own, own)
    code, v = verify({'qr_code': own['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('pass shown in the student portal verifies at the gate', v.get('result') == 'VALID', v)
    code, res = call('GET', 'student.php?action=vehicles&owner_id_number=NCST-2024-0001', token=tok)
    check('client-supplied owner ID is ignored', sorted(x['plateNumber'] for x in res['data']) == ['STU 7001', 'STU 7002'], res)

    call('POST', 'violations.php', {'plate': 'STU 7001', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'Blocking hydrant'}, guard)
    code, res = call('GET', 'student.php?action=violations', token=tok)
    check('violations: own warnings visible', code == 200 and len(res['data']) == 1 and res['data'][0]['plateNumber'] == 'STU 7001', res)
    code, res = call('GET', 'student.php?action=me', token=tok)
    check('summary shows strike count', res['data']['summary']['strikes'] == 1, res['data']['summary'])
    call('POST', 'logs.php', {'plate': 'STU 7001', 'action': 'Entry Recorded', 'gate_type': 'Ingress',
                              'driver_id': int(own['authorizedDrivers'] and call('GET', 'vehicles.php?plate=STU7001', token=admin)[1]['data']['authorizedDrivers'][0]['id'])}, guard)
    code, res = call('GET', 'student.php?action=activity', token=tok)
    check('activity: own gate history', code == 200 and res['data'] and all(a['plateNumber'].startswith('STU') for a in res['data']), res)

    # Token separation
    for path in ['vehicles.php', 'vehicles.php?plate=NDK4821', 'logs.php', 'violations.php', 'visitors.php', 'stats.php']:
        code, _ = call('GET', path, token=tok)
        check(f'student token rejected on staff endpoint {path} -> 401', code == 401, code)
    code, _ = call('POST', 'verify.php', {'qr_code': stranger_payload}, tok)
    check('student token cannot use the gate verifier -> 401', code == 401, code)
    code, _ = call('GET', 'student.php?action=vehicles', token=admin)
    check('staff token rejected on student endpoint -> 401', code == 401, code)

    # Admin re-issues the login
    code, res = call('POST', 'students.php', {'owner_id_number': owner_id, 'action': 'issue'}, guard)
    check('guard cannot issue student logins -> 403', code == 403, code)
    code, res = call('POST', 'students.php', {'owner_id_number': owner_id, 'action': 'issue'}, admin)
    check('admin resets student password', code == 200 and res['data']['tempPassword'], res)
    code, _ = call('GET', 'student.php?action=me', token=tok)
    check('old student session revoked after reset', code == 401, code)
    code, res = call('POST', 'students.php', {'owner_id_number': 'NO-SUCH-ID', 'action': 'issue'}, admin)
    check('cannot issue a login for an owner without vehicles -> 404', code == 404, res)
    code, res = call('POST', 'students.php', {'owner_id_number': 'NCST-2023-0099', 'action': 'issue'}, admin)
    check('pre-v2 owner can be given a login from the dossier', code == 200 and res['data']['created'] is True, res)

def test_visitor_items_and_on_campus(admin):
    section('Visitor items & on-campus list')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    base = {'visitor_name': 'Eventos Catering', 'contact_number': '0917 321 0000', 'plate': 'EVT 4040',
            'purpose': 'Foundation day setup', 'person_to_visit': 'Student Affairs Office'}
    items = [{'name': 'Monobloc chairs', 'quantity': 40},
             {'name': 'Sound system', 'quantity': 1, 'description': 'speakers + mixer'},
             {'name': '', 'quantity': 1, 'description': ''}]

    code, res = call('POST', 'visitors.php', dict(base, items=[{'name': 'Chairs', 'quantity': 0}]), guard)
    check('item quantity must be 1-9999 -> 400', code == 400, res)
    code, res = call('POST', 'visitors.php', dict(base, items=[{'name': '', 'quantity': 2, 'description': 'mystery box'}]), guard)
    check('item without a name -> 400', code == 400, res)
    code, res = call('POST', 'visitors.php', dict(base, items=[{'name': f'Item {i}', 'quantity': 1} for i in range(21)]), guard)
    check('more than 20 items -> 400', code == 400, res)

    code, res = call('POST', 'visitors.php', dict(base, items=items), guard)
    vp = res['data']
    check('day pass with items -> 201, blank rows ignored', code == 201 and [i['name'] for i in vp['items']] == ['Monobloc chairs', 'Sound system']
          and vp['items'][0]['quantity'] == 40 and vp['items'][1]['description'] == 'speakers + mixer', vp)
    _, res = call('GET', 'visitors.php', token=guard)
    listed = {p['plateNumber']: p for p in res['data']}
    check('items shown in the visitor list', len(listed['EVT4040']['items']) == 2, listed.get('EVT4040'))

    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('gate verification returns the items', v.get('result') == 'VALID' and len(v['visitor']['items']) == 2, v)
    code, res = call('POST', 'logs.php', {'plate': 'EVT 4040', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': vp['id']}, guard)
    check('entry without checking items -> 400', code == 400 and res['data']['code'] == 'ITEMS_CHECK_REQUIRED', res)
    code, res = call('POST', 'logs.php', {'plate': 'EVT 4040', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': vp['id'], 'items_verified': True}, guard)
    check('entry with items checked -> logged with item list', code == 201 and 'Items checked in: 40x Monobloc chairs, 1x Sound system (speakers + mixer)' in res['data']['notes'], res)

    code, res = call('GET', 'oncampus.php', token=guard)
    oc = res['data']
    visitor_row = next((x for x in oc['visitors'] if x['plateNumber'] == 'EVT4040'), None)
    check('on-campus list includes the visitor and items', code == 200 and visitor_row and len(visitor_row['items']) == 2, oc)
    check('on-campus counts add up', oc['counts']['total'] == len(oc['vehicles']) + len(oc['visitors']), oc['counts'])

    # A registered vehicle entering appears with driver and entry details
    _, res = call('GET', 'vehicles.php?plate=STU7002', token=admin)
    stu = res['data']
    call('POST', 'logs.php', {'plate': 'STU 7002', 'action': 'Entry Recorded', 'gate_type': 'Ingress',
                              'driver_id': int(stu['authorizedDrivers'][0]['id'])}, guard)
    code, res = call('GET', 'oncampus.php', token=guard)
    row = next((x for x in res['data']['vehicles'] if x['plateNumber'] == 'STU 7002'), None)
    check('registered vehicle listed with driver, gate and guard', row and row['enteredBy'] == 'Sam Student'
          and row['admittedBy'] == 'QA Guard (NCST-SEC-99)' and row['hoursInside'] is not None, row)

    code, res = call('POST', 'logs.php', {'plate': 'EVT 4040', 'action': 'Exit Approved', 'gate_type': 'Egress', 'visitor_pass_id': vp['id'], 'items_verified': True}, guard)
    check('exit with items checked -> "Items checked out" logged', code == 201 and 'Items checked out:' in res['data']['notes'], res)
    code, res = call('GET', 'oncampus.php', token=guard)
    check('visitor leaves the on-campus list after exit', not any(x['plateNumber'] == 'EVT4040' for x in res['data']['visitors']), res['data']['visitors'])

    # Mobile scanner cannot tick the box: allowed, but the log says items were not checked
    code, res = call('POST', 'visitors.php', dict(base, plate='EVT 4041', items=[{'name': 'Tables', 'quantity': 10}]), guard)
    code, res = call('POST', 'logs.php', {'plateNumber': 'EVT 4041', 'driverName': 'Driver', 'action': 'Entry Recorded'}, headers=SCANNER)
    check('mobile entry logs items as not checked', code == 201 and 'not checked by mobile scanner' in res['data']['notes'], res)
    check('mobile log attributed to Mobile Scanner', res['data'].get('guardName', '').startswith('Mobile Scanner'), res)

    code, _ = call('GET', 'oncampus.php')
    check('on-campus list requires sign-in -> 401', code == 401, code)


def test_scheduled_and_revoked_passes(admin):
    section('Scheduled day passes, revoke while inside, retired setting')
    import datetime
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    today = datetime.date.today()
    day = lambda n: (today + datetime.timedelta(days=n)).isoformat()
    base = {'visitor_name': 'Sofia Scheduled', 'contact_number': '0917 555 0101', 'plate': 'SCH 5001',
            'purpose': 'Board meeting', 'person_to_visit': 'Office of the President'}

    # --- who may pick a day, and which days are allowed
    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(3)), guard)
    check('guard cannot schedule another day -> 403', code == 403 and res['data']['code'] == 'ADMIN_ONLY_SCHEDULE', res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(-1)), admin)
    check('past date refused -> 400', code == 400 and res['data']['code'] == 'DATE_IN_PAST', res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(61)), admin)
    check('more than 60 days ahead refused -> 400', code == 400 and res['data']['code'] == 'DATE_TOO_FAR', res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date='2026-02-30'), admin)
    check('impossible date refused -> 400', code == 400, res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date='soon'), admin)
    check('malformed date refused -> 400', code == 400, res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date=today.isoformat()), guard)
    check('guard may still pass today explicitly -> 201', code == 201 and res['data']['validDate'] == today.isoformat(), res)
    today_pass = res['data']

    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(3)), admin)
    check('admin schedules a pass 3 days ahead -> 201', code == 201 and res['data']['validDate'] == day(3), res)
    future = res['data']
    check('pass code carries the chosen day', future['passCode'].startswith('VP-' + day(3).replace('-', '') + '-'), future['passCode'])
    payload = json.loads(future['qrPayload'])
    check('QR is signed for the chosen day', payload['valid'] == day(3) and payload['type'] == 'visitor_temp', payload)
    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(3)), admin)
    check('second pass for the same plate and day -> 409', code == 409 and res['data']['code'] == 'PASS_EXISTS', res)
    code, res = call('POST', 'visitors.php', dict(base, valid_date=day(5)), admin)
    check('same plate on a different day is allowed', code == 201, res)

    # --- before its day the pass is "not yet valid", never "forged" or "expired"
    code, v = verify({'qr_code': future['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('future pass at entrance -> NOT_YET_VALID, refused', v.get('result') == 'NOT_YET_VALID' and v.get('accepted') is False, v)
    check('  ...with the date in the reason', day(3) in v.get('reason', ''), v)
    check('  ...no security incident for an early visitor', v.get('incident') is None and v.get('autoLogged') is True, v)
    check('  ...and no "manual lookup" warning on a denial', not any('Manual lookup' in w for w in v.get('warnings', [])), v)
    code, v = verify({'qr_code': future['qrPayload'], 'gate_type': 'Egress'}, guard)
    check('future pass at exit gate -> refused too', v.get('result') == 'NOT_YET_VALID' and v.get('accepted') is False, v)
    code, res = call('POST', 'logs.php', {'plate': 'SCH 5001', 'action': 'Entry Recorded', 'gate_type': 'Ingress',
                                          'visitor_pass_id': future['id']}, guard)
    check('server refuses to log the entry -> 403 NOT_YET_VALID', code == 403 and res['data']['code'] == 'NOT_YET_VALID', res)
    code, v = verify({'qr_code': future['qrPayload'], 'gate_type': 'Ingress'}, guard, now=day(3) + ' 08:00:00')
    check('on its day the same QR verifies', v.get('result') == 'VALID' and v.get('accepted') is True, v)
    code, v = verify({'qr_code': future['qrPayload'], 'gate_type': 'Ingress'}, guard, now=day(4) + ' 08:00:00')
    check('the day after it is EXPIRED_TEMP', v.get('result') == 'EXPIRED_TEMP', v)
    code, v = verify({'qr_code': future['qrPayload'], 'gate_type': 'Ingress'}, guard, now=day(3) + ' 23:59:00')
    check('valid all day: still accepted at 23:59', v.get('result') == 'VALID', v)

    # --- manual plate lookup
    code, v = verify({'plate': 'SCH 5001', 'gate_type': 'Ingress'}, guard)
    check('plate lookup finds today\'s pass, not the upcoming ones', v.get('accepted') is True and v['visitor']['validDate'] == today.isoformat(), v)
    code, v = verify({'plate': 'SCH 5001', 'gate_type': 'Ingress'}, guard, now=day(1) + ' 09:00:00')
    check('plate lookup with only upcoming passes -> NOT_YET_VALID', v.get('result') == 'NOT_YET_VALID', v)

    # --- listing
    code, res = call('GET', 'visitors.php?upcoming=1', token=guard)
    plates = [x['validDate'] for x in res['data']]
    check('upcoming list: future active passes, soonest first', code == 200 and day(3) in plates and day(5) in plates
          and plates == sorted(plates) and today.isoformat() not in plates, res)
    code, res = call('GET', f'visitors.php?date={day(3)}', token=guard)
    check('day list shows the scheduled pass on its day', any(x['id'] == future['id'] for x in res['data']), res)
    code, res = call('GET', 'visitors.php', token=guard)
    check('default list (today) does not include future passes', not any(x['id'] == future['id'] for x in res['data']), res)

    # --- revoke a visitor who is on campus: hold + can still leave
    code, res = call('POST', 'logs.php', {'plate': 'SCH 5001', 'action': 'Entry Recorded', 'gate_type': 'Ingress',
                                          'visitor_pass_id': today_pass['id']}, guard)
    check('visitor with today\'s pass enters', code == 201, res)
    code, res = call('GET', 'oncampus.php', token=guard)
    check('visitor is on the campus list', any(x['plateNumber'] == 'SCH5001' for x in res['data']['visitors']), res['data']['visitors'])
    code, res = call('PUT', 'visitors.php', {'id': today_pass['id'], 'action': 'revoke', 'notes': 'Disruptive behaviour'}, guard)
    check('guard cannot revoke -> 403', code == 403, code)
    code, res = call('PUT', 'visitors.php', {'id': today_pass['id'], 'action': 'revoke', 'notes': 'Disruptive behaviour'}, admin)
    check('admin revokes a pass whose visitor is inside -> 200', code == 200 and res['data']['status'] == 'Revoked', res)
    check('  ...a security hold is opened', 'hold CASE-' in res['message'], res['message'])
    held = open_incidents_for(admin, 'SCH5001')
    check('  ...the incident is in the Held queue with the reason', held and held[0]['reason'] == 'Visitor pass revoked while on campus'
          and 'Disruptive behaviour' in (held[0].get('notes') or ''), held)
    code, res = call('GET', 'oncampus.php', token=guard)
    row = next((x for x in res['data']['visitors'] if x['plateNumber'] == 'SCH5001'), None)
    check('revoked visitor stays on the campus list, flagged', row is not None and row['revoked'] is True and row['activeHold'], row)
    code, st = call('GET', 'stats.php', token=guard)
    check('the dashboard headcount (stats) matches the On Campus list, revoked visitor included',
          st['data']['inside'] == res['data']['counts']['total'], (st['data']['inside'], res['data']['counts']))
    code, v = verify({'qr_code': today_pass['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('revoked pass is refused at the entrance', v.get('result') == 'REVOKED' and v.get('accepted') is False, v)
    code, v = verify({'qr_code': today_pass['qrPayload'], 'gate_type': 'Egress'}, guard)
    check('revoked visitor inside may still leave, with a hold alert',
          v.get('accepted') is True and v.get('result') == 'REVOKED' and any('HOLD ALERT' in w for w in v.get('warnings', [])), v)
    code, res = call('POST', 'logs.php', {'plate': 'SCH 5001', 'action': 'Exit Approved', 'gate_type': 'Egress',
                                          'visitor_pass_id': today_pass['id']}, guard)
    check('exit is logged', code == 201 and res['data']['status'] == 'Exited', res)
    code, res = call('GET', f'visitors.php?id={today_pass["id"]}', token=guard)
    check('the pass stays Revoked after the exit', res['data']['status'] == 'Revoked' and res['data']['exitTime'], res['data'])
    code, res = call('GET', 'oncampus.php', token=guard)
    check('visitor leaves the campus list after exit', not any(x['plateNumber'] == 'SCH5001' for x in res['data']['visitors']), res['data']['visitors'])

    # --- a vehicle's state is "Outside", and the retired setting is gone
    code, res = call('GET', 'settings.php')
    check('settings: read-only policy values', code == 200 and 'curfew_time' in res['data'], res)
    check('settings: no visitor pass hour limit any more', 'visitor_pass_validity_hours' not in res['data'], res['data'])
    code, _ = call('POST', 'settings.php', {'visitor_pass_validity_hours': 4}, admin)
    check('settings cannot be written -> 405', code == 405, code)


def test_vip_passes(admin):
    section('VIP passes (permanent vehicles)')
    import sqlite3
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def register(plate, owner, **extra):
        body = {'plateNumber': plate, 'ownerName': owner, 'ownerIdNumber': 'ID-' + plate.replace(' ', ''),
                'ownerPhone': '0917 000 1111', 'authorizedDrivers': [{'fullName': owner, 'relationship': 'Self (Owner)'}]}
        body.update(extra)
        return call('POST', 'vehicles.php', body, admin)

    def driver_id(plate):
        _, res = call('GET', 'vehicles.php?plate=' + plate.replace(' ', ''), token=admin)
        return int(res['data']['authorizedDrivers'][0]['id'])

    # --- who can grant it
    code, res = register('VIP 0001', 'Dr. Rosa President', passClass='VIP')
    check('admin registers a VIP vehicle -> 201', code == 201 and res['data']['isVip'] is True and res['data']['passClass'] == 'VIP', res)
    vip = res['data']
    check('  ...who granted it and when is recorded', bool(vip.get('vipGrantedBy')) and len(vip.get('vipGrantedAt') or '') == 19, vip)
    payload = json.loads(vip['qrPayload'])
    check('  ...the class is NOT in the signed QR', set(payload) == {'v', 'pid', 'plate_number', 'type', 'valid', 'sig'} and payload['type'] == 'permanent', payload)
    code, res = register('VIP 0002', 'Sam Standard')
    check('a normal registration is Standard', code == 201 and res['data']['isVip'] is False and res['data']['passClass'] == 'Standard', res)
    std = res['data']
    code, res = register('VIP 0009', 'Bad Class', passClass='gold')
    check('unknown pass class -> 400', code == 400, res)
    code, _ = call('POST', 'vehicles.php', {'plateNumber': 'VIP 0008', 'ownerName': 'X', 'ownerIdNumber': 'X-8', 'passClass': 'VIP'}, guard)
    check('a guard cannot register a VIP -> 403', code == 403, code)
    code, _ = call('PUT', 'vehicles.php', {'id': std['id'], 'passClass': 'VIP'}, guard)
    check('a guard cannot make a vehicle VIP -> 403', code == 403, code)
    _, res = call('GET', 'vehicles.php?plate=VIP0002', token=admin)
    check('  ...and it stayed Standard', res['data']['isVip'] is False, res['data'])

    # --- the gate: a VIP is not asked who is driving; a normal vehicle still is
    code, v = verify({'qr_code': vip['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('VIP verifies like any signed pass, flagged isVip', v.get('result') == 'VALID' and v['vehicle']['isVip'] is True, v)
    code, res = call('POST', 'logs.php', {'plate': 'VIP 0001', 'action': 'Entry Recorded', 'gate_type': 'Ingress'}, guard)
    check('VIP entry needs no driver confirmation -> 201', code == 201, res)
    check('  ...the log says VIP and that the driver was not checked', res['data']['notes'].startswith('VIP pass')
          and res['data']['driverRelationship'] == 'VIP (driver not checked)' and res['data']['driverName'] == 'Dr. Rosa President', res['data'])
    code, res = call('POST', 'logs.php', {'plate': 'VIP 0002', 'action': 'Entry Recorded', 'gate_type': 'Ingress'}, guard)
    check('a Standard vehicle still needs a driver -> 400', code == 400 and res['data']['code'] == 'DRIVER_CONFIRMATION_REQUIRED', res)
    code, res = call('POST', 'logs.php', {'plate': 'VIP 0002', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver_id('VIP 0002')}, guard)
    check('  ...and enters once the driver is chosen', code == 201 and not res['data']['notes'].startswith('VIP'), res)

    # --- forged / revoked passes are still stopped for a VIP
    forged = dict(payload, plate_number='VIP0001', sig='AAAAAAAAAAAAAAAAAAAAAA')
    code, v = verify({'qr_code': json.dumps(forged), 'gate_type': 'Egress'}, guard)
    check('a forged VIP QR is still FORGED', v.get('result') == 'FORGED' and not v['accepted'], v)
    code, res = call('POST', 'passes.php', {'vehicle_id': vip['id'], 'action': 'reissue'}, admin)
    code, v = verify({'qr_code': vip['qrPayload'], 'gate_type': 'Egress'}, guard)
    check('the old VIP pass is REVOKED after a reissue', v.get('result') == 'REVOKED' and not v['accepted'], v)
    new_payload = res['data']['qrPayload']
    code, v = verify({'qr_code': new_payload, 'gate_type': 'Egress'}, guard)
    check('the reissued VIP pass works', v.get('result') == 'VALID', v)

    # --- no strikes, no violations, no ban
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'x'}, guard)
    check('a warning against a VIP is refused -> 409', code == 409 and res['data']['code'] == 'VIP_EXEMPT', res)
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Reckless / Prohibited Driving on Campus', 'severity': 'Violation', 'notes': 'x'}, admin)
    check('a violation against a VIP is refused -> 409', code == 409 and res['data']['code'] == 'VIP_EXEMPT', res)
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0002', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'x'}, guard)
    check('a Standard vehicle still gets warnings', code == 201, res)

    # --- overnight / overtime: the VIP is not listed, flagged or struck
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Inside Campus' WHERE plate_number IN ('VIP 0001', 'VIP 0002')")
    db.execute("DELETE FROM gate_logs WHERE plate_number IN ('VIP 0001', 'VIP 0002') AND action = 'Entry Recorded'")
    for plate, who in (('VIP 0001', 'Dr. Rosa President'), ('VIP 0002', 'Sam Standard')):
        db.execute("INSERT INTO gate_logs (plate_number, driver_name, action, gate_type, status, guard_name, logged_at) VALUES (?, ?, 'Entry Recorded', 'Ingress', 'Inside Campus', 'QA', '2026-09-20 06:00:00')", (plate, who))
    db.commit()
    db.close()
    night = 'overnight_check.php?now=' + urllib.parse.quote('2026-09-20 23:00:00')
    code, res = call('GET', night, token=guard)
    listed = {i['plateNumber'] for i in res['data']['items']}
    check('overnight report lists the Standard vehicle, not the VIP', 'VIP 0002' in listed and 'VIP 0001' not in listed, listed)
    code, res = call('POST', night, {}, guard)
    flagged = {f['plateNumber'] for f in res['data']['flagged']}
    check('the automatic run strikes the Standard vehicle only', 'VIP 0002' in flagged and 'VIP 0001' not in flagged, flagged)
    code, res = call('POST', night, {'vehicle_id': vip['id']}, guard)
    check('a manual overnight flag on a VIP -> 404 (not listed)', code == 404, res)
    code, res = call('GET', 'oncampus.php?now=' + urllib.parse.quote('2026-09-21 09:00:00'), token=guard)
    rows = {v['plateNumber']: v for v in res['data']['vehicles']}
    check('On Campus Now shows the VIP, with no time flag', rows['VIP 0001']['isVip'] is True and rows['VIP 0001']['timeFlag'] is None, rows.get('VIP 0001'))
    check('  ...while the Standard vehicle is flagged overnight', rows['VIP 0002']['timeFlag'] == 'overnight', rows.get('VIP 0002'))
    _, res = call('GET', 'vehicles.php?plate=VIP0001', token=admin)
    check('the VIP still has 0 strikes and is not banned', res['data']['warningCount'] == 0 and res['data']['isBanned'] is False, res['data'])

    # --- a banned vehicle cannot be made VIP; withdrawing VIP restores the rules
    code, res = register('VIP 0003', 'Ban Candidate')
    for _ in range(3):
        call('POST', 'violations.php', {'plate': 'VIP 0003', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'x'}, guard)
    _, res = call('GET', 'vehicles.php?plate=VIP0003', token=admin)
    check('(setup) three strikes ban the vehicle', res['data']['isBanned'] is True, res['data'])
    banned_id = res['data']['id']
    code, res = call('PUT', 'vehicles.php', {'id': banned_id, 'passClass': 'VIP'}, admin)
    check('a banned vehicle cannot be made VIP -> 409', code == 409 and res['data']['code'] == 'VEHICLE_BANNED', res)

    code, res = call('PUT', 'vehicles.php', {'id': std['id'], 'passClass': 'VIP'}, admin)
    check('admin makes an existing vehicle VIP', code == 200 and res['data']['isVip'] is True and res['data']['vipGrantedBy'], res)
    code, res = call('PUT', 'vehicles.php', {'id': std['id'], 'passClass': 'Standard'}, admin)
    check('admin withdraws VIP', code == 200 and res['data']['isVip'] is False and res['data']['vipGrantedBy'] is None, res)
    code, res = call('PUT', 'vehicles.php', {'id': vip['id'], 'passClass': 'Standard'}, admin)
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'x'}, guard)
    check('once VIP is withdrawn the vehicle can be warned again', code == 201, res)
    code, res = call('PUT', 'vehicles.php', {'id': vip['id'], 'ownerRole': 'Faculty'}, admin)
    check('editing other fields does not change the class', code == 200, res)


def test_offline_sync(admin):
    section('Offline sync (mobile events recorded without a connection)')
    import datetime, sqlite3, uuid
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    utc = datetime.timezone.utc
    manila = datetime.timezone(datetime.timedelta(hours=8))
    now = datetime.datetime.now(utc)

    def ago(hours=0, minutes=0):
        return now - datetime.timedelta(hours=hours, minutes=minutes)

    def iso(t):
        return t.strftime('%Y-%m-%dT%H:%M:%SZ')

    def manila_str(t):
        return t.astimezone(manila).strftime('%Y-%m-%d %H:%M:%S')

    def ev(type_, t, payload, ref=None):
        return {'client_ref': ref or ('T-' + uuid.uuid4().hex[:20]), 'type': type_, 'occurred_at': iso(t), 'payload': payload}

    def sync(events, headers=SCANNER, token=None):
        return call('POST', 'sync.php', {'events': events}, token, headers=None if token else headers)

    def register(plate, owner):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': owner, 'ownerIdNumber': 'ID-' + plate.replace(' ', ''),
                                                 'authorizedDrivers': [{'fullName': owner, 'relationship': 'Self (Owner)'}]}, admin)
        return res['data']

    def vehicle(plate):
        return call('GET', 'vehicles.php?plate=' + plate.replace(' ', ''), token=admin)[1]['data']

    def logs_for(plate, limit=50):
        return [l for l in call('GET', f'logs.php?limit=200', token=admin)[1]['data'] if l['plateNumber'] == plate][:limit]

    def entry(plate, **extra):
        return dict({'plate': plate, 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': 'Guard-checked Driver'}, **extra)

    def exit_(plate, **extra):
        return dict({'plate': plate, 'action': 'Exit Approved', 'gate_type': 'Egress', 'driverName': 'Guard-checked Driver'}, **extra)

    # --- access and shape
    code, _ = call('POST', 'sync.php', {'events': [ev('gate_log', ago(1), entry('SYN 1001'))]})
    check('sync without the device key -> 401', code == 401, code)
    code, _ = call('GET', 'sync.php', headers=SCANNER)
    check('sync only accepts POST -> 405', code == 405, code)
    code, _ = sync([])
    check('empty batch -> 400', code == 400, code)
    code, _ = sync([ev('gate_log', ago(1), entry('SYN 1001')) for _ in range(51)])
    check('more than 50 events -> 400', code == 400, code)

    # --- an offline entry keeps its real time
    v1 = register('SYN 1001', 'Nina Offline')
    t_in = ago(hours=3)
    e1 = ev('gate_log', t_in, entry('SYN 1001', guardName='Officer Reyes'))
    code, res = sync([e1])
    r = res['data']['results'][0]
    check('offline entry accepted', code == 200 and r['status'] == 'accepted' and r['flags'] == [] and r['id'], res)
    row = logs_for('SYN 1001')[0]
    check('  ...logged with the time it HAPPENED, not the sync time', row['loggedAt'] == manila_str(t_in), (row['loggedAt'], manila_str(t_in)))
    check('  ...and the sync time is recorded separately', row.get('syncedAt') and row['syncedAt'] > row['loggedAt'], row)
    check('  ...noted as recorded offline, with the operator', 'Recorded offline' in row['notes'] and 'Officer Reyes' in row['notes'], row['notes'])
    v = vehicle('SYN 1001')
    check('  ...vehicle is Inside Campus since the event time', v['status'] == 'Inside Campus' and v['lastEntryTime'] == manila_str(t_in), v)

    # --- resending is harmless
    code, res = sync([e1])
    r2 = res['data']['results'][0]
    check('the same client_ref again -> duplicate, same log', r2['status'] == 'duplicate' and r2['id'] == r['id'], res)
    check('  ...still one row', len(logs_for('SYN 1001')) == 1, logs_for('SYN 1001'))

    # --- the exit that followed
    t_out = ago(hours=1)
    code, res = sync([ev('gate_log', t_out, exit_('SYN 1001'))])
    check('offline exit accepted', res['data']['results'][0]['status'] == 'accepted', res)
    check('  ...vehicle is Outside again', vehicle('SYN 1001')['status'] == 'Outside', vehicle('SYN 1001')['status'])

    # --- events arrive out of order: still ends up right
    register('SYN 1003', 'Omar Order')
    code, res = sync([ev('gate_log', ago(hours=1), exit_('SYN 1003')), ev('gate_log', ago(hours=4), entry('SYN 1003'))])
    check('exit listed before entry in one batch: both accepted', [x['status'] for x in res['data']['results']] == ['accepted', 'accepted'] or
          sorted(x['status'] for x in res['data']['results']) == ['accepted', 'accepted'], res)
    check('  ...processed oldest first, so the vehicle ends Outside', vehicle('SYN 1003')['status'] == 'Outside', vehicle('SYN 1003')['status'])

    # --- a stale event must not overwrite newer state
    v4 = register('SYN 1004', 'Sam Stale')
    drv = int(vehicle('SYN 1004')['authorizedDrivers'][0]['id'])
    code, res = call('POST', 'logs.php', {'plate': 'SYN 1004', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': drv}, guard)
    check('(setup) live entry now', code == 201, res)
    code, res = sync([ev('gate_log', ago(hours=5), exit_('SYN 1004'))])
    check('an older offline exit is still logged', res['data']['results'][0]['status'] == 'accepted', res)
    check('  ...but the vehicle stays Inside (the live entry is newer)', vehicle('SYN 1004')['status'] == 'Inside Campus', vehicle('SYN 1004')['status'])

    # --- events that already happened are recorded even when the server would have refused them
    b = register('SYN 1005', 'Ben Banned')
    for _ in range(3):
        call('POST', 'violations.php', {'plate': 'SYN 1005', 'type': 'Parking in Fire Lane / Restricted Zone', 'severity': 'Warning', 'notes': 'x'}, guard)
    check('(setup) vehicle is banned', vehicle('SYN 1005')['isBanned'] is True, vehicle('SYN 1005'))
    code, res = call('POST', 'logs.php', {'plate': 'SYN 1005', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': int(vehicle('SYN 1005')['authorizedDrivers'][0]['id'])}, guard)
    check('(live) the same entry would be refused', code == 403, res)
    code, res = sync([ev('gate_log', ago(hours=2), entry('SYN 1005'))])
    r = res['data']['results'][0]
    check('offline entry of a banned vehicle is RECORDED, flagged BANNED', r['status'] == 'accepted' and r['flags'] == ['BANNED'] and r['caseNumber'], res)
    held = open_incidents_for(admin, 'SYN 1005')
    check('  ...a Held incident tells the security office it is on campus', any(i['reason'] == 'Offline entry needs review' for i in held), held)
    check('  ...the log says why', 'FLAGGED AT SYNC: BANNED' in logs_for('SYN 1005')[0]['notes'], logs_for('SYN 1005')[0]['notes'])
    check('  ...and the vehicle is shown inside', vehicle('SYN 1005')['status'] == 'Inside Campus', vehicle('SYN 1005')['status'])

    code, res = sync([ev('gate_log', ago(hours=2), entry('SYN 9999'))])
    r = res['data']['results'][0]
    check('offline entry of an unregistered plate: recorded, flagged UNREGISTERED', r['status'] == 'accepted' and r['flags'] == ['UNREGISTERED'], res)

    # --- visitor passes
    base = {'visitor_name': 'Vera Visitor', 'contact_number': '0917 111 2222', 'plate': 'SYN 2002', 'purpose': 'Meeting', 'person_to_visit': 'Registrar'}
    code, res = call('POST', 'visitors.php', base, guard)
    vp = res['data']
    t_v = ago(minutes=90)
    code, res = sync([ev('gate_log', t_v, entry('SYN 2002', driverName=''))])
    r = res['data']['results'][0]
    check('offline entry with a valid day pass: accepted, no flags', r['status'] == 'accepted' and r['flags'] == [], res)
    code, res = call('GET', f'visitors.php?id={vp["id"]}', token=guard)
    check('  ...the pass records the real entry time', res['data']['entryTime'] == manila_str(t_v) and res['data']['isInside'] is True, res['data'])
    code, res = sync([ev('visitor_exit', ago(minutes=30), {'passId': vp['passCode'], 'plateNumber': 'SYN 2002'}, ref='T-visitorexit-0001')])
    check('offline visitor checkout accepted', res['data']['results'][0]['status'] == 'accepted', res)
    code, res = call('GET', f'visitors.php?id={vp["id"]}', token=guard)
    exit_time = res['data']['exitTime']
    check('  ...the pass records the real exit time and is Used', exit_time == manila_str(ago(minutes=30)) and res['data']['status'] == 'Used', res['data'])
    code, res = sync([ev('visitor_exit', ago(minutes=5), {'passId': vp['passCode']}, ref='T-visitorexit-0002')])
    code, res2 = call('GET', f'visitors.php?id={vp["id"]}', token=guard)
    check('  ...a second checkout keeps the first exit time', res2['data']['exitTime'] == exit_time, res2['data'])
    code, res = sync([ev('visitor_exit', ago(minutes=5), {'passId': 'VP-NOPE-0000'}, ref='T-visitorexit-0003')])
    check('checkout for an unknown pass -> rejected NOT_FOUND', res['data']['results'][0]['code'] == 'NOT_FOUND', res)

    tomorrow = (datetime.date.today() + datetime.timedelta(days=2)).isoformat()
    code, res = call('POST', 'visitors.php', dict(base, plate='SYN 2003', valid_date=tomorrow), admin)
    future = res['data']
    code, res = sync([ev('gate_log', ago(minutes=20), entry('SYN 2003'))])
    check('offline entry on a pass for a later day: recorded, flagged NOT_YET_VALID', res['data']['results'][0]['flags'] == ['NOT_YET_VALID'], res)
    code, res = call('POST', 'visitors.php', dict(base, plate='SYN 2004'), guard)
    call('PUT', 'visitors.php', {'id': res['data']['id'], 'action': 'revoke'}, admin)
    code, res = sync([ev('gate_log', ago(minutes=20), entry('SYN 2004'))])
    check('offline entry on a revoked pass: recorded, flagged REVOKED', res['data']['results'][0]['flags'] == ['REVOKED'], res)
    code, res = sync([ev('visitor_pass', ago(minutes=20), dict(base, plate='SYN 2005'), ref='T-visitorpass-0001')])
    check('a visitor pass cannot be issued offline -> rejected', res['data']['results'][0]['code'] == 'NOT_SUPPORTED_OFFLINE', res)
    code, res = call('GET', 'visitors.php?q=SYN2005', token=guard)
    check('  ...and none was created', code == 404, code)

    # --- VIP
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'SYN 3001', 'ownerName': 'Dr. Vee', 'ownerIdNumber': 'ID-SYN3001', 'passClass': 'VIP'}, admin)
    code, res = sync([ev('gate_log', ago(hours=2), {'plate': 'SYN 3001', 'action': 'Entry Recorded', 'gate_type': 'Ingress'})])
    check('offline VIP entry: recorded with no flags and tagged VIP', res['data']['results'][0]['flags'] == [] and logs_for('SYN 3001')[0]['notes'].startswith('VIP pass'), res)

    # --- time rules
    code, res = sync([ev('gate_log', ago(hours=25), entry('SYN 1001'))])
    check('an event older than 24 hours -> rejected EVENT_TOO_OLD', res['data']['results'][0]['code'] == 'EVENT_TOO_OLD', res)
    code, res = sync([ev('gate_log', ago(hours=23, minutes=50), entry('SYN 1001'))])
    check('an event just inside the limit is accepted', res['data']['results'][0]['status'] == 'accepted', res)
    future_t = now + datetime.timedelta(hours=2)
    code, res = sync([ev('gate_log', future_t, entry('SYN 1006'))])
    row = logs_for('SYN 1006')[0]
    check('a phone clock running ahead is clamped to now, and noted', res['data']['results'][0]['status'] == 'accepted'
          and row['loggedAt'] <= manila_str(now + datetime.timedelta(minutes=2)) and 'clock was ahead' in row['notes'], row)
    code, res = sync([dict(ev('gate_log', ago(1), entry('SYN 1001')), occurred_at='sometime')])
    check('an unreadable event time -> rejected', res['data']['results'][0]['code'] == 'INVALID_OCCURRED_AT', res)
    code, res = sync([{'client_ref': 'T-missing-time-0001', 'type': 'gate_log', 'payload': entry('SYN 1001')}])
    check('a missing event time -> rejected', res['data']['results'][0]['code'] == 'MISSING_OCCURRED_AT', res)
    code, res = sync([dict(ev('gate_log', ago(1), entry('SYN 1001')), client_ref='short')])
    check('a bad client_ref -> rejected', res['data']['results'][0]['code'] == 'INVALID_CLIENT_REF', res)

    # --- one bad event never blocks the others
    good = ev('gate_log', ago(minutes=10), exit_('SYN 1001'))
    code, res = sync([ev('teleport', ago(1), {}, ref='T-unknown-type-0001'), ev('gate_log', ago(1), {'action': 'Entry Recorded'}, ref='T-no-plate-000001'),
                      ev('gate_log', ago(1), {'plate': 'SYN 1001', 'action': 'Party Time'}, ref='T-bad-action-00001'), good])
    codes = {x['client_ref']: x.get('code') or x['status'] for x in res['data']['results']}
    check('bad events are rejected with a reason, and the good one after them is still accepted',
          codes['T-unknown-type-0001'] == 'UNKNOWN_TYPE' and codes['T-no-plate-000001'] == 'MISSING_PLATE'
          and codes['T-bad-action-00001'] == 'INVALID_ACTION' and codes[good['client_ref']] == 'accepted', codes)

    # --- incidents
    inc = ev('incident', ago(hours=1), {'plateNumber': 'SYN 7777', 'driverName': 'Suspicious Driver', 'reason': 'Refused inspection',
                                       'gatePoint': 'Gate 1 (Main Ingress)', 'officer': 'Officer Reyes', 'notes': 'Left before check'})
    code, res = sync([inc])
    r = res['data']['results'][0]
    check('offline incident report accepted', r['status'] == 'accepted' and r['caseNumber'], res)
    code, res = sync([inc])
    check('  ...and resending it does not open a second case', res['data']['results'][0]['status'] == 'duplicate'
          and res['data']['results'][0]['caseNumber'] == r['caseNumber'], res)
    check('  ...one Held case', len(open_incidents_for(admin, 'SYN 7777')) == 1, open_incidents_for(admin, 'SYN 7777'))

    # --- the live endpoints are idempotent too (reply lost, app retries)
    ref = 'T-live-retry-000001'
    body = {'plate': 'SYN 1004', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': drv, 'client_ref': ref}
    code, res = call('POST', 'logs.php', body, guard)
    check('live log with a client_ref -> 201', code == 201, res)
    before = len(logs_for('SYN 1004'))
    code, res = call('POST', 'logs.php', body, guard)
    check('the same live log again -> 200 "already recorded", nothing added', code == 200 and res['data']['duplicate'] is True and len(logs_for('SYN 1004')) == before, res)
    code, res = call('POST', 'incidents.php', {'plateNumber': 'SYN 7778', 'reason': 'Test', 'client_ref': 'T-live-incident-01'}, guard)
    code2, res2 = call('POST', 'incidents.php', {'plateNumber': 'SYN 7778', 'reason': 'Test', 'client_ref': 'T-live-incident-01'}, guard)
    check('the same live incident again -> 200, one case', code == 201 and code2 == 200 and res2['data']['caseNumber'] == res['data']['caseNumber'], (res, res2))

    # --- the web app can tell which rows arrived late
    live = [l for l in call('GET', 'logs.php?limit=200', token=admin)[1]['data'] if l['plateNumber'] == 'NDK4821' or l['plateNumber'] == 'NDK 4821']
    check('live rows have no sync time; offline rows do', all(not l.get('syncedAt') for l in live) and bool(logs_for('SYN 1001')[0].get('syncedAt')), live[:1])

    # --- an unexpected server error is a "retry", never a permanent rejection
    register('SYN 4001', 'Rita Retry')
    t = ago(minutes=15)
    failing = ev('gate_log', t, dict(entry('SYN 4001'), _test_fail='before'), ref='T-fail-before-0001')
    code, res = sync([failing])
    r = res['data']['results'][0]
    check('an unexpected error while processing -> "retry" (not rejected)', code == 200 and r['status'] == 'retry' and r['code'] == 'TEMPORARY_ERROR', res)
    check('  ...nothing was recorded', logs_for('SYN 4001') == [], logs_for('SYN 4001'))
    code, res = sync([dict(failing, payload=entry('SYN 4001'))])
    check('  ...the same event sent again (no failure now) is accepted', res['data']['results'][0]['status'] == 'accepted' and len(logs_for('SYN 4001')) == 1, res)

    raced = ev('gate_log', ago(minutes=12), dict(entry('SYN 4001', action='Exit Approved', gate_type='Egress'), _test_fail='after_commit'), ref='T-fail-after-00001')
    code, res = sync([raced])
    r = res['data']['results'][0]
    check('an error AFTER the event was stored (concurrent send won) -> "duplicate", not a failure', r['status'] == 'duplicate' and r.get('id'), res)
    check('  ...and it was recorded exactly once', len([l for l in logs_for('SYN 4001') if l['action'] == 'Exit Approved']) == 1, logs_for('SYN 4001'))
    code, res = sync([dict(raced, payload=exit_('SYN 4001'))])
    check('  ...resending it is still a duplicate', res['data']['results'][0]['status'] == 'duplicate', res)

    # --- editing a vehicle can never change whether it is inside
    inside = register('SYN 4002', 'Ivan Inside')
    drv2 = int(vehicle('SYN 4002')['authorizedDrivers'][0]['id'])
    call('POST', 'logs.php', {'plate': 'SYN 4002', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': drv2}, guard)
    check('(setup) vehicle is inside', vehicle('SYN 4002')['status'] == 'Inside Campus', vehicle('SYN 4002')['status'])
    for bad_status in ('', 'Outside', 'Inside', 'Exited'):
        code, res = call('PUT', 'vehicles.php', {'id': inside['id'], 'ownerPhone': '0917 999 0000', 'status': bad_status}, admin)
    v = vehicle('SYN 4002')
    check('an edit that sends a status (even an empty one) does not change it', code == 200 and v['status'] == 'Inside Campus', v['status'])
    check('  ...while the other fields in the same edit are saved', v['ownerPhone'] == '0917 999 0000', v)
    code, res = call('GET', 'oncampus.php', token=guard)
    check('  ...and the vehicle is still on the On Campus list', any(x['plateNumber'] == 'SYN 4002' for x in res['data']['vehicles']), res['data']['counts'])


def main():
    if '--fresh' in sys.argv and os.path.exists(SQLITE_DB):
        os.remove(SQLITE_DB)
        print(f'Deleted local SQLite DB: {SQLITE_DB}')
    admin = test_auth()
    test_staff_accounts(admin)
    test_lockout()
    test_mobile_compat()

    # A clean guard account for the pass tests
    code, res = call('POST', 'users.php', {'username': 'guard.qa', 'full_name': 'QA Guard', 'role': 'guard', 'badge_number': 'NCST-SEC-99'}, admin)
    temp = res['data']['tempPassword']
    qa = login('guard.qa', temp)[1]['data']['token']
    call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Guard-QA-2026'}, qa)

    test_signed_passes(admin)
    test_legacy_passes(admin)
    test_gate_flow(admin)
    test_violations(admin)
    test_overnight(admin)
    test_visitor_passes(admin)
    test_student_portal(admin)
    test_visitor_items_and_on_campus(admin)
    test_scheduled_and_revoked_passes(admin)
    test_vip_passes(admin)
    test_offline_sync(admin)
    print(f'\n{passed} passed, {failed} failed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
