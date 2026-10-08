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


AUTO_PAY = True  # newly registered vehicles are Unpaid; most tests just need a working pass, so the cashier "pays" them


AUTO_REASON = True  # sensitive admin actions need a written reason; older tests just supply a generic one


def call(method, path, body=None, token=None, headers=None):
    if AUTO_REASON:
        if isinstance(body, dict):
            if path == 'vehicles.php' and method in ('POST', 'PUT') and (str(body.get('passClass', '')).lower() in ('vip', 'standard') or 'passValidUntil' in body):
                body.setdefault('reason', 'Test: automated reason')
            if path == 'passes.php':
                body.setdefault('reason', 'Test: automated reason')
        if method == 'DELETE' and path.startswith('vehicles.php') and 'reason=' not in path:
            path += '&reason=Test+cleanup'
    code, res = _call(method, path, body, token, headers)
    if (AUTO_PAY and method == 'POST' and path == 'vehicles.php' and code == 201
            and res.get('data', {}).get('paymentStatus') == 'Unpaid'):
        c2, paid = _call('POST', 'payments.php', {'action': 'cash', 'vehicleId': res['data']['id']}, token)
        if c2 == 201:
            account = res['data'].get('studentAccount')
            res['data'] = paid['data']['vehicle']
            res['data']['studentAccount'] = account
    return code, res


def _call(method, path, body=None, token=None, headers=None):
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
    code, res = call('POST', 'logs.php', {'plateNumber': 'NDK 4821', 'driverName': 'Juan Dela Cruz', 'action': 'Entry Recorded'}, headers=SCANNER)
    check('mobile entry for suspended vehicle also refused', code == 403, res)
    code, res = call('POST', 'logs.php', {'plate': 'NDK 4821', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': drivers['Juan Dela Cruz']}, guard)
    check('exit for suspended vehicle still allowed', code == 201, res)
    call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)


def test_violations(admin):
    section('Violations (hold until resolved, no strikes)')
    import sqlite3
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'STR 3001', 'ownerName': 'Rico Santos', 'ownerIdNumber': 'NCST-2024-3001',
                                             'authorizedDrivers': [{'fullName': 'Rico Santos', 'relationship': 'Self (Owner)'}]}, admin)
    veh = res['data']
    payload = veh['qrPayload']
    driver_id = int(veh['authorizedDrivers'][0]['id'])
    check('vehicle output has no strike counter', 'warningCount' not in veh, sorted(k for k in veh if 'arn' in k))

    def issue(token, type_='Parking in Fire Lane / Restricted Zone', notes='Observed by patrol', **extra):
        return call('POST', 'violations.php', {'vehicle_id': veh['id'], 'type': type_, 'notes': notes, **extra}, token)

    code, res = issue(guard, type_='Speeding Wildly')
    check('unknown violation type rejected -> 400', code == 400, res)
    code, res = issue(guard, type_='Other', notes='')
    check('"Other" requires notes -> 400', code == 400, res)
    code, res = call('POST', 'violations.php', {'vehicle_id': veh['id'], 'type': 'Parking in Fire Lane / Restricted Zone'})
    check('issuing a violation requires sign-in -> 401', code == 401, code)

    # A guard can issue a violation; the vehicle is on hold
    code, res = issue(guard, severity='Warning')  # an old client still sending "severity" gets a violation, never a warning
    check('guard issues a violation -> 201, vehicle on hold', code == 201 and res['data']['onHold'] and res['data']['vehicle']['isBanned']
          and res['data']['vehicle']['registrationStatus'] == 'Suspended' and res['data']['violation']['status'] == 'Pending', res)
    check('no strike fields anywhere in the response', 'strikes' not in res['data'] and 'warningCount' not in res['data']['vehicle']
          and 'severity' not in res['data']['violation'], res['data'])
    first_id = res['data']['violation']['id']
    check('the hold opens a Held incident', any(i['reason'] == 'Parking in Fire Lane / Restricted Zone' for i in open_incidents_for(admin, 'STR 3001')), '')

    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('entry -> BANNED (violation hold), denied, logged', v.get('result') == 'BANNED' and not v['accepted'] and v['autoLogged'], v)
    check('  ...message says violation hold', 'VIOLATION' in v['message'].upper() and 'violation' in v['reason'], v)
    code, res = call('POST', 'logs.php', {'plate': 'STR 3001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver_id}, guard)
    check('entry refused server-side -> 403', code == 403 and res['data']['code'] == 'VEHICLE_BANNED', res)

    # ... and it cannot leave either
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Inside Campus' WHERE id = ?", (veh['id'],))
    db.commit()
    db.close()
    code, v = verify({'qr_code': payload, 'gate_type': 'Egress'}, guard)
    check('exit -> denied while the violation is pending', v.get('result') == 'BANNED' and not v['accepted'] and v['autoLogged'], v)
    code, res = call('POST', 'logs.php', {'plate': 'STR 3001', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': driver_id}, guard)
    check('exit approval refused server-side -> 403', code == 403 and res['data']['code'] == 'VEHICLE_BANNED', res)

    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'action': 'toggle_status'}, admin)
    check('suspend/activate toggle cannot lift the hold -> 409', code == 409, res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'registrationStatus': 'Active'}, admin)
    check('editing registration to Active cannot lift the hold -> 409', code == 409, res)
    inc = [i for i in open_incidents_for(admin, 'STR 3001') if i['reason'] == 'Parking in Fire Lane / Restricted Zone'][0]
    code, res = call('PUT', 'incidents.php', {'id': inc['id'], 'notes': 'cleared'}, admin)
    check('clearing the incident directly is refused -> 409', code == 409 and res['data']['code'] == 'VIOLATION_PENDING', res)

    # A second violation: both must be resolved
    code, res = issue(admin, type_='Reckless / Prohibited Driving on Campus', notes='Overspeeding near the chapel')
    second_id = res['data']['violation']['id']
    check('a second violation is accepted while on hold', code == 201, res)
    _, res = call('GET', f"violations.php?vehicle_id={veh['id']}&status=Pending", token=guard)
    check('guard can list the pending violations', len(res['data']) == 2, res)

    code, res = call('PUT', 'violations.php', {'violation_id': first_id, 'action': 'resolve', 'notes': 'x'}, guard)
    check('guard cannot resolve -> 403', code == 403, code)
    code, res = call('PUT', 'violations.php', {'violation_id': first_id, 'action': 'resolve', 'notes': ''}, admin)
    check('resolution notes are mandatory -> 400', code == 400, res)
    code, res = call('PUT', 'violations.php', {'vehicle_id': veh['id'], 'action': 'reset', 'notes': 'x'}, admin)
    check('the old "reset strikes" action no longer exists -> 400', code == 400, res)
    code, res = call('PUT', 'violations.php', {'violation_id': first_id, 'action': 'resolve', 'notes': 'Cleared at the Security Office (OR #1234)'}, admin)
    check('resolving one of two keeps the hold', code == 200 and res['data']['holdLifted'] is False and res['data']['vehicle']['isBanned'], res)
    code, v = verify({'qr_code': payload, 'gate_type': 'Egress'}, guard)
    check('  ...still cannot leave', v.get('result') == 'BANNED' and not v['accepted'], v)
    code, res = call('PUT', 'violations.php', {'violation_id': second_id, 'action': 'resolve', 'notes': 'Apology letter and fine settled'}, admin)
    check('resolving the last one lifts the hold', code == 200 and res['data']['holdLifted'] and not res['data']['vehicle']['isBanned']
          and res['data']['vehicle']['registrationStatus'] == 'Active', res)
    check('incidents closed with the violations', not open_incidents_for(admin, 'STR 3001'), open_incidents_for(admin, 'STR 3001'))
    code, v = verify({'qr_code': payload, 'gate_type': 'Egress'}, guard)
    check('the vehicle can leave after resolution', v.get('result') == 'VALID' and v['accepted'], v)
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Outside' WHERE id = ?", (veh['id'],))
    db.commit()
    db.close()
    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('...and enter again', v.get('result') == 'VALID' and v['accepted'], v)
    code, res = call('PUT', 'violations.php', {'violation_id': first_id, 'action': 'resolve', 'notes': 'again'}, admin)
    check('resolving twice -> 409', code == 409, res)

    # Dismissing a violation issued by mistake lifts the hold
    code, res = issue(guard, notes='Wrong plate noted by patrol')
    vid = res['data']['violation']['id']
    code, res = call('PUT', 'violations.php', {'violation_id': vid, 'action': 'dismiss', 'notes': 'Issued to the wrong vehicle'}, admin)
    check('dismissing a mistaken violation lifts the hold', code == 200 and res['data']['holdLifted'] and not res['data']['vehicle']['isBanned'], res)
    _, res = call('GET', 'violations.php?status=Pending&plate=STR3001', token=guard)
    check('nothing pending afterwards', isinstance(res['data'], list) and len(res['data']) == 0, res)

    # Records left by the retired strike system are history only: not listed, never blocking
    db = sqlite3.connect(SQLITE_DB)
    db.execute("INSERT INTO vehicle_violations (vehicle_id, plate_number, violation_type, severity, logged_by, status, counts_as_strike, created_at) "
               "VALUES (?, 'STR 3001', 'Parking in Fire Lane / Restricted Zone', 'Warning', 'old', 'Pending', 1, '2026-09-01 08:00:00')", (veh['id'],))
    db.commit()
    db.close()
    _, res = call('GET', 'violations.php?status=Pending&plate=STR3001', token=admin)
    check('an old pending warning row is not listed', len(res['data']) == 0, res)
    code, v = verify({'qr_code': payload, 'gate_type': 'Ingress'}, guard)
    check('  ...and does not block or warn', v.get('result') == 'VALID' and v['accepted'] and not any('trike' in w for w in v['warnings']), v)


def test_overnight(admin):
    section('Overtime & overnight parking list (staff decide, nothing automatic)')
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
    check('list has no strike counter', 'warningCount' not in items['OVT 2002'] and items['OVT 2002']['onHold'] is False, items['OVT 2002'])

    code, res = report('2026-09-20 23:00:00', 'POST')
    items = {i['plateNumber']: i for i in res['data']['items']}
    check('after curfew: both vehicles are listed as overnight', items['OVN 1001']['category'] == 'overnight' and items['OVT 2002']['category'] == 'overnight', res['data'])
    check('the run only lists: no violation was recorded', all(not i['flaggedThisNight'] and not i['onHold'] for i in items.values()), items)
    _, res = call('GET', f'violations.php?vehicle_id={night_id}', token=admin)
    check('  ...nothing in the violations ledger', res['data'] == [], res['data'])

    code, res = report('2026-09-20 23:00:00', 'POST', {'vehicle_id': over_id})
    check('guard issues a violation for a listed vehicle -> 201, on hold', code == 201 and res['data']['onHold'] is True, res)
    _, res = call('GET', f'violations.php?vehicle_id={over_id}', token=admin)
    check('  ...recorded as an overnight violation by the guard', len(res['data']) == 1 and res['data'][0]['violationType'].startswith('Overnight')
          and res['data'][0]['loggedBy'] != 'System (Overnight Check)' and res['data'][0]['status'] == 'Pending', res['data'])
    code, res = report('2026-09-20 23:30:00')
    items = {i['plateNumber']: i for i in res['data']['items']}
    check('list shows it issued and on hold; the other vehicle untouched', items['OVT 2002']['flaggedThisNight'] and items['OVT 2002']['onHold']
          and not items['OVN 1001']['onHold'], items)
    code, res = report('2026-09-20 23:45:00', 'POST', {'vehicle_id': over_id})
    check('issuing twice for the same night -> 409', code == 409 and res['data']['code'] == 'ALREADY_FLAGGED', res)
    code, res = report('2026-09-21 01:00:00')
    check('after midnight it is still the same night', {i['plateNumber']: i['flaggedThisNight'] for i in res['data']['items']}['OVT 2002'] is True, res['data'])
    code, res = report('2026-09-21 22:30:00')
    check('next night -> can be issued again', {i['plateNumber']: i['flaggedThisNight'] for i in res['data']['items']}['OVT 2002'] is False, res['data'])

    # A vehicle that exits is no longer reported
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Outside' WHERE id = ?", (night_id,))
    db.commit()
    db.close()
    code, res = report('2026-09-22 23:00:00', 'POST')
    check('exited vehicle is not listed', 'OVN 1001' not in {i['plateNumber'] for i in res['data']['items']}, res['data'])
    code, res = report('2026-09-22 23:00:00', 'POST', {'vehicle_id': night_id})
    check('issuing for a vehicle that is not listed -> 404', code == 404, res)

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
    check('pass is revoked automatically after exit, with entry and exit times', res['data']['status'] == 'Revoked' and res['data']['entryTime'] and res['data']['exitTime'], res)
    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('used pass cannot enter again -> REVOKED', v.get('result') == 'REVOKED', v)
    code, v = verify({'qr_code': vp['qrPayload'], 'gate_type': 'Egress'}, guard)
    check('used pass cannot exit again either', v.get('result') == 'REVOKED', v)
    code, res = call('POST', 'logs.php', {'plate': 'VIS 9001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': vp['id']}, guard)
    check('server refuses re-entry on a used pass -> 403', code == 403 and res['data']['code'] == 'PASS_USED', res)
    check('  ...and says it was revoked when the visitor exited', 'revoked when the visitor exited' in res['message'], res)

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
    check('second vehicle for the same ID is refused (one vehicle per ID)', code == 409 and res['data']['code'] == 'OWNER_HAS_VEHICLE'
          and res['data']['plateNumber'] == 'STU 7001', res)
    # An owner who already had two vehicles before that rule existed (legacy data) must keep working: insert it directly
    import sqlite3
    db = sqlite3.connect(SQLITE_DB)
    cur = db.execute("INSERT INTO vehicles (plate_number, make_model_color, owner_name, owner_id_number) VALUES ('STU 7002', 'Legacy second car', 'Sam Student', ?)", (owner_id,))
    db.execute("INSERT INTO authorized_drivers (vehicle_id, full_name, relationship) VALUES (?, 'Sam Student', 'Self (Owner)')", (cur.lastrowid,))
    db.commit()
    db.close()
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
          and 'warningCount' not in own and 'isBanned' in own and 'ownerPhone' not in own, own)
    code, v = verify({'qr_code': own['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('pass shown in the student portal verifies at the gate', v.get('result') == 'VALID', v)
    code, res = call('GET', 'student.php?action=vehicles&owner_id_number=NCST-2024-0001', token=tok)
    check('client-supplied owner ID is ignored', sorted(x['plateNumber'] for x in res['data']) == ['STU 7001', 'STU 7002'], res)

    call('POST', 'logs.php', {'plate': 'STU 7001', 'action': 'Entry Recorded', 'gate_type': 'Ingress',
                              'driver_id': int(own['authorizedDrivers'] and call('GET', 'vehicles.php?plate=STU7001', token=admin)[1]['data']['authorizedDrivers'][0]['id'])}, guard)
    code, res = call('GET', 'student.php?action=activity', token=tok)
    check('activity: own gate history', code == 200 and res['data'] and all(a['plateNumber'].startswith('STU') for a in res['data']), res)

    code, res = call('GET', 'student.php?action=me', token=tok)
    check('summary: nothing on hold yet', res['data']['summary']['openViolations'] == 0 and res['data']['summary']['banned'] == 0
          and 'strikes' not in res['data']['summary'], res['data']['summary'])
    call('POST', 'violations.php', {'plate': 'STU 7001', 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'Blocking hydrant'}, guard)
    code, res = call('GET', 'student.php?action=violations', token=tok)
    check('violations: own violation visible, no severity / strike fields', code == 200 and len(res['data']) == 1 and res['data'][0]['plateNumber'] == 'STU 7001'
          and res['data'][0]['status'] == 'Pending' and 'severity' not in res['data'][0] and 'countsAsStrike' not in res['data'][0], res)
    code, res = call('GET', 'student.php?action=me', token=tok)
    check('summary: one open violation, one vehicle on hold', res['data']['summary']['openViolations'] == 1 and res['data']['summary']['banned'] == 1, res['data']['summary'])
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    check('vehicle shows the hold and has no strike counter', [x for x in res['data'] if x['plateNumber'] == 'STU 7001'][0]['isBanned'] is True
          and 'warningCount' not in res['data'][0], res['data'][0])

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
    times = [x['entryTime'] for x in res['data']['vehicles'] if x['entryTime']]
    check('on-campus vehicles are in arrival order (earliest entry first)', times == sorted(times), times)
    visitor_times = [x['entryTime'] for x in res['data']['visitors']]
    check('on-campus visitors are in arrival order too', visitor_times == sorted(visitor_times), visitor_times)
    check('entries carry their gate log id (for the CCTV clip)', isinstance(row['entryLogId'], int)
          and all(isinstance(x['entryLogId'], int) for x in res['data']['visitors'] if x['plateNumber'] == 'EVT4040'), res['data'])

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
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'x'}, guard)
    check('a violation against a VIP (guard) is refused -> 409', code == 409 and res['data']['code'] == 'VIP_EXEMPT', res)
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Reckless / Prohibited Driving on Campus', 'notes': 'x'}, admin)
    check('a violation against a VIP (admin) is refused -> 409', code == 409 and res['data']['code'] == 'VIP_EXEMPT', res)

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
    listed = {i['plateNumber'] for i in res['data']['items']}
    check('the list-only run still skips the VIP', 'VIP 0002' in listed and 'VIP 0001' not in listed, listed)
    std2 = call('GET', 'vehicles.php?plate=VIP0002', token=admin)[1]['data']
    code, res = call('POST', night, {'vehicle_id': std2['id']}, guard)
    check('a violation can be issued for the listed Standard vehicle', code == 201 and res['data']['onHold'], res)
    pending = call('GET', f"violations.php?vehicle_id={std2['id']}&status=Pending", token=admin)[1]['data']
    call('PUT', 'violations.php', {'violation_id': pending[0]['id'], 'action': 'resolve', 'notes': 'Owner reached; cleared (test cleanup)'}, admin)
    code, res = call('POST', night, {'vehicle_id': vip['id']}, guard)
    check('a manual overnight flag on a VIP -> 404 (not listed)', code == 404, res)
    code, res = call('GET', 'oncampus.php?now=' + urllib.parse.quote('2026-09-21 09:00:00'), token=guard)
    rows = {v['plateNumber']: v for v in res['data']['vehicles']}
    check('On Campus Now shows the VIP, with no time flag', rows['VIP 0001']['isVip'] is True and rows['VIP 0001']['timeFlag'] is None, rows.get('VIP 0001'))
    check('  ...while the Standard vehicle is flagged overnight', rows['VIP 0002']['timeFlag'] == 'overnight', rows.get('VIP 0002'))
    _, res = call('GET', 'vehicles.php?plate=VIP0001', token=admin)
    check('the VIP has no violation hold', res['data']['isBanned'] is False, res['data'])

    # --- a banned vehicle cannot be made VIP; withdrawing VIP restores the rules
    code, res = register('VIP 0003', 'Ban Candidate')
    call('POST', 'violations.php', {'plate': 'VIP 0003', 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'x'}, guard)
    _, res = call('GET', 'vehicles.php?plate=VIP0003', token=admin)
    check('(setup) a violation puts the vehicle on hold', res['data']['isBanned'] is True, res['data'])
    banned_id = res['data']['id']
    code, res = call('PUT', 'vehicles.php', {'id': banned_id, 'passClass': 'VIP'}, admin)
    check('a banned vehicle cannot be made VIP -> 409', code == 409 and res['data']['code'] == 'VEHICLE_BANNED', res)

    code, res = call('PUT', 'vehicles.php', {'id': std['id'], 'passClass': 'VIP'}, admin)
    check('admin makes an existing vehicle VIP', code == 200 and res['data']['isVip'] is True and res['data']['vipGrantedBy'], res)
    code, res = call('PUT', 'vehicles.php', {'id': std['id'], 'passClass': 'Standard'}, admin)
    check('admin withdraws VIP', code == 200 and res['data']['isVip'] is False and res['data']['vipGrantedBy'] is None, res)
    code, res = call('PUT', 'vehicles.php', {'id': vip['id'], 'passClass': 'Standard'}, admin)
    code, res = call('POST', 'violations.php', {'plate': 'VIP 0001', 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'x'}, guard)
    check('once VIP is withdrawn the vehicle can get a violation again', code == 201, res)
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

    owners = {}

    def register(plate, owner):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': owner, 'ownerIdNumber': 'ID-' + plate.replace(' ', ''),
                                                 'authorizedDrivers': [{'fullName': owner, 'relationship': 'Self (Owner)'}]}, admin)
        owners[plate] = owner
        return res['data']

    def vehicle(plate):
        return call('GET', 'vehicles.php?plate=' + plate.replace(' ', ''), token=admin)[1]['data']

    def logs_for(plate, limit=50):
        return [l for l in call('GET', f'logs.php?limit=200', token=admin)[1]['data'] if l['plateNumber'] == plate][:limit]

    def entry(plate, **extra):
        return dict({'plate': plate, 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': owners.get(plate, 'Guard-checked Driver')}, **extra)

    def exit_(plate, **extra):
        return dict({'plate': plate, 'action': 'Exit Approved', 'gate_type': 'Egress', 'driverName': owners.get(plate, 'Guard-checked Driver')}, **extra)

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
    call('POST', 'violations.php', {'plate': 'SYN 1005', 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'x'}, guard)
    check('(setup) vehicle is on violation hold', vehicle('SYN 1005')['isBanned'] is True, vehicle('SYN 1005'))
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
    check('  ...the pass records the real exit time and is revoked', exit_time == manila_str(ago(minutes=30)) and res['data']['status'] == 'Revoked', res['data'])
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

    # --- visitor passes issued OFFLINE on the phone
    manila_day = lambda t: t.astimezone(manila).strftime('%Y%m%d')

    def pass_payload(plate, code, **extra):
        return dict({'passId': code, 'pass_code': code, 'visitorName': 'Olga Offline', 'visitor_name': 'Olga Offline',
                     'plateNumber': plate, 'plate': plate, 'contactNumber': '0917 000 4444', 'purposeOfVisit': 'Enrollment',
                     'personToVisit': 'Registrar', 'vehicleModel': 'Red Vios', 'registeredByGuard': 'Officer Reyes',
                     'items': [{'name': 'Boxes', 'quantity': 3}]}, **extra)

    t_pass = ago(minutes=45)
    code_a = 'VP-' + manila_day(t_pass) + '-K7M2QX'
    code, res = sync([ev('visitor_pass', t_pass, pass_payload('SYN 5001', code_a), ref='T-offline-pass-0001')])
    r = res['data']['results'][0]
    check('an offline visitor pass is accepted, keeping the phone\'s pass code', r['status'] == 'accepted' and r['passCode'] == code_a and r['id'], res)
    code, res = call('GET', f'visitors.php?id={r["id"]}', token=guard)
    vp = res['data']
    check('  ...it is valid on the day it was ISSUED, not the day it synced', vp['validDate'] == t_pass.astimezone(manila).strftime('%Y-%m-%d'), vp)
    check('  ...created_at is the real issue time; synced_at marks the late arrival', vp['createdAt'] == manila_str(t_pass)
          and vp['syncedAt'] and vp['syncedAt'] > vp['createdAt'], vp)
    check('  ...the visitor, plate, items and issuing guard are kept', vp['visitorName'] == 'Olga Offline' and vp['plateNumber'] == 'SYN5001'
          and [(i['name'], i['quantity']) for i in vp['items']] == [('Boxes', 3)] and 'Officer Reyes' in (vp['createdBy'] or ''), vp)
    check('  ...and it starts Active, with a server-signed QR available to staff', vp['status'] == 'Active' and 'sig' in json.loads(vp['qrPayload']), vp)

    # the entry the guard logged right after issuing the pass: sent in the wrong order, still lands after the pass
    code_b = 'VP-' + manila_day(ago(minutes=30)) + '-P4T9WZ'
    t_entry = ago(minutes=29)
    entry_first = ev('gate_log', t_entry, entry('SYN 5002', driverName='Olga Offline'), ref='T-offline-entry-0002')
    pass_second = ev('visitor_pass', ago(minutes=30), pass_payload('SYN 5002', code_b), ref='T-offline-pass-0002')
    code, res = sync([entry_first, pass_second])
    got = {x['client_ref']: x for x in res['data']['results']}
    check('an entry listed BEFORE its pass in the same batch: both accepted, no flags',
          got['T-offline-entry-0002']['status'] == 'accepted' and got['T-offline-entry-0002']['flags'] == [] and got['T-offline-pass-0002']['status'] == 'accepted', res)
    code, res = call('GET', f'visitors.php?id={got["T-offline-pass-0002"]["id"]}', token=guard)
    check('  ...the pass records the entry at the real time and the visitor is inside',
          res['data']['entryTime'] == manila_str(t_entry) and res['data']['isInside'] is True, res['data'])

    # sent twice, or clashing
    code, res = sync([pass_second])
    check('sending the same pass again -> duplicate', res['data']['results'][0]['status'] == 'duplicate', res)
    code, res = sync([ev('visitor_pass', ago(minutes=30), pass_payload('SYN 5099', code_b), ref='T-offline-pass-0003')])
    check('the same pass code on a different vehicle -> rejected CODE_CONFLICT', res['data']['results'][0]['code'] == 'CODE_CONFLICT', res)
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5001', 'VP-' + manila_day(ago(minutes=20)) + '-ZZ22ZZ'), ref='T-offline-pass-0004')])
    r = res['data']['results'][0]
    if manila_day(ago(minutes=20)) == manila_day(t_pass):  # not when the two events straddle Manila midnight
        check('a second pass for the same plate and day (another phone) -> duplicate, the existing pass is used',
              r['status'] == 'duplicate' and r['passCode'] == code_a, res)

    # a registered vehicle uses its own pass
    register('SYN 5003', 'Reg Owner')
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5003', 'VP-' + manila_day(ago(minutes=20)) + '-REG333'), ref='T-offline-pass-0005')])
    r = res['data']['results'][0]
    check('an offline pass for a REGISTERED vehicle: no pass created, flagged, security hold opened',
          r['status'] == 'accepted' and r['flags'] == ['PLATE_REGISTERED'] and r['caseNumber'], res)
    code, res = call('GET', 'visitors.php?q=SYN5003', token=guard)
    check('  ...and there is no visitor pass for it', code == 404, code)
    check('  ...the hold explains why', any(i['reason'] == 'Offline visitor pass for a registered vehicle' for i in open_incidents_for(admin, 'SYN 5003')),
          open_incidents_for(admin, 'SYN 5003'))

    # bad data is refused with a reason
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5004', 'VP-' + manila_day(ago(minutes=20)) + '-NONAME', visitorName='', visitor_name=''), ref='T-offline-pass-0006')])
    check('an offline pass with no visitor name -> rejected MISSING_FIELDS', res['data']['results'][0]['code'] == 'MISSING_FIELDS', res)
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5004', 'VP-' + manila_day(ago(minutes=20)) + '-BADQTY', items=[{'name': 'Chairs', 'quantity': 0}]), ref='T-offline-pass-0007')])
    check('an item with quantity 0 -> rejected INVALID_ITEMS', res['data']['results'][0]['code'] == 'INVALID_ITEMS', res)
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5004', 'VP-' + manila_day(ago(minutes=20)) + '-MANYIT', items=[{'name': f'Item {i}', 'quantity': 1} for i in range(21)]), ref='T-offline-pass-0008')])
    check('more than 20 items -> rejected INVALID_ITEMS', res['data']['results'][0]['code'] == 'INVALID_ITEMS', res)
    code, res = call('GET', 'visitors.php?q=SYN5004', token=guard)
    check('  ...and nothing was created for the refused passes', code == 404, code)
    code, res = sync([ev('visitor_pass', ago(minutes=20), pass_payload('SYN 5005', '??', ), ref='T-offline-pass-0009')])
    r = res['data']['results'][0]
    check('a pass with an unusable code still works: the server assigns one', r['status'] == 'accepted' and r['passCode'].startswith('VP-'), res)

    # the pass works at any gate once synced (only when it was issued today, to stay safe around midnight)
    if t_pass.astimezone(manila).date() == datetime.datetime.now(manila).date():
        code, v = verify({'qr_code': json.dumps({'passId': code_a, 'plateNumber': 'SYN5001'}), 'gate_type': 'Ingress'}, guard)
        check('after syncing, the phone-made QR verifies at the web gate (found by its pass code)',
              v.get('accepted') is True and v['visitor']['passCode'] == code_a, v)
    code, res = call('GET', 'visitors.php?date=' + t_pass.astimezone(manila).strftime('%Y-%m-%d'), token=guard)
    check('the day list shows the offline pass with its sync time', any(x['passCode'] == code_a and x['syncedAt'] for x in res['data']), res)

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


def test_loophole_fixes(admin):
    """Gate loopholes closed: unpaid / expired entries, free-text drivers, deleting history, re-pricing."""
    global AUTO_PAY
    import datetime, sqlite3
    section('Gate loopholes closed (payment, expiry, drivers, deletion, re-pricing)')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def reg(plate, owner_id, vtype='4-Wheel', **extra):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': 'Lia Loophole', 'ownerIdNumber': owner_id, 'vehicleType': vtype,
                                                 'authorizedDrivers': [{'fullName': 'Lia Loophole', 'relationship': 'Self (Owner)', 'licenseNo': 'N/A'}], **extra}, admin)
        return res['data']

    def pay(vehicle_id):
        return call('POST', 'payments.php', {'action': 'cash', 'vehicleId': vehicle_id}, admin)

    def phone_entry(plate, driver='Lia Loophole', action='Entry Recorded', **extra):
        gate = 'Egress' if action == 'Exit Approved' else 'Ingress'
        return call('POST', 'logs.php', {'plateNumber': plate, 'driverName': driver, 'action': action, 'gate_type': gate, **extra}, headers=SCANNER)

    def set_status(vehicle_id, status):
        db = sqlite3.connect(SQLITE_DB)
        db.execute("UPDATE vehicles SET status = ? WHERE id = ?", (status, vehicle_id))
        db.commit()
        db.close()

    # --- 1. unpaid vehicles cannot be admitted, whatever the client does
    u = reg('LPX 1001', 'LP-X1')
    code, res = phone_entry('LPX 1001')
    check('phone entry of an UNPAID vehicle (plate only) -> 403 VEHICLE_UNPAID', code == 403 and res['data']['code'] == 'VEHICLE_UNPAID', res)
    code, res = call('POST', 'logs.php', {'plate': 'LPX 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': int(u['authorizedDrivers'][0]['id'])}, guard)
    check('web gate monitor entry of an UNPAID vehicle -> 403 VEHICLE_UNPAID', code == 403 and res['data']['code'] == 'VEHICLE_UNPAID', res)
    code, v = verify({'plate': 'LPX 1001', 'gate_type': 'Ingress'}, guard)
    check('manual plate lookup says UNPAID', v.get('result') == 'UNPAID' and not v['accepted'], v)
    code, res = pay(u['id'])
    code, res = phone_entry('LPX 1001')
    check('after payment the same entry is recorded', code == 201, res)

    # --- 2. expired passes cannot be admitted (every lookup path), but may still leave
    e = reg('LPX 2002', 'LP-X2')
    pay(e['id'])
    call('PUT', 'vehicles.php', {'id': e['id'], 'passValidUntil': '2025-01-01'}, admin)
    code, res = phone_entry('LPX 2002')
    check('phone entry with an EXPIRED pass -> 403 PASS_EXPIRED', code == 403 and res['data']['code'] == 'PASS_EXPIRED', res)
    code, v = verify({'plate': 'LPX 2002', 'gate_type': 'Ingress'}, guard)
    check('manual plate lookup says EXPIRED (not MANUAL / accepted)', v.get('result') == 'EXPIRED' and not v['accepted'], v)
    set_status(e['id'], 'Inside Campus')
    code, res = phone_entry('LPX 2002', action='Exit Approved')
    check('an expired pass may still leave campus', code == 201, res)
    call('PUT', 'vehicles.php', {'id': e['id'], 'passValidUntil': '2026-12-31'}, admin)
    code, res = phone_entry('LPX 2002')
    check('entry works again once the pass is valid', code == 201, res)

    # --- 3. only a listed driver may be admitted, from the phone too
    d = reg('LPX 3003', 'LP-X3')
    pay(d['id'])
    code, res = phone_entry('LPX 3003', driver='Totally Unlisted Person')
    check('phone entry by an unlisted driver -> 400 DRIVER_NOT_AUTHORIZED', code == 400 and res['data']['code'] == 'DRIVER_NOT_AUTHORIZED', res)
    code, res = phone_entry('LPX 3003', driver='')
    check('phone entry with no driver -> 400 DRIVER_CONFIRMATION_REQUIRED', code == 400 and res['data']['code'] == 'DRIVER_CONFIRMATION_REQUIRED', res)
    code, res = phone_entry('LPX 3003', driver='Unverified')
    check('"Unverified" is not a driver either -> 400', code == 400, res)
    code, res = phone_entry('LPX 3003', driver='  lia   LOOPHOLE ')
    check('a listed driver (case / spacing ignored) is admitted and verified', code == 201, res)
    _, logs = call('GET', 'logs.php?limit=5', token=admin)
    check('  ...logged as the verified driver', logs['data'][0]['verifiedDriverName'] == 'Lia Loophole', logs['data'][0])
    set_status(d['id'], 'Outside')
    code, res = phone_entry('LPX 3003', driver='Someone Else', action='Exit Approved')
    check('exit by an unlisted driver -> 400 DRIVER_NOT_AUTHORIZED', code == 400 and res['data']['code'] == 'DRIVER_NOT_AUTHORIZED', res)
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'LPX 3033', 'ownerName': 'Vee Ip', 'ownerIdNumber': 'LP-X33', 'passClass': 'VIP'}, admin)
    code, res = phone_entry('LPX 3033', driver='Any Chauffeur')
    check('VIP vehicles keep their exemption from the driver check', code == 201, res)

    # --- offline sync: the server flags what the phone could not know
    now = datetime.datetime.now(datetime.timezone.utc)
    unpaid = reg('LPX 3500', 'LP-X35')
    code, res = call('POST', 'sync.php', {'events': [{'client_ref': 'T-loophole-flags-0001', 'type': 'gate_log', 'occurred_at': (now - datetime.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'),
                                                      'payload': {'plate': 'LPX 3500', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': 'Stranger'}}]}, headers=SCANNER)
    flags = res['data']['results'][0]['flags'] if code == 200 else None
    check('offline entry of an unpaid vehicle by an unlisted driver is recorded and FLAGGED', flags is not None and 'UNPAID' in flags and 'DRIVER_NOT_LISTED' in flags, res)

    # --- 4. a vehicle with history cannot be deleted
    clean = reg('LPX 4004', 'LP-X4')
    code, res = call('DELETE', f"vehicles.php?id={clean['id']}", token=admin)
    check('a vehicle with no history can still be deleted (registered by mistake)', code == 200, res)
    code, res = call('DELETE', f"vehicles.php?id={clean['id']}", token=admin)
    check('deleting a missing vehicle -> 404', code == 404, res)
    h = reg('LPX 4040', 'LP-X40')
    pay(h['id'])
    call('POST', 'violations.php', {'vehicle_id': h['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'probe'}, guard)
    code, res = call('DELETE', f"vehicles.php?id={h['id']}", token=admin)
    check('a vehicle on violation hold cannot be deleted -> 409 VEHICLE_HAS_HISTORY', code == 409 and res['data']['code'] == 'VEHICLE_HAS_HISTORY' and res['data']['violations'] == 1, res)
    code, res = call('GET', 'violations.php?status=Pending&plate=LPX4040', token=admin)
    check('  ...the violation and the hold are still there', len(res['data']) == 1, res)
    r = reg('LPX 4141', 'LP-X41')
    pay(r['id'])
    code, res = call('DELETE', f"vehicles.php?id={r['id']}", token=admin)
    check('a vehicle that has paid cannot be deleted either', code == 409 and res['data']['payments'] == 1, res)
    code, res = call('DELETE', f"vehicles.php?id={u['id']}", token=admin)
    check('a vehicle with gate passages cannot be deleted', code == 409 and res['data']['gatePassages'] >= 1, res)
    code, _ = call('DELETE', f"vehicles.php?id={clean['id']}", token=guard)
    check('guards cannot delete -> 403', code == 403, code)

    # --- 5. the fee follows the vehicle when its class changes
    b = reg('LPX 5005', 'LP-X5', 'Bicycle')
    check('(setup) bicycle is free', b['paymentStatus'] == 'Waived' and b['qrPayload'], b)
    code, res = call('PUT', 'vehicles.php', {'id': b['id'], 'makeModelColor': 'Blue'}, admin)
    check('an unrelated edit does not re-price', res['data']['paymentStatus'] == 'Waived', res['data'])
    code, res = call('PUT', 'vehicles.php', {'id': b['id'], 'vehicleType': '4-Wheel'}, admin)
    check('bicycle re-typed as a car -> Unpaid, fee 500, no QR', code == 200 and res['data']['paymentStatus'] == 'Unpaid' and res['data']['feeAmount'] == 500
          and res['data']['qrPayload'] is None, res)
    code, res = phone_entry('LPX 5005')
    check('  ...and it cannot enter until paid', code == 403 and res['data']['code'] == 'VEHICLE_UNPAID', res)
    code, res = pay(b['id'])
    check('  ...paying settles it', code == 201 and res['data']['payment']['amount'] == 500 and res['data']['vehicle']['paymentStatus'] == 'Paid'
          and res['data']['vehicle']['qrPayload'], res)

    m = reg('LPX 5050', 'LP-X50', 'Motorcycle')
    pay(m['id'])
    code, res = call('PUT', 'vehicles.php', {'id': m['id'], 'vehicleType': '4-Wheel'}, admin)
    check('motorcycle (250 paid) re-typed as a car -> only the 250 difference is due', res['data']['paymentStatus'] == 'Unpaid' and res['data']['feeAmount'] == 250, res['data'])
    code, res = pay(m['id'])
    check('  ...the receipt is for the difference, the vehicle shows 500 paid in total', res['data']['payment']['amount'] == 250 and res['data']['vehicle']['feeAmount'] == 500, res)
    code, res = call('PUT', 'vehicles.php', {'id': m['id'], 'vehicleType': 'Motorcycle'}, admin)
    check('re-typing to a cheaper class never refunds or re-bills', res['data']['paymentStatus'] == 'Paid', res['data'])

    vip = reg('LPX 5555', 'LP-X55', passClass='VIP')
    check('(setup) VIP registered free', vip['paymentStatus'] == 'Waived', vip)
    code, res = call('PUT', 'vehicles.php', {'id': vip['id'], 'passClass': 'Standard'}, admin)
    check('withdrawing VIP bills the normal fee', res['data']['paymentStatus'] == 'Unpaid' and res['data']['feeAmount'] == 500, res['data'])

    # vehicles that pre-date payments (grandfathered Paid, no payment on record) are left alone
    db = sqlite3.connect(SQLITE_DB)
    cur = db.execute("INSERT INTO vehicles (plate_number, vehicle_type, make_model_color, owner_name, owner_id_number) VALUES ('LPX 6006', '4-Wheel (Sedan)', 'Old car', 'Old Timer', 'LP-X6')")
    db.commit()
    old_id = cur.lastrowid
    db.close()
    code, res = call('PUT', 'vehicles.php', {'id': old_id, 'vehicleType': '4-Wheel'}, admin)
    check('a grandfathered vehicle edited later stays Paid', code == 200 and res['data']['paymentStatus'] == 'Paid', res)
    AUTO_PAY = True


class FakeSmtp:
    """A tiny SMTP server that records every message, so the real mail code runs end to end without sending anything."""

    def __init__(self, port, user='sp-user', password='sp-pass'):
        import socket, threading
        self.messages, self.user, self.password = [], user, password
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', port))
        self.sock.listen(5)
        self.running = True
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        import threading
        while self.running:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn):
        import base64
        f = conn.makefile('rwb', buffering=0)

        def send(line):
            f.write((line + '\r\n').encode())

        send('220 fake.smtp ready')
        rcpt, auth_step, authed = [], 0, False
        while True:
            line = f.readline()
            if not line:
                return
            cmd = line.decode(errors='replace').strip()
            up = cmd.upper()
            if auth_step == 1:
                auth_step = 2 if base64.b64decode(cmd).decode() == self.user else -1
                send('334 UGFzc3dvcmQ6')
            elif auth_step in (2, -1):
                ok = auth_step == 2 and base64.b64decode(cmd).decode() == self.password
                authed = ok
                auth_step = 0
                send('235 ok' if ok else '535 bad credentials')
            elif up.startswith('EHLO'):
                send('250-fake.smtp')
                send('250 AUTH LOGIN')
            elif up.startswith('AUTH LOGIN'):
                auth_step = 1
                send('334 VXNlcm5hbWU6')
            elif up.startswith('MAIL FROM'):
                send('250 ok' if authed else '530 auth required')
            elif up.startswith('RCPT TO'):
                rcpt.append(cmd[cmd.index('<') + 1:cmd.index('>')])
                send('250 ok')
            elif up == 'DATA':
                send('354 go')
                data = b''
                while not data.endswith(b'\r\n.\r\n'):
                    chunk = f.readline()
                    if not chunk:
                        return
                    data += chunk
                self.messages.append({'to': list(rcpt), 'raw': data})
                rcpt = []
                send('250 queued')
            elif up == 'QUIT':
                send('221 bye')
                conn.close()
                return
            else:
                send('250 ok')

    def stop(self):
        self.running = False
        try:
            self.sock.close()
        except OSError:
            pass

    @staticmethod
    def parse(raw):
        import email, email.header
        msg = email.message_from_bytes(raw)
        subject = str(email.header.make_header(email.header.decode_header(msg['Subject'])))
        text = ''
        for part in msg.walk():
            if part.get_content_type() == 'text/plain':
                text = part.get_payload(decode=True).decode()
        return subject, text, msg



def test_owner_notices(admin):
    """Blocked / violation notices: student portal feed + e-mail through SMTP; on-campus details for the guard."""
    import re, sqlite3, time
    section('Owner notices (portal + e-mail) and on-campus details')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    secret = open(os.path.join(ROOT, 'backend', 'config', 'secret.php'), encoding='utf-8').read()
    smtp_cfg = re.search(r"define\('SP_SMTP_HOST',\s*'127\.0\.0\.1'\)", secret) and re.search(r"define\('SP_SMTP_PORT',\s*(\d+)\)", secret)
    smtp = FakeSmtp(int(smtp_cfg.group(1))) if smtp_cfg else None
    if not smtp:
        print('  (SMTP is not pointed at 127.0.0.1 in secret.php: the e-mail checks are skipped)')

    def new_owner(plate, owner_id, email=None, with_email_account=False):
        body = {'plateNumber': plate, 'ownerName': 'Nina Notice', 'ownerIdNumber': owner_id, 'ownerPhone': '0917 123 4567', 'department': 'BSIT',
                'authorizedDrivers': [{'fullName': 'Nina Notice', 'relationship': 'Self (Owner)'}]}
        if email:
            body['ownerEmail'] = email
        code, res = call('POST', 'vehicles.php', body, admin)
        v = res['data']
        temp_pw = v['studentAccount']['tempPassword']
        tok = call('POST', 'auth.php?action=login&realm=student', {'username': owner_id, 'password': temp_pw})[1]['data']['token']
        call('POST', 'auth.php?action=change_password', {'current_password': temp_pw, 'new_password': 'Student-Note-2026'}, tok)
        return v, tok

    def notices(tok, wait_for=None):
        for _ in range(40):
            code, res = call('GET', 'student.php?action=notices', token=tok)
            rows = res['data']
            if wait_for is None or (rows and rows[0]['emailStatus'] in wait_for):
                return rows
            time.sleep(0.15)
        return rows

    # --- a violation
    v1, tok1 = new_owner('NTC 1001', 'NTC-OWNER-1', 'nina@example.com')
    code, res = call('POST', 'violations.php', {'vehicle_id': v1['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'Blocking the hydrant'}, guard)
    check('guard issues the violation', code == 201, res)
    rows = notices(tok1, ['Sent', 'Failed', 'Skipped'])
    check('the owner sees a Violation notice in the student portal', len(rows) == 1 and rows[0]['kind'] == 'Violation' and rows[0]['plateNumber'] == 'NTC 1001'
          and 'Parking in Fire Lane' in rows[0]['title'] and 'Blocking the hydrant' in rows[0]['message'], rows)
    check('  ...and the portal never exposes the e-mail address or error', set(rows[0]) == {'id', 'kind', 'title', 'message', 'plateNumber', 'emailStatus', 'emailed', 'createdAt'}, sorted(rows[0]))
    if smtp:
        check('  ...the e-mail was sent through SMTP', rows[0]['emailStatus'] == 'Sent' and rows[0]['emailed'] is True, rows[0])
        check('  ...to the owner address', len(smtp.messages) == 1 and smtp.messages[0]['to'] == ['nina@example.com'], [m['to'] for m in smtp.messages])
        subject, text, _ = FakeSmtp.parse(smtp.messages[0]['raw'])
        check('  ...subject names the plate; the body has the violation, the notes and what to do',
              'NTC 1001' in subject and 'Parking in Fire Lane' in text and 'Blocking the hydrant' in text and 'cannot enter or leave campus' in text, (subject, text[:200]))
    else:
        check('  ...without SMTP the e-mail is Skipped, the portal notice stays', rows[0]['emailStatus'] in ('Skipped', 'Failed'), rows[0])

    # --- a block at the gate (guard flags the vehicle)
    code, res = call('POST', 'incidents.php', {'plateNumber': 'NTC 1001', 'reason': 'Plate & Vehicle Profile Mismatch', 'ownerName': 'Nina Notice', 'vehicleType': '4-Wheel',
                                               'gatePoint': 'Gate 1 (Main Ingress)', 'notes': 'Driver did not match'}, guard)
    check('guard blocks the vehicle at the gate', code == 201, res)
    rows = notices(tok1, ['Sent', 'Failed', 'Skipped'])
    check('the owner sees a Blocked notice with the reason and case number', len(rows) == 2 and rows[0]['kind'] == 'Blocked'
          and 'Plate & Vehicle Profile Mismatch' in rows[0]['message'] and 'CASE-' in rows[0]['message'], rows)
    if smtp:
        check('  ...and a second e-mail went out', rows[0]['emailStatus'] == 'Sent' and len(smtp.messages) == 2, (rows[0]['emailStatus'], len(smtp.messages)))

    # --- an owner without an e-mail address still gets the portal notice
    v2, tok2 = new_owner('NTC 2002', 'NTC-OWNER-2')
    call('POST', 'incidents.php', {'plateNumber': 'NTC 2002', 'reason': 'Security Officer Intervention', 'ownerName': 'Nina Notice', 'gatePoint': 'Gate 1 (Main Ingress)'}, guard)
    rows = notices(tok2)
    check('no e-mail on file: portal notice exists, e-mail Skipped', len(rows) == 1 and rows[0]['emailStatus'] == 'Skipped' and rows[0]['emailed'] is False, rows)
    check("another owner's notices are not visible (scoped by login)", all(r['plateNumber'] == 'NTC 2002' for r in rows) and len(notices(tok1)) == 2, rows)
    code, _ = call('GET', 'student.php?action=notices', token=admin)
    check('staff token cannot read the student feed -> 401', code == 401, code)
    code, _ = call('GET', 'student.php?action=notices')
    check('the feed needs a sign-in -> 401', code == 401, code)

    # --- an unregistered plate has no owner to tell
    code, res = call('POST', 'incidents.php', {'plateNumber': 'UNK 0000', 'reason': 'Unauthorized / Unregistered Driver', 'gatePoint': 'Gate 1 (Main Ingress)'}, guard)
    check('blocking an unregistered plate works and notifies nobody', code == 201 and len(notices(tok1)) == 2 and len(notices(tok2)) == 1, res)

    # --- SMTP trouble is recorded, never fatal
    if smtp:
        smtp.stop()
        time.sleep(0.2)
        code, res = call('POST', 'violations.php', {'vehicle_id': v1['id'], 'type': 'Unauthorized Driver at Helm', 'notes': 'mail server is down'}, guard)
        check('the violation is still recorded when SMTP is down', code == 201, res)
        rows = notices(tok1, ['Sent', 'Failed', 'Skipped'])
        check('  ...the owner sees it at once', 'mail server is down' in rows[0]['message'], rows[0])
        check('  ...the notice stays in the portal and the e-mail is marked Failed', rows[0]['kind'] == 'Violation' and rows[0]['emailStatus'] == 'Failed', rows[0])

    # --- the guard's phone gets contact + on-campus details for a vehicle that is already inside
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Inside Campus' WHERE id = ?", (v1['id'],))
    db.execute("DELETE FROM gate_logs WHERE plate_number = 'NTC 1001'")
    db.execute("INSERT INTO gate_logs (plate_number, driver_name, verified_driver_name, action, gate_type, gate_point, status, guard_name, logged_at) "
               "VALUES ('NTC 1001', 'Nina Notice', 'Nina Notice', 'Entry Recorded', 'Ingress', 'Gate 1 (Main Ingress)', 'Inside Campus', 'Officer Reyes', datetime('now', '+8 hours', '-3 hours'))")
    db.commit()
    db.close()
    code, v = verify({'plate': 'NTC 1001', 'gate_type': 'Ingress'}, guard)
    oc = v.get('onCampus') or {}
    check('scanning a vehicle already inside returns where it is and who to call', v.get('currentlyInside') is True and oc.get('ownerPhone') == '0917 123 4567'
          and oc.get('enteredBy') == 'Nina Notice' and oc.get('admittedBy') == 'Officer Reyes' and oc.get('gatePoint') == 'Gate 1 (Main Ingress)'
          and 2.5 <= (oc.get('hoursInside') or 0) <= 3.5, v)
    check('  ...the vehicle record carries the contact number and department', v['vehicle']['ownerPhone'] == '0917 123 4567' and v['vehicle']['department'] == 'BSIT', v['vehicle'])
    code, v = verify({'plate': 'NTC 2002', 'gate_type': 'Ingress'}, guard)
    check('a vehicle that is not inside has no on-campus block', v.get('onCampus') is None, v.get('onCampus'))
    if smtp:
        smtp.stop()


def test_payments(admin):
    """Registration fee: cashier cash payment, PayMongo checkout (local mock gateway), QR only after payment."""
    global AUTO_PAY
    section('Registration fee payments (cashier + online)')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def register(plate, owner_id, vtype=None, **extra):
        body = {'plateNumber': plate, 'ownerName': 'Pat Payer', 'ownerIdNumber': owner_id}
        if vtype:
            body['vehicleType'] = vtype
        body.update(extra)
        return call('POST', 'vehicles.php', body, admin)

    def new_student(plate, owner_id, vtype='4-Wheel'):
        code, res = register(plate, owner_id, vtype)
        temp_pw = res['data']['studentAccount']['tempPassword']
        t = call('POST', 'auth.php?action=login&realm=student', {'username': owner_id, 'password': temp_pw})[1]['data']['token']
        call('POST', 'auth.php?action=change_password', {'current_password': temp_pw, 'new_password': 'Student-Pay-2026'}, t)
        return res['data'], t

    # Fees by vehicle type
    for plate, vtype, status, fee in [('PAY 0001', 'Bicycle', 'Waived', 0), ('PAY 0002', 'Motorcycle', 'Unpaid', 250),
                                      ('PAY 0003', '3-Wheel (Tricycle)', 'Unpaid', 250), ('PAY 0004', '4-Wheel', 'Unpaid', 500),
                                      ('PAY 0005', 'Campus Fleet', 'Unpaid', 500)]:
        code, res = register(plate, 'PAY-' + plate[-4:], vtype)
        d = res['data']
        check(f'{vtype}: fee {fee}, {status}', code == 201 and d['paymentStatus'] == status and d['feeAmount'] == fee, d)
        check(f'{vtype}: QR only when not Unpaid', bool(d['qrPayload']) == (status != 'Unpaid'), d.get('qrPayload'))
    code, res = register('PAY 0006', 'PAY-VIP', '4-Wheel', passClass='VIP')
    check('VIP registration is waived', code == 201 and res['data']['paymentStatus'] == 'Waived' and res['data']['qrPayload'], res)

    # Unpaid vehicle: no QR anywhere, gate refuses entry
    owner = 'PAY-OWNER-1'
    code, res = register('PAY 1001', owner, '4-Wheel')
    veh = res['data']
    temp = res['data']['studentAccount']['tempPassword']
    check('unpaid vehicle: admin sees no QR', veh['paymentStatus'] == 'Unpaid' and veh['qrPayload'] is None, veh)
    code, res = call('GET', 'vehicles.php?plate=PAY1001', token=admin)
    check('unpaid vehicle: lookup has no QR', res['data']['qrPayload'] is None, res)
    code, v = verify({'plate': 'PAY 1001', 'gate_type': 'Ingress'}, guard)
    check('unpaid vehicle is refused at entry (UNPAID)', v.get('result') == 'UNPAID' and v.get('accepted') is False, v)
    code, res = call('POST', 'auth.php?action=login&realm=student', {'username': owner, 'password': temp})
    tok = res['data']['token']
    call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Student-Pay-2026'}, tok)
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    sv = res['data'][0]
    check('student portal: Unpaid, fee 500, no QR', sv['paymentStatus'] == 'Unpaid' and sv['feeAmount'] == 500 and sv['qrPayload'] is None, sv)
    code, res = call('GET', 'student.php?action=me', token=tok)
    check('student summary counts unpaid vehicles', res['data']['summary']['unpaidVehicles'] == 1, res['data']['summary'])

    # Editing an unpaid vehicle updates its fee
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'vehicleType': 'Motorcycle'}, admin)
    check('unpaid fee follows a vehicle type edit (250)', code == 200 and res['data']['feeAmount'] == 250 and res['data']['paymentStatus'] == 'Unpaid', res)
    call('PUT', 'vehicles.php', {'id': veh['id'], 'vehicleType': '4-Wheel'}, admin)
    call('PUT', 'vehicles.php', {'id': veh['id'], 'paymentStatus': 'Paid', 'makeModelColor': 'Edited'}, admin)
    code, res = call('GET', 'vehicles.php?plate=PAY1001', token=admin)
    check('payment status cannot be set through a vehicle edit', res['data']['paymentStatus'] == 'Unpaid' and res['data']['feeAmount'] == 500, res)

    # Cashier
    code, _ = call('GET', 'payments.php?view=unpaid', token=guard)
    check('guard cannot use the cashier -> 403', code == 403, code)
    code, _ = call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id']}, tok)
    check('student token cannot use the cashier -> 401', code == 401, code)
    code, res = call('GET', 'payments.php?view=unpaid', token=admin)
    check('cashier queue lists the unpaid vehicle', code == 200 and any(x['plateNumber'] == 'PAY 1001' and x['feeAmount'] == 500 for x in res['data']), res)
    code, res = call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id'], 'tendered': 100}, admin)
    check('cash below the fee is refused', code == 400, res)
    code, res = call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id'], 'tendered': 1000}, admin)
    pay = res['data']['payment']
    check('cash payment -> receipt with change', code == 201 and pay['receiptNumber'].startswith('OR-') and pay['change'] == 500
          and pay['method'] == 'Cash' and pay['status'] == 'Paid', res)
    paid = res['data']['vehicle']
    check('QR issued after payment', paid['paymentStatus'] == 'Paid' and paid['qrPayload'] and paid['passId'] != veh['passId'], paid)
    code, v = verify({'qr_code': paid['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('paid pass verifies at the gate', v.get('result') == 'VALID' and v.get('accepted') is True, v)
    code, res = call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id']}, admin)
    check('second payment for a paid vehicle -> 409', code == 409, res)
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    check('student now sees the QR', res['data'][0]['qrPayload'] == paid['qrPayload'], res)
    code, res = call('GET', 'student.php?action=payments', token=tok)
    check('student sees the receipt', len(res['data']) == 1 and res['data'][0]['receiptNumber'] == pay['receiptNumber'], res)

    # Online (local mock gateway)
    return_url = BASE.split('/web-app-admin/api')[0] + '/web-app-student/'
    online, tok2 = new_student('PAY 2001', 'PAY-OWNER-2')
    code, res = register('PAY 2002', 'PAY-OTHER', '4-Wheel')
    other = res['data']
    code, res = call('POST', 'student_pay.php', {'vehicleId': other['id'], 'returnUrl': return_url}, tok2)
    check("cannot pay for someone else's vehicle -> 404", code == 404, res)
    code, res = call('POST', 'student_pay.php', {'vehicleId': online['id'], 'returnUrl': 'https://evil.example/steal'}, tok2)
    check('return URL on another host refused -> 400', code == 400, res)
    code, res = call('POST', 'student_pay.php', {'vehicleId': veh['id'], 'returnUrl': return_url}, tok)
    check('already-paid vehicle cannot start a checkout -> 409', code == 409, res)
    code, res = call('POST', 'student_pay.php', {'vehicleId': online['id'], 'returnUrl': return_url}, admin)
    check('staff token cannot start a student checkout -> 401', code == 401, res)
    code, res = call('POST', 'student_pay.php', {'vehicleId': online['id'], 'returnUrl': return_url}, tok2)
    check('student starts an online payment', code == 201 and res['data']['checkoutUrl'] and res['data']['amount'] == 500, res)
    pid = res['data']['paymentId']
    checkout = res['data']['checkoutUrl']
    code, res = call('GET', f'student_pay.php?paymentId={pid}', token=tok2)
    check('pending until the gateway confirms', res['data']['status'] == 'Pending', res)
    code, res = call('GET', 'student.php?action=vehicles', token=tok2)
    check('still no QR while pending', [x for x in res['data'] if x['plateNumber'] == 'PAY 2001'][0]['qrPayload'] is None, res)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    def press(checkout_url, do):
        """Presses a button on the test checkout page; returns the Location it redirects to."""
        form = urllib.parse.parse_qs(urllib.parse.urlparse(checkout_url).query)
        body = urllib.parse.urlencode({'session': form['session'][0], 'return': form['return'][0], 'do': do}).encode()
        try:
            urllib.request.build_opener(NoRedirect).open(urllib.request.Request(checkout_url, data=body))
            return ''
        except urllib.error.HTTPError as e:
            return e.headers.get('Location', '')

    location = press(checkout, 'pay')
    check('checkout redirects back to the portal with the result', location.startswith(return_url) and 'payment=success' in location, location)
    code, res = call('GET', f'student_pay.php?paymentId={pid}', token=tok2)
    check('payment settled', res['data']['status'] == 'Paid' and res['data']['method'] == 'PayMongo' and res['data']['receiptNumber'], res)
    code, res2 = call('GET', f'student_pay.php?paymentId={pid}', token=tok2)
    check('settling is idempotent (same receipt)', res2['data']['receiptNumber'] == res['data']['receiptNumber'], res2)
    code, res = call('GET', 'student.php?action=vehicles', token=tok2)
    pv = [x for x in res['data'] if x['plateNumber'] == 'PAY 2001'][0]
    check('QR active after online payment', pv['paymentStatus'] == 'Paid' and pv['qrPayload'], pv)
    code, v = verify({'qr_code': pv['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('online-paid pass verifies at the gate', v.get('result') == 'VALID', v)

    # Cancelling on the checkout page leaves the vehicle unpaid
    v3, tok3 = new_student('PAY 2003', 'PAY-OWNER-3')
    code, started = call('POST', 'student_pay.php', {'vehicleId': v3['id'], 'returnUrl': return_url}, tok3)
    location = press(started['data']['checkoutUrl'], 'cancel')
    check('cancelled checkout returns with payment=cancelled', 'payment=cancelled' in location, location)
    code, res = call('GET', f"student_pay.php?paymentId={started['data']['paymentId']}", token=tok3)
    check('cancelling does not pay', res['data']['status'] == 'Pending', res)

    # Cash while an online checkout is open: the checkout is cancelled and cannot double-charge
    race, tok4 = new_student('PAY 3001', 'PAY-OWNER-4')
    code, res = call('POST', 'student_pay.php', {'vehicleId': race['id'], 'returnUrl': return_url}, tok4)
    rpid, rcheckout = res['data']['paymentId'], res['data']['checkoutUrl']
    code, res = call('GET', 'payments.php?view=unpaid', token=admin)
    check('queue flags the open online checkout', any(x['plateNumber'] == 'PAY 3001' and x['onlineCheckoutOpen'] for x in res['data']), res)
    code, res = call('POST', 'payments.php', {'action': 'cash', 'vehicleId': race['id']}, admin)
    check('cashier settles it', code == 201, res)
    press(rcheckout, 'pay')
    code, res = call('GET', f'student_pay.php?paymentId={rpid}', token=tok4)
    check('the superseded online checkout stays Cancelled (no double payment)', res['data']['status'] == 'Cancelled', res)

    # Reporting
    code, res = call('GET', 'payments.php', token=admin)
    s = res['data']['summary']
    check('history + today totals', code == 200 and s['cashToday']['count'] >= 2 and s['onlineToday']['count'] == 1
          and s['collectedToday'] >= 1500 and s['onlineMock'] is True and s['unpaidCount'] >= 4, s)
    code, res = call('GET', 'payments.php?method=PayMongo&q=PAY2001', token=admin)
    check('filter by method + plate', len(res['data']['payments']) == 1 and res['data']['payments'][0]['plateNumber'] == 'PAY 2001', res)
    code, res = call('GET', 'payments.php?q=PAY%202001', token=admin)
    check('search by plate with a space', len(res['data']['payments']) == 1, res)

    # Webhook refuses unsigned calls
    code, res = call('POST', 'paymongo_webhook.php', {'data': {'attributes': {'type': 'checkout_session.payment.paid'}}})
    check('webhook without a valid signature -> 401', code == 401, res)
    AUTO_PAY = True


def test_vehicle_classes(admin):
    """One active vehicle per class per ID; admin override; replace vehicle (credit carried over); retire."""
    global AUTO_PAY, AUTO_REASON
    import sqlite3
    section('Vehicle classes: limit, override, replace, retire')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def reg(plate, owner_id, vtype='4-Wheel', **extra):
        return call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': 'Vera Class', 'ownerIdNumber': owner_id, 'vehicleType': vtype, **extra}, admin)

    def pay(vehicle_id):
        return call('POST', 'payments.php', {'action': 'cash', 'vehicleId': vehicle_id}, admin)

    # --- one active vehicle per class
    code, res = reg('VCL 0001', 'VCL-1')
    check('first four-wheel vehicle registers', code == 201, res)
    code, res = reg('VCL 0002', 'VCL-1')
    check('second four-wheel vehicle -> 409 OWNER_CLASS_LIMIT naming the existing plate', code == 409 and res['data']['code'] == 'OWNER_CLASS_LIMIT'
          and res['data']['plateNumber'] == 'VCL 0001' and res['data']['vehicleClass'] == 'four', res)
    code, res = reg('VCL 0002', '  vcl-1 ', 'Campus Fleet')
    check('same ID with different case / spaces, same class (fleet counts as four-wheel) -> 409', code == 409, res)
    code, res = reg('VCL 0003', 'VCL-1', 'Motorcycle')
    check('a motorcycle is a different class -> 201', code == 201, res)
    code, res = reg('VCL 0004', 'VCL-1', 'Bicycle')
    check('a bicycle is its own class -> 201', code == 201 and res['data']['paymentStatus'] == 'Waived', res)
    code, res = reg('VCL 0005', 'VCL-1', '3-Wheel (Tricycle)')
    check('a second two/three-wheel vehicle -> 409', code == 409 and res['data']['vehicleClass'] == 'two', res)
    code, res = reg('VCL 0005', 'VCL-1', 'Motorcycle', overrideReason='abc')
    check('an override reason that is too short is not enough -> 409', code == 409, res)
    code, res = reg('VCL 0005', 'VCL-1', 'Motorcycle', overrideReason='Faculty also owns a scooter for deliveries')
    check('an admin can allow an extra vehicle with a written reason -> 201', code == 201, res)
    _, aud = call('GET', 'audit.php?action=vehicle.limit_override&q=VCL0005', token=admin)
    check('  ...the override is in the audit log with the reason', aud['data']['total'] == 1 and 'scooter' in aud['data']['rows'][0]['reason'], aud['data'])
    code, _ = call('POST', 'vehicles.php', {'plateNumber': 'VCL 0099', 'ownerName': 'X', 'ownerIdNumber': 'VCL-9'}, guard)
    check('guards cannot register vehicles -> 403', code == 403, code)

    # --- changing the class or owner through an edit obeys the same rule
    v1 = call('GET', 'vehicles.php?plate=VCL0003', token=admin)[1]['data']
    code, res = call('PUT', 'vehicles.php', {'id': v1['id'], 'vehicleType': '4-Wheel'}, admin)
    check('re-typing a motorcycle as a car when the ID already has one -> 409', code == 409 and res['data']['code'] == 'OWNER_CLASS_LIMIT', res)
    code, res = call('PUT', 'vehicles.php', {'id': v1['id'], 'vehicleType': '4-Wheel', 'overrideReason': 'Owner keeps both cars on campus'}, admin)
    check('  ...unless an admin gives a reason', code == 200, res)

    # --- replace a vehicle: the old one is retired, the paid fee is carried over
    old = reg('VCL 1001', 'VCL-2')[1]['data']
    pay(old['id'])
    code, res = reg('VCL 1002', 'VCL-2', '4-Wheel', replacesVehicleId=old['id'])
    check('replacing needs a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = reg('VCL 1002', 'VCL-2', '4-Wheel', replacesVehicleId=old['id'], replaceReason='Sold the old car, bought a new one')
    new = res['data']
    check('replacing a paid car with a car -> 201, credit covers the whole fee, the new pass is active',
          code == 201 and new['replaced']['plateNumber'] == 'VCL 1001' and new['replaced']['creditApplied'] == 500 and new['paymentStatus'] == 'Paid' and new['qrPayload'], res)
    old_now = call('GET', 'vehicles.php?plate=VCL1001', token=admin)[1]['data']
    check('the old vehicle is retired: no QR, history kept', old_now['isRetired'] is True and old_now['qrPayload'] is None and old_now['replacedByVehicleId'] == new['id']
          and 'sold the old car' in old_now['retiredReason'].lower(), old_now)
    code, v = verify({'plate': 'VCL 1001', 'gate_type': 'Ingress'}, guard)
    check('a retired vehicle is refused at entry (RETIRED)', v.get('result') == 'RETIRED' and not v['accepted'], v)
    code, res = call('POST', 'logs.php', {'plateNumber': 'VCL 1001', 'driverName': 'Vera Class', 'action': 'Entry Recorded', 'gate_type': 'Ingress'}, headers=SCANNER)
    check('  ...and entry cannot be recorded (VEHICLE_RETIRED)', code == 403 and res['data']['code'] == 'VEHICLE_RETIRED', res)
    code, res = call('PUT', 'vehicles.php', {'id': old['id'], 'action': 'toggle_status'}, admin)
    check('a retired vehicle cannot be reactivated -> 409', code == 409 and res['data']['code'] == 'VEHICLE_RETIRED', res)
    _, pays = call('GET', 'payments.php?q=VCL1002', token=admin)
    credit_rows = [p for p in pays['data']['payments'] if p['method'] == 'Credit']
    check('the credit is recorded as a payment with a receipt', len(credit_rows) == 1 and credit_rows[0]['amount'] == 500 and credit_rows[0]['purpose'] == 'Transfer credit'
          and credit_rows[0]['receiptNumber'], credit_rows)
    code, res = call('POST', 'verify.php', {'qr_code': new['qrPayload'], 'gate_type': 'Ingress'}, guard)
    check('the new vehicle verifies at the gate', res['data']['result'] == 'VALID', res)

    # a cheaper class: the credit covers the fee; nothing is refunded
    car = reg('VCL 2001', 'VCL-3')[1]['data']
    pay(car['id'])
    code, res = reg('VCL 2002', 'VCL-3', 'Motorcycle', replacesVehicleId=car['id'], replaceReason='Switched to a motorcycle')
    check('replacing a car with a motorcycle: only the 250 fee is covered, Paid', code == 201 and res['data']['replaced']['creditApplied'] == 250 and res['data']['paymentStatus'] == 'Paid', res)
    # a dearer class: the balance is due
    moto = reg('VCL 3001', 'VCL-4', 'Motorcycle')[1]['data']
    pay(moto['id'])
    code, res = reg('VCL 3002', 'VCL-4', '4-Wheel', replacesVehicleId=moto['id'], replaceReason='Bought a car')
    check('replacing a motorcycle (250 paid) with a car: 250 credited, 250 still due', code == 201 and res['data']['replaced']['creditApplied'] == 250
          and res['data']['replaced']['balanceDue'] == 250 and res['data']['paymentStatus'] == 'Unpaid' and res['data']['feeAmount'] == 250 and res['data']['qrPayload'] is None, res)
    code, res = pay(res['data']['id'])
    check('  ...paying the balance activates it; the vehicle shows 500 paid in total', code == 201 and res['data']['vehicle']['paymentStatus'] == 'Paid' and res['data']['vehicle']['feeAmount'] == 500, res)
    # an unpaid old vehicle carries no credit
    unpaid_old = reg('VCL 4001', 'VCL-5')[1]['data']
    code, res = reg('VCL 4002', 'VCL-5', '4-Wheel', replacesVehicleId=unpaid_old['id'], replaceReason='Typed the wrong plate at registration')
    check('replacing an unpaid vehicle carries no credit; the new one owes the full fee', code == 201 and res['data']['replaced']['creditApplied'] == 0 and res['data']['paymentStatus'] == 'Unpaid'
          and res['data']['feeAmount'] == 500, res)

    # --- guards for replace / retire
    other = reg('VCL 5001', 'VCL-6')[1]['data']
    code, res = reg('VCL 5002', 'VCL-7', '4-Wheel', replacesVehicleId=other['id'], replaceReason='Not my vehicle at all')
    check('a vehicle that belongs to another ID cannot be replaced -> 400', code == 400, res)
    pay(other['id'])
    call('POST', 'violations.php', {'vehicle_id': other['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'hold'}, guard)
    code, res = reg('VCL 5002', 'VCL-6', '4-Wheel', replacesVehicleId=other['id'], replaceReason='Selling the vehicle')
    check('a vehicle on violation hold cannot be replaced -> 409', code == 409 and res['data']['code'] == 'VEHICLE_HAS_VIOLATION', res)
    code, res = call('PUT', 'vehicles.php', {'id': other['id'], 'action': 'retire', 'reason': 'Selling the vehicle'}, admin)
    check('...nor retired -> 409', code == 409 and res['data']['code'] == 'VEHICLE_HAS_VIOLATION', res)

    retire_me = reg('VCL 6001', 'VCL-8')[1]['data']
    AUTO_REASON = False
    code, res = call('PUT', 'vehicles.php', {'id': retire_me['id'], 'action': 'retire'}, admin)
    check('retiring needs a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    AUTO_REASON = True
    code, res = call('PUT', 'vehicles.php', {'id': retire_me['id'], 'action': 'retire', 'reason': 'Vehicle was sold'}, admin)
    check('retire a vehicle -> 200, isRetired', code == 200 and res['data']['isRetired'] is True, res)
    code, res = call('PUT', 'vehicles.php', {'id': retire_me['id'], 'action': 'retire', 'reason': 'Vehicle was sold'}, admin)
    check('retiring twice -> 409', code == 409, res)
    code, res = reg('VCL 6002', 'VCL-8')
    check('the freed class slot can be used again -> 201', code == 201, res)

    # --- the owner's portal shows only active vehicles
    student = reg('VCL 7001', 'VCL-9')[1]['data']
    temp_pw = student['studentAccount']['tempPassword']
    tok = call('POST', 'auth.php?action=login&realm=student', {'username': 'VCL-9', 'password': temp_pw})[1]['data']['token']
    call('POST', 'auth.php?action=change_password', {'current_password': temp_pw, 'new_password': 'Student-Cls-2026'}, tok)
    pay(student['id'])
    reg('VCL 7002', 'VCL-9', '4-Wheel', replacesVehicleId=student['id'], replaceReason='Replacing the old car')
    code, res = call('GET', 'student.php?action=vehicles', token=tok)
    check('the portal lists only the new vehicle after a replacement', [x['plateNumber'] for x in res['data']] == ['VCL 7002'], res)
    code, res = call('GET', 'student.php?action=me', token=tok)
    check('  ...and counts one vehicle', res['data']['summary']['vehicles'] == 1, res['data']['summary'])
    AUTO_PAY = True


def test_audit_and_approvals(admin):
    """Admin action log, mandatory reasons, second-admin approvals, settings. Runs last: it adds (then removes) a second admin."""
    global AUTO_PAY, AUTO_REASON
    section('Audit log, reasons, second-admin approvals')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    AUTO_PAY = False

    # --- the log is admin-only and records the day's actions
    code, _ = call('GET', 'audit.php', token=guard)
    check('guards cannot read the audit log -> 403', code == 403, code)
    code, res = call('GET', 'audit.php?limit=5', token=admin)
    check('admin reads the log: total, page, action list, rows', code == 200 and res['data']['total'] > 20 and len(res['data']['rows']) == 5 and 'vehicle.register' in res['data']['actions'], res['data'].get('total'))
    code, res = call('GET', 'audit.php?action=payment.cash&limit=100', token=admin)
    check('filter by action', res['data']['rows'] and all(r['action'] == 'payment.cash' for r in res['data']['rows']), res['data']['total'])
    code, res = call('GET', 'audit.php?action=vehicle&limit=100', token=admin)
    check('an action prefix matches the whole group (vehicle.*)', {r['action'] for r in res['data']['rows']} >= {'vehicle.register', 'vehicle.replace'}, {r['action'] for r in res['data']['rows']})
    code, res = call('GET', 'audit.php?q=VCL1001&limit=100', token=admin)
    check('search by plate finds that vehicle\'s history', len(res['data']['rows']) >= 3 and all('VCL 1001' == r['plateNumber'] for r in res['data']['rows'] if r['plateNumber']), len(res['data']['rows']))
    code, res = call('GET', 'audit.php?from=2999-01-01', token=admin)
    check('date filter', res['data']['total'] == 0, res['data']['total'])
    check('every row names who did it', all(r['actor'] and r['createdAt'] for r in call('GET', 'audit.php?limit=100', token=admin)[1]['data']['rows']), '')

    # --- reasons are mandatory for the sensitive actions
    AUTO_REASON = False
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'AUD 1001', 'ownerName': 'Ada Audit', 'ownerIdNumber': 'AUD-1', 'vehicleType': '4-Wheel'}, admin)
    veh = res['data']
    call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id']}, admin)

    def vip_body(**kw):
        return {'id': veh['id'], 'passClass': 'VIP', **kw}
    code, res = call('PUT', 'vehicles.php', vip_body(), admin)
    check('granting VIP without a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = call('PUT', 'vehicles.php', vip_body(reason='abc'), admin)
    check('a reason under 5 characters is not enough -> 400', code == 400, res)
    code, res = call('PUT', 'vehicles.php', vip_body(reason='School president\'s official vehicle'), admin)
    check('with a reason (and no second admin available) VIP is granted directly', code == 200 and res['data']['isVip'] is True, res)
    _, aud = call('GET', 'audit.php?action=vehicle.vip_grant&q=AUD1001', token=admin)
    check('  ...logged with the reason and the note that nobody could approve', aud['data']['total'] == 1 and 'president' in aud['data']['rows'][0]['reason']
          and 'no second administrator' in aud['data']['rows'][0]['detail'], aud['data'])
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passClass': 'Standard'}, admin)
    check('withdrawing VIP needs a reason too -> 400', code == 400, res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passClass': 'Standard', 'reason': 'No longer holds the office'}, admin)
    check('  ...with one it works and is logged', code == 200 and call('GET', 'audit.php?action=vehicle.vip_withdraw&q=AUD1001', token=admin)[1]['data']['total'] == 1, res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passValidUntil': '2026-11-30'}, admin)
    check('moving a pass date needs a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passValidUntil': '2026-11-30', 'reason': 'Registrar extended the school year'}, admin)
    check('  ...with one it works', code == 200 and res['data']['passValidUntil'] == '2026-11-30', res)
    _, aud = call('GET', 'audit.php?action=vehicle.pass_date&q=AUD1001', token=admin)
    check('  ...and the log shows the old and new date', aud['data']['total'] == 1 and '2026-12-31 -> 2026-11-30' in aud['data']['rows'][0]['detail'], aud['data'])
    code, res = call('PUT', 'vehicles.php', {'id': veh['id'], 'passValidUntil': '2026-11-30', 'makeModelColor': 'Blue'}, admin)
    check('re-sending the same date needs no reason', code == 200, res)
    code, res = call('POST', 'passes.php', {'vehicle_id': veh['id'], 'action': 'reissue'}, admin)
    check('reissuing a pass needs a reason -> 400', code == 400, res)
    code, res = call('POST', 'passes.php', {'vehicle_id': veh['id'], 'action': 'reissue', 'reason': 'Phone was lost'}, admin)
    check('  ...with one it is reissued and logged', code == 200 and call('GET', 'audit.php?action=pass.reissue&q=AUD1001', token=admin)[1]['data']['total'] == 1, res)
    fresh = call('POST', 'vehicles.php', {'plateNumber': 'AUD 2002', 'ownerName': 'Del Ete', 'ownerIdNumber': 'AUD-2', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    code, res = call('DELETE', f"vehicles.php?id={fresh['id']}", token=admin)
    check('deleting needs a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = call('DELETE', f"vehicles.php?id={fresh['id']}&reason=Registered%20by%20mistake", token=admin)
    check('  ...with one it is deleted and logged', code == 200 and call('GET', 'audit.php?action=vehicle.delete&q=AUD2002', token=admin)[1]['data']['total'] == 1, res)
    AUTO_REASON = True

    # --- other actions are logged
    code, res = call('POST', 'users.php', {'username': 'audit.guard', 'full_name': 'Audit Guard', 'role': 'guard', 'badge_number': 'NCST-SEC-77'}, admin)
    gid = res['data']['user']['id']
    call('PUT', 'users.php', {'id': gid, 'action': 'set_status', 'status': 'Inactive'}, admin)
    call('PUT', 'users.php', {'id': gid, 'action': 'reset_password'}, admin)
    actions = {r['action'] for r in call('GET', 'audit.php?action=staff&limit=50', token=admin)[1]['data']['rows']}
    check('staff create / status / password reset are logged', {'staff.create', 'staff.status', 'staff.password_reset'} <= actions, actions)
    call('POST', 'students.php', {'owner_id_number': 'AUD-1', 'action': 'issue'}, admin)
    check('issuing a student login is logged', call('GET', 'audit.php?action=student.login_issued', token=admin)[1]['data']['total'] >= 1, '')
    v2 = call('POST', 'vehicles.php', {'plateNumber': 'AUD 3003', 'ownerName': 'Vio Late', 'ownerIdNumber': 'AUD-3'}, admin)[1]['data']
    vid = call('POST', 'violations.php', {'vehicle_id': v2['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'hydrant'}, guard)[1]['data']['violation']['id']
    check('a violation issued by a guard is logged under the guard', any(r['action'] == 'violation.issue' and r['actorRole'] == 'guard'
          for r in call('GET', 'audit.php?q=AUD3003', token=admin)[1]['data']['rows']), '')

    # --- settings
    code, res = call('GET', 'settings.php?scope=all', token=guard)
    check('the settings list is admin-only -> 403', code == 403, code)
    code, res = call('PUT', 'settings.php', {'parking_capacity': 150, 'hold_reminder_days': 5}, admin)
    check('admin saves settings', code == 200 and {s['key']: s['value'] for s in res['data']['settings']}['parking_capacity'] == 150, res)
    code, res = call('PUT', 'settings.php', {'parking_capacity': -3}, admin)
    check('a value outside its limits is refused -> 400', code == 400, res)
    code, res = call('PUT', 'settings.php', {'parking_capacity': 'lots'}, admin)
    check('a non-number is refused -> 400', code == 400, res)
    code, res = call('GET', 'settings.php')
    check('the public settings expose the capacity (the apps need it) but not the internal policy values', res['data']['parking_capacity'] == 150 and 'hold_reminder_days' not in res['data'], res['data'])
    check('setting changes are logged with old and new value', 'parking_capacity: 0 -> 150' in str([r['detail'] for r in call('GET', 'audit.php?action=settings', token=admin)[1]['data']['rows']]), '')
    call('PUT', 'settings.php', {'parking_capacity': 0, 'hold_reminder_days': 3}, admin)

    # --- second-admin approvals
    code, res = call('POST', 'users.php', {'username': 'admin.two', 'full_name': 'Second Admin', 'role': 'admin', 'badge_number': 'NCST-SEC-02'}, admin)
    a2_id, a2_temp = res['data']['user']['id'], res['data']['tempPassword']
    a2 = login('admin.two', a2_temp)[1]['data']['token']
    call('POST', 'auth.php?action=change_password', {'current_password': a2_temp, 'new_password': 'Admin-Two-2026'}, a2)
    a2 = login('admin.two', 'Admin-Two-2026')[1]['data']['token']

    target = call('POST', 'vehicles.php', {'plateNumber': 'APR 1001', 'ownerName': 'App Rove', 'ownerIdNumber': 'APR-1', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    code, res = call('PUT', 'vehicles.php', {'id': target['id'], 'passClass': 'VIP', 'reason': 'Dean of the college'}, admin)
    check('with two administrators, granting VIP becomes a request (202), nothing changes yet', code == 202 and res['data']['vipApprovalPending'] is True and res['data']['isVip'] is False, res)
    check('  ...the vehicle is still Standard and still owes its fee', call('GET', 'vehicles.php?plate=APR1001', token=admin)[1]['data']['paymentStatus'] == 'Unpaid', '')
    code, res = call('PUT', 'vehicles.php', {'id': target['id'], 'passClass': 'VIP', 'reason': 'Dean of the college'}, admin)
    check('asking again while one is pending -> 409', code == 409 and res['data']['code'] == 'APPROVAL_PENDING', res)
    code, res = call('GET', 'approvals.php?status=Pending', token=admin)
    req = [r for r in res['data']['requests'] if r['plateNumber'] == 'APR 1001'][0]
    check('the request shows who asked, what and why', req['type'] == 'vip_grant' and req['requestedBy'].startswith('System Administrator') and req['reason'] == 'Dean of the college'
          and res['data']['pending'] >= 1 and res['data']['secondAdminAvailable'] is True, req)
    code, res = call('POST', 'approvals.php', {'id': req['id'], 'decision': 'approve'}, admin)
    check('the requester cannot approve their own request -> 403', code == 403, res)
    code, _ = call('POST', 'approvals.php', {'id': req['id'], 'decision': 'approve'}, guard)
    check('guards cannot decide -> 403', code == 403, code)
    code, res = call('POST', 'approvals.php', {'id': req['id'], 'decision': 'approve', 'note': 'Confirmed with the HR office'}, a2)
    check('a different administrator approves -> VIP is granted', code == 200 and res['data']['request']['status'] == 'Approved', res)
    got = call('GET', 'vehicles.php?plate=APR1001', token=admin)[1]['data']
    check('  ...the vehicle is VIP, its fee waived, granted by both names', got['isVip'] is True and got['paymentStatus'] == 'Waived' and 'approved by Second Admin' in got['vipGrantedBy'], got)
    code, res = call('POST', 'approvals.php', {'id': req['id'], 'decision': 'reject', 'note': 'late'}, a2)
    check('a decided request cannot be decided again -> 409', code == 409, res)
    check('the approval is in the audit log', call('GET', 'audit.php?action=approval.approved', token=admin)[1]['data']['total'] == 1, '')

    t2 = call('POST', 'vehicles.php', {'plateNumber': 'APR 2002', 'ownerName': 'Rej Ect', 'ownerIdNumber': 'APR-2', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    call('PUT', 'vehicles.php', {'id': t2['id'], 'passClass': 'VIP', 'reason': 'Friend of a trustee'}, admin)
    req2 = [r for r in call('GET', 'approvals.php?status=Pending', token=admin)[1]['data']['requests'] if r['plateNumber'] == 'APR 2002'][0]
    code, res = call('POST', 'approvals.php', {'id': req2['id'], 'decision': 'reject'}, a2)
    check('rejecting needs a note for the requester -> 400', code == 400, res)
    code, res = call('POST', 'approvals.php', {'id': req2['id'], 'decision': 'reject', 'note': 'Not a trustee guest'}, a2)
    check('reject with a note -> Rejected, the vehicle stays Standard', code == 200 and res['data']['request']['status'] == 'Rejected'
          and call('GET', 'vehicles.php?plate=APR2002', token=admin)[1]['data']['isVip'] is False, res)

    code, res = call('POST', 'vehicles.php', {'plateNumber': 'APR 3003', 'ownerName': 'Reg Vip', 'ownerIdNumber': 'APR-3', 'vehicleType': '4-Wheel', 'passClass': 'VIP', 'reason': 'Guest of honour'}, admin)
    check('registering as VIP with two administrators: registered Standard, request pending', code == 201 and res['data']['vipApprovalPending'] is True and res['data']['isVip'] is False
          and res['data']['paymentStatus'] == 'Unpaid', res)

    # dismissing a violation needs the second administrator; resolving does not
    t3 = call('POST', 'vehicles.php', {'plateNumber': 'APR 4004', 'ownerName': 'Dis Miss', 'ownerIdNumber': 'APR-4', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    v_id = call('POST', 'violations.php', {'vehicle_id': t3['id'], 'type': 'Unauthorized Driver at Helm', 'notes': 'x'}, guard)[1]['data']['violation']['id']
    code, res = call('PUT', 'violations.php', {'violation_id': v_id, 'action': 'dismiss', 'notes': 'Issued to the wrong vehicle'}, admin)
    check('dismissing a violation becomes a request (202); the vehicle stays on hold', code == 202 and res['data']['approvalPending'] is True
          and call('GET', 'vehicles.php?plate=APR4004', token=admin)[1]['data']['isBanned'] is True, res)
    code, res = call('PUT', 'violations.php', {'violation_id': v_id, 'action': 'dismiss', 'notes': 'Issued to the wrong vehicle'}, admin)
    check('  ...asking again -> 409', code == 409, res)
    req3 = [r for r in call('GET', 'approvals.php?status=Pending', token=admin)[1]['data']['requests'] if r['plateNumber'] == 'APR 4004'][0]
    code, res = call('POST', 'approvals.php', {'id': req3['id'], 'decision': 'approve'}, a2)
    got = call('GET', 'vehicles.php?plate=APR4004', token=admin)[1]['data']
    check('the second administrator approves -> dismissed, the hold is lifted', code == 200 and got['isBanned'] is False, res)
    pend = call('GET', 'violations.php?status=Dismissed&plate=APR4004', token=admin)[1]['data']
    check('  ...the dismissal carries both names and the requester\'s notes', pend and 'approved by Second Admin' in pend[0]['resolvedBy'] and pend[0]['resolutionNotes'] == 'Issued to the wrong vehicle', pend)
    v_id2 = call('POST', 'violations.php', {'vehicle_id': t3['id'], 'type': 'Unauthorized Driver at Helm', 'notes': 'again'}, guard)[1]['data']['violation']['id']
    code, res = call('PUT', 'violations.php', {'violation_id': v_id2, 'action': 'resolve', 'notes': 'Cleared at the office'}, admin)
    check('resolving a violation stays a single-admin action', code == 200 and res['data']['holdLifted'] is True, res)

    # a violation that was resolved meanwhile closes its pending dismissal request
    t4 = call('POST', 'vehicles.php', {'plateNumber': 'APR 5005', 'ownerName': 'Race Cond', 'ownerIdNumber': 'APR-5', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    v4 = call('POST', 'violations.php', {'vehicle_id': t4['id'], 'type': 'Unauthorized Driver at Helm', 'notes': 'x'}, guard)[1]['data']['violation']['id']
    call('PUT', 'violations.php', {'violation_id': v4, 'action': 'dismiss', 'notes': 'Mistake'}, admin)
    call('PUT', 'violations.php', {'violation_id': v4, 'action': 'resolve', 'notes': 'Paid and cleared'}, admin)
    req4 = [r for r in call('GET', 'approvals.php?status=Pending', token=admin)[1]['data']['requests'] if r['plateNumber'] == 'APR 5005'][0]
    code, res = call('POST', 'approvals.php', {'id': req4['id'], 'decision': 'approve'}, a2)
    check('approving a dismissal of an already-closed violation just closes the request', code == 200, res)

    # --- back to one administrator: no second approver exists, so actions apply directly again
    call('PUT', 'users.php', {'id': a2_id, 'action': 'set_status', 'status': 'Inactive'}, admin)
    t5 = call('POST', 'vehicles.php', {'plateNumber': 'APR 6006', 'ownerName': 'Solo Admin', 'ownerIdNumber': 'APR-6', 'vehicleType': '4-Wheel'}, admin)[1]['data']
    code, res = call('PUT', 'vehicles.php', {'id': t5['id'], 'passClass': 'VIP', 'reason': 'Only one administrator is active'}, admin)
    check('with one active administrator VIP is granted directly again', code == 200 and res['data']['isVip'] is True, res)
    AUTO_REASON = True
    AUTO_PAY = True


def test_ops_phase2(admin):
    """Renewals, maintenance reminders, one-time exit release, capacity, guard shifts, evidence photos, HTTPS headers."""
    global AUTO_PAY
    import datetime, sqlite3, time, base64
    section('Renewals, exit release, capacity, shifts, evidence, HTTPS')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    today = datetime.date.today()
    year = today.year

    def reg(plate, owner_id, vtype='4-Wheel', **extra):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': 'Rene Wall', 'ownerIdNumber': owner_id, 'vehicleType': vtype, 'ownerEmail': f'{owner_id.lower()}@example.com',
                                                 'authorizedDrivers': [{'fullName': 'Rene Wall', 'relationship': 'Self (Owner)', 'licenseNo': 'N/A'}], **extra}, admin)
        return res['data']

    def pay(vid):
        return call('POST', 'payments.php', {'action': 'cash', 'vehicleId': vid}, admin)

    def set_until(vid, d):
        db = sqlite3.connect(SQLITE_DB)
        db.execute("UPDATE vehicles SET pass_valid_until = ? WHERE id = ?", (d, vid))
        db.commit()
        db.close()

    def student_token(v, owner_id):
        temp = v['studentAccount']['tempPassword']
        t = call('POST', 'auth.php?action=login&realm=student', {'username': owner_id, 'password': temp})[1]['data']['token']
        call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Student-Ren-2026'}, t)
        return t

    # ---------------------------------------------------------------- renewals
    near = (today + datetime.timedelta(days=20)).isoformat()
    far = (today + datetime.timedelta(days=200)).isoformat()
    past = (today - datetime.timedelta(days=10)).isoformat()
    r1 = reg('RNW 1001', 'RN-1')
    pay(r1['id'])
    tok_r1 = student_token(r1, 'RN-1')
    set_until(r1['id'], far)
    code, res = call('POST', 'renewals.php', {'action': 'cash', 'vehicleId': r1['id']}, admin)
    check('renewal is refused before the window opens -> 409', code == 409 and 'opens' in res['message'], res)
    code, res = call('GET', 'renewals.php', token=guard)
    check('guards cannot use renewals -> 403', code == 403, code)

    set_until(r1['id'], near)
    code, res = call('GET', 'renewals.php', token=admin)
    row = [r for r in res['data']['vehicles'] if r['plateNumber'] == 'RNW 1001']
    check('a pass inside the window is on the renewal list with fee 500 and next year as the new date',
          len(row) == 1 and row[0]['eligible'] and row[0]['fee'] == 500 and row[0]['newValidUntil'] == f'{year + 1}-12-31' and row[0]['daysLeft'] == 20, row)
    code, res = call('POST', 'renewals.php', {'action': 'cash', 'vehicleId': r1['id'], 'tendered': 100}, admin)
    check('cash below the fee is refused', code == 409, res)
    code, res = call('POST', 'renewals.php', {'action': 'free', 'vehicleId': r1['id']}, admin)
    check('"free" on a fee-bearing renewal is refused', code == 409, res)
    code, res = call('POST', 'renewals.php', {'action': 'cash', 'vehicleId': r1['id'], 'tendered': 500}, admin)
    check('cash renewal -> pass moves to Dec 31 of next year, new QR', code == 201 and res['data']['vehicle']['passValidUntil'] == f'{year + 1}-12-31'
          and res['data']['vehicle']['qrPayload'] and res['data']['payment']['purpose'] == 'Renewal' and res['data']['payment']['amount'] == 500, res)
    old_qr = r1['qrPayload']
    check('  ...the QR changed (the old pass id is dead)', res['data']['vehicle']['qrPayload'] != old_qr, '')
    code, res = call('POST', 'renewals.php', {'action': 'cash', 'vehicleId': r1['id']}, admin)
    check('renewing again is refused (not due any more)', code == 409, res)
    code, res = call('GET', 'audit.php?action=renewal&q=RNW1001', token=admin)
    check('the renewal is in the audit log', res['data']['total'] == 1, res['data'])

    # expired pass: renew -> valid again, can enter
    r2 = reg('RNW 2002', 'RN-2')
    pay(r2['id'])
    set_until(r2['id'], past)
    code, v = verify({'plate': 'RNW 2002', 'gate_type': 'Ingress'}, guard)
    check('expired pass is refused at the gate', v.get('result') == 'EXPIRED', v)
    code, res = call('POST', 'renewals.php', {'action': 'cash', 'vehicleId': r2['id']}, admin)
    check('an expired pass can be renewed', code == 201 and res['data']['vehicle']['passValidUntil'] == f'{year}-12-31' or res['data']['vehicle']['passValidUntil'] == f'{year + 1}-12-31', res)
    code, v = verify({'plate': 'RNW 2002', 'gate_type': 'Ingress'}, guard)
    check('  ...and then it is admitted', v.get('accepted') is True, v)

    # free renewal (bicycle) and bulk
    b1 = reg('RNW 3001', 'RN-3', 'Bicycle')
    b2 = reg('RNW 3002', 'RN-4', 'Motorcycle')
    pay(b2['id'])
    b3 = reg('RNW 3003', 'RN-5', 'Motorcycle')
    pay(b3['id'])
    for v_ in (b1, b2, b3):
        set_until(v_['id'], near)
    code, res = call('POST', 'renewals.php', {'action': 'bulk', 'vehicleIds': [b1['id'], b2['id'], b3['id']]}, admin)
    check('bulk renewal with fees needs the cash confirmation -> 400', code == 400 and res['data']['code'] == 'CASH_CONFIRMATION_REQUIRED' and res['data']['totalDue'] == 500, res)
    code, res = call('GET', 'vehicles.php?plate=RNW3001', token=admin)
    check('  ...and nothing changed', res['data']['passValidUntil'] == near, res['data']['passValidUntil'])
    code, res = call('POST', 'renewals.php', {'action': 'bulk', 'vehicleIds': [b1['id'], b2['id'], b3['id']], 'cashCollected': True}, admin)
    check('bulk renewal: 3 renewed, PHP 500 collected (bicycle free)', code == 200 and res['data']['renewed'] == 3 and res['data']['collected'] == 500, res)

    # online renewal by the owner
    return_url = BASE.split('/web-app-admin/api')[0] + '/web-app-student/'
    r3 = reg('RNW 4001', 'RN-6')
    pay(r3['id'])
    tok_r3 = student_token(r3, 'RN-6')
    code, res = call('POST', 'student_pay.php', {'vehicleId': r3['id'], 'returnUrl': return_url, 'purpose': 'renewal'}, tok_r3)
    check('online renewal before the window opens -> 409', code == 409, res)
    set_until(r3['id'], near)
    code, res = call('GET', 'student.php?action=vehicles', token=tok_r3)
    sv = res['data'][0]
    check('the owner sees the renewal as available (fee 500)', sv.get('renewal', {}).get('eligible') is True and sv['renewal']['fee'] == 500, sv.get('renewal'))
    code, res = call('POST', 'student_pay.php', {'vehicleId': r3['id'], 'returnUrl': return_url, 'purpose': 'renewal'}, tok_r3)
    check('owner starts an online renewal', code == 201 and res['data']['amount'] == 500, res)
    pid, checkout = res['data']['paymentId'], res['data']['checkoutUrl']

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None
    form = urllib.parse.parse_qs(urllib.parse.urlparse(checkout).query)
    body = urllib.parse.urlencode({'session': form['session'][0], 'return': form['return'][0], 'do': 'pay'}).encode()
    try:
        urllib.request.build_opener(NoRedirect).open(urllib.request.Request(checkout, data=body))
    except urllib.error.HTTPError:
        pass
    code, res = call('GET', f'student_pay.php?paymentId={pid}', token=tok_r3)
    check('online renewal settles', res['data']['status'] == 'Paid' and res['data']['purpose'] == 'Renewal', res)
    code, res = call('GET', 'vehicles.php?plate=RNW4001', token=admin)
    check('  ...and the pass now runs to next year', res['data']['passValidUntil'] == f'{year + 1}-12-31', res['data']['passValidUntil'])

    # ---------------------------------------------------------------- maintenance reminders
    m1 = reg('MNT 1001', 'MN-1')
    pay(m1['id'])
    tok_m1 = student_token(m1, 'MN-1')
    set_until(m1['id'], (today + datetime.timedelta(days=10)).isoformat())
    code, res = call('POST', 'maintenance.php?force=1', token=guard)
    check('only admins can force maintenance -> 403', code == 403, code)
    code, res = call('POST', 'maintenance.php?force=1', token=admin)
    check('maintenance sends expiry notices', code == 200 and res['data']['expiryNotices'] >= 1, res)
    rows = call('GET', 'student.php?action=notices', token=tok_m1)[1]['data']
    check('the owner sees an Expiry notice naming the date', any(r['kind'] == 'Expiry' and 'expires on' in r['message'] for r in rows), rows)
    code, res = call('POST', 'maintenance.php?force=1', token=admin)
    check('running it again sends nothing new (idempotent)', res['data']['expiryNotices'] == 0, res)
    code, res = call('POST', 'maintenance.php', token=admin)
    check('an unforced run right after is skipped', res['data'].get('skipped') is True, res)

    h1 = reg('MNT 2002', 'MN-2')
    pay(h1['id'])
    tok_h1 = student_token(h1, 'MN-2')
    code, res = call('POST', 'violations.php', {'vehicle_id': h1['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'Hydrant'}, guard)
    vid = res['data']['violation']['id']
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicle_violations SET created_at = ? WHERE id = ?", ((datetime.datetime.now() - datetime.timedelta(days=7)).strftime('%Y-%m-%d %H:%M:%S'), vid))
    db.commit()
    db.close()
    code, res = call('POST', 'maintenance.php?force=1', token=admin)
    check('an unresolved violation older than N days triggers a reminder', res['data']['holdReminders'] == 1, res)
    rows = call('GET', 'student.php?action=notices', token=tok_h1)[1]['data']
    check('  ...the owner sees a Reminder notice', any(r['kind'] == 'Reminder' and 'unresolved' in r['message'] for r in rows), rows)
    code, res = call('POST', 'maintenance.php?force=1', token=admin)
    check('  ...and it is not sent twice', res['data']['holdReminders'] == 0, res)

    # ---------------------------------------------------------------- one-time exit release
    x = reg('RLS 1001', 'RL-1')
    pay(x['id'])
    driver = int(x['authorizedDrivers'][0]['id'])
    code, res = call('POST', 'logs.php', {'plate': 'RLS 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver}, guard)
    check('vehicle enters', code == 201, res)
    code, res = call('POST', 'releases.php', {'vehicleId': x['id'], 'reason': 'Emergency, parent is ill'}, admin)
    check('releasing a vehicle that is not on hold -> 409 NOT_ON_HOLD', code == 409 and res['data']['code'] == 'NOT_ON_HOLD', res)
    call('POST', 'violations.php', {'vehicle_id': x['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'Blocked the exit'}, guard)
    code, v = verify({'plate': 'RLS 1001', 'gate_type': 'Egress'}, guard)
    check('on hold: exit is refused', v.get('result') == 'BANNED' and v.get('accepted') is False, v)
    code, res = call('POST', 'logs.php', {'plate': 'RLS 1001', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': driver}, guard)
    check('  ...also server-side', code == 403 and res['data']['code'] == 'VEHICLE_BANNED', res)
    code, res = call('POST', 'releases.php', {'vehicleId': x['id'], 'reason': 'Emergency'}, guard)
    check('a guard cannot release -> 403', code == 403, code)
    code, res = call('POST', 'releases.php', {'vehicleId': x['id']}, admin)
    check('the admin must give a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = call('POST', 'releases.php', {'vehicleId': x['id'], 'reason': 'Emergency, parent is ill'}, admin)
    check('admin releases one exit', code == 201 and res['data']['minutes'] == 30, res)
    code, res = call('POST', 'releases.php', {'vehicleId': x['id'], 'reason': 'Again please'}, admin)
    check('a second release while one is active -> 409', code == 409, res)
    code, v = verify({'plate': 'RLS 1001', 'gate_type': 'Egress'}, guard)
    check('the gate scan now accepts the exit, with a warning naming the release', v.get('accepted') is True and any('EXIT RELEASED' in w for w in v.get('warnings', [])) and v.get('exitRelease'), v)
    code, v = verify({'plate': 'RLS 1001', 'gate_type': 'Ingress'}, guard)
    check('a release does not allow entry', v.get('accepted') is False, v)
    code, res = call('POST', 'logs.php', {'plate': 'RLS 1001', 'action': 'Exit Approved', 'gate_type': 'Egress', 'driver_id': driver}, guard)
    check('the exit is recorded', code == 201, res)
    code, res = call('GET', 'vehicles.php?plate=RLS1001', token=admin)
    check('  ...the vehicle is outside and still on hold', res['data']['status'] != 'Inside Campus' and res['data'].get('isBanned', True), res['data']['status'])
    code, res = call('POST', 'logs.php', {'plate': 'RLS 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver}, guard)
    check('  ...and cannot come back in', code == 403, res)
    code, res = call('GET', 'audit.php?action=exit.&q=RLS1001', token=admin)
    actions = {r['action'] for r in res['data']['rows']}
    check('release and use are both in the audit log', {'exit.release', 'exit.release_used'} <= actions, actions)
    # single use: put it back inside and try again
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE vehicles SET status = 'Inside Campus' WHERE id = ?", (x['id'],))
    db.commit()
    db.close()
    code, v = verify({'plate': 'RLS 1001', 'gate_type': 'Egress'}, guard)
    check('a used release cannot be reused', v.get('accepted') is False, v)
    # expiry
    code, res = call('POST', 'releases.php', {'vehicleId': x['id'], 'reason': 'Second emergency'}, admin)
    check('a new release can be issued after the first was used', code == 201, res)
    rid = res['data']['id']
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE exit_releases SET expires_at = ? WHERE id = ?", ((datetime.datetime.now() - datetime.timedelta(minutes=1)).strftime('%Y-%m-%d %H:%M:%S'), rid))
    db.commit()
    db.close()
    code, v = verify({'plate': 'RLS 1001', 'gate_type': 'Egress'}, guard)
    check('an expired release does nothing', v.get('accepted') is False, v)

    # ---------------------------------------------------------------- capacity
    code, res = call('GET', 'stats.php', token=admin)
    inside = res['data']['occupancy']['inside']
    check('stats carry the occupancy (unlimited by default)', res['data']['occupancy']['level'] == 'unlimited' and inside == res['data']['inside'], res['data']['occupancy'])
    code, res = call('PUT', 'settings.php', {'parking_capacity': inside + 10, 'reason': 'Lot A + B only'}, admin)
    check('set a capacity', code == 200, res)
    code, res = call('GET', 'stats.php', token=admin)
    check('plenty of room -> ok', res['data']['occupancy']['level'] == 'ok' and res['data']['occupancy']['available'] == 10, res['data']['occupancy'])
    code, res = call('PUT', 'settings.php', {'parking_capacity': max(inside + 1, 1)}, admin)
    code, res = call('GET', 'stats.php', token=admin)
    check('one space left -> nearly full', res['data']['occupancy']['level'] == 'nearly_full', res['data']['occupancy'])
    code, v = verify({'plate': 'MNT 1001', 'gate_type': 'Ingress'}, guard)
    check('the gate scan carries the occupancy warning', v['occupancy']['level'] == 'nearly_full' and v['occupancy']['message'], v.get('occupancy'))
    code, res = call('PUT', 'settings.php', {'parking_capacity': max(inside, 1)}, admin)
    code, v = verify({'plate': 'MNT 1001', 'gate_type': 'Ingress'}, guard)
    check('at capacity -> full (entry is still the guard\'s decision)', v['occupancy']['level'] == 'full' and v['accepted'] is True, v.get('occupancy'))
    call('PUT', 'settings.php', {'parking_capacity': 0}, admin)

    # ---------------------------------------------------------------- guard shifts and the supervisor view
    code, res = call('GET', 'shifts.php', token=guard)
    check('nobody on duty and no handover to start', code == 200 and res['data']['mine'] is None, res)
    code, res = call('POST', 'shifts.php', {'action': 'start'}, guard)
    check('going on duty needs a gate -> 400', code == 400, res)
    code, res = call('POST', 'shifts.php', {'action': 'start', 'gate': 'Gate 1 (Main Ingress)'}, guard)
    check('guard goes on duty', code == 201 and res['data']['shift']['gate'] == 'Gate 1 (Main Ingress)', res)
    code, res = call('POST', 'shifts.php', {'action': 'start', 'gate': 'Gate 1 (Main Ingress)'}, guard)
    check('starting again at the same gate resumes it', code == 200, res)
    code, res = call('GET', 'shifts.php', token=admin)
    check('the supervisor sees who is on duty', any(s['gate'] == 'Gate 1 (Main Ingress)' and 'QA Guard' in s['guard'] for s in res['data']['onDuty']), res['data']['onDuty'])
    code, res = call('POST', 'shifts.php', {'action': 'end', 'notes': 'Gate arm is jammed; the plate of the blue Vios was not read.'}, guard)
    check('guard ends the shift with a handover note', code == 200, res)
    code, res = call('POST', 'shifts.php', {'action': 'end'}, guard)
    check('ending when not on duty -> 409', code == 409, res)
    code, res = call('POST', 'shifts.php', {'action': 'start', 'gate': 'Gate 1 (Main Ingress)'}, admin)
    check('the next person on that gate gets the previous handover note', code == 201 and res['data']['handover'] and 'jammed' in res['data']['handover']['handoverNotes'], res)
    call('POST', 'shifts.php', {'action': 'end'}, admin)
    code, res = call('POST', 'shifts.php', {'action': 'start', 'gate': 'Gate 2'}, None)
    check('shifts need a sign-in', code == 401, code)
    code, res = call('POST', 'verify.php', {'plate': 'MNT 1001', 'gate_type': 'Ingress', 'lookupMethod': 'manual'}, guard)
    code, res = call('GET', 'shifts.php?scope=report', token=guard)
    check('the report is for admins only -> 403', code == 403, code)
    code, res = call('GET', 'shifts.php?scope=report', token=admin)
    qa = [g for g in res['data']['guards'] if 'QA Guard' in g['guard']]
    check('the supervisor report lists each guard with entries, exits, denials, manual lookups, violations and hours',
          qa and qa[0]['violationsIssued'] >= 2 and qa[0]['shifts'] >= 1 and qa[0]['entries'] >= 1 and 'denialRate' in qa[0], qa)

    # ---------------------------------------------------------------- evidence photos
    jpeg = base64.b64encode(b'\xff\xd8\xff\xe0' + b'\x00' * 200 + b'\xff\xd9').decode()
    code, lg = call('POST', 'logs.php', {'plate': 'MNT 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driverName': 'Rene Wall',
                                         'driver_id': int(m1['authorizedDrivers'][0]['id'])}, guard)
    log_id = lg['data']['id']
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'MNT 1001', 'gateLogId': log_id, 'image': jpeg, 'plateRead': 'MNT 1001'}, guard)
    check('guard uploads an entry photo; the plate read matches', code == 201 and res['data']['plateMatches'] is True, res)
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'MNT 1001', 'gateLogId': log_id, 'image': 'data:image/jpeg;base64,' + jpeg, 'plateRead': 'MNT-1OO1'}, guard)
    check('an OCR confusion (O vs 0) still matches', code == 201 and res['data']['plateMatches'] is True, res)
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'MNT 1001', 'gateLogId': log_id, 'image': jpeg, 'plateRead': 'XYZ 9999'}, guard)
    check('a different plate on the photo is flagged as a mismatch', code == 201 and res['data']['plateMatches'] is False and 'does not match' in res['message'], res)
    code, res = call('GET', 'audit.php?action=evidence.plate_mismatch', token=admin)
    check('  ...and logged', res['data']['total'] == 1, res['data'])
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'MNT 1001', 'gateLogId': log_id, 'image': jpeg}, guard)
    check('a photo with no plate read is stored unchecked', code == 201 and res['data']['plateMatches'] is None, res)
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'MNT 1001', 'gateLogId': log_id, 'image': jpeg}, guard)
    check('at most 4 photos per record -> 409', code == 409, res)
    code, res = call('POST', 'evidence.php', {'kind': 'entry', 'plate': 'RLS 1001', 'gateLogId': log_id, 'image': jpeg}, guard)
    check('a photo cannot be attached to another plate\'s record -> 400', code == 400, res)
    code, res = call('POST', 'evidence.php', {'kind': 'violation', 'plate': 'MNT 2002', 'violationId': vid, 'image': base64.b64encode(b'<html>not an image</html>').decode()}, guard)
    check('something that is not a JPEG/PNG is refused', code == 400, res)
    code, res = call('POST', 'evidence.php', {'kind': 'violation', 'plate': 'MNT 2002', 'violationId': vid, 'image': base64.b64encode(b'\xff\xd8\xff' + b'0' * 700000).decode()}, guard)
    check('an oversized photo -> 413', code == 413, res)
    code, res = call('POST', 'evidence.php', {'kind': 'violation', 'plate': 'MNT 2002', 'violationId': vid, 'image': jpeg}, guard)
    check('violation evidence is stored', code == 201, res)
    ev_id = res['data']['id']
    code, res = call('GET', f'evidence.php?violationId={vid}', token=guard)
    check('guards cannot browse evidence -> 403', code == 403, code)
    code, res = call('GET', f'evidence.php?violationId={vid}', token=admin)
    check('admin lists the evidence without pictures', code == 200 and len(res['data']) == 1 and 'image' not in res['data'][0], res)
    code, res = call('GET', f'evidence.php?id={ev_id}', token=admin)
    check('admin opens one photo (data URL)', res['data']['image'].startswith('data:image/jpeg;base64,'), '')
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE evidence_photos SET created_at = ? WHERE id = ?", ((datetime.datetime.now() - datetime.timedelta(days=120)).strftime('%Y-%m-%d %H:%M:%S'), ev_id))
    db.commit()
    db.close()
    code, res = call('POST', 'maintenance.php?force=1', token=admin)
    check('photos older than the retention period are purged', res['data']['photosPurged'] == 1, res)
    code, res = call('GET', f'evidence.php?id={ev_id}', token=admin)
    check('  ...the row stays, the picture is gone', res['data']['purged'] is True and not res['data']['image'], res['data'])

    # ---------------------------------------------------------------- HTTPS plumbing
    code, res = call('GET', 'status.php')
    check('status reports how the request arrived', code == 200 and 'transport' in res['data'] and res['data']['transport']['secure'] is False, res)
    req = urllib.request.Request(f'{BASE}/status.php', headers={'X-Forwarded-Proto': 'https'})
    with urllib.request.urlopen(req) as r:
        check('behind a TLS proxy (X-Forwarded-Proto) the API sends HSTS', 'max-age' in (r.headers.get('Strict-Transport-Security') or ''), dict(r.headers))
        check('  ...and nosniff', r.headers.get('X-Content-Type-Options') == 'nosniff', '')
    with urllib.request.urlopen(f'{BASE}/status.php') as r:
        check('plain http gets no HSTS header', r.headers.get('Strict-Transport-Security') is None, '')
    AUTO_PAY = True


def test_cases(admin):
    """Cases: violations and security incidents as one process with steps, outcomes and an owner-facing timeline."""
    global AUTO_PAY
    section('Cases (one process for violations and security incidents)')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def reg(plate, owner_id):
        code, res = call('POST', 'vehicles.php', {'plateNumber': plate, 'ownerName': 'Cass Case', 'ownerIdNumber': owner_id, 'vehicleType': '4-Wheel', 'ownerEmail': f'{owner_id.lower()}@example.com',
                                                 'authorizedDrivers': [{'fullName': 'Cass Case', 'relationship': 'Self (Owner)', 'licenseNo': 'N/A'}]}, admin)
        v = res['data']
        call('POST', 'payments.php', {'action': 'cash', 'vehicleId': v['id']}, admin)
        temp = v['studentAccount']['tempPassword']
        tok = call('POST', 'auth.php?action=login&realm=student', {'username': owner_id, 'password': temp})[1]['data']['token']
        call('POST', 'auth.php?action=change_password', {'current_password': temp, 'new_password': 'Student-Case-2026'}, tok)
        return v, tok

    def issue(v, type_='Parking in Fire Lane / Restricted Zone', notes='Blocking the hydrant'):
        code, res = call('POST', 'violations.php', {'vehicle_id': v['id'], 'type': type_, 'notes': notes}, guard)
        return 'V' + str(res['data']['violation']['id'])

    def act(key, token, **body):
        return call('POST', 'cases.php', {'key': key, **body}, token)

    def get(key, token=None):
        return call('GET', f'cases.php?key={key}', token=token or admin)[1]['data']

    v1, tok1 = reg('CSE 1001', 'CS-1')
    key = issue(v1)
    code, res = call('GET', 'cases.php', token=guard)
    row = [c for c in res['data']['cases'] if c['key'] == key]
    check('a new violation appears as an Open case (guards can list cases)', code == 200 and len(row) == 1 and row[0]['status'] == 'Open' and row[0]['type'] == 'Violation' and row[0]['step'] == 'Reported', row)
    check('the incident behind a violation is not listed twice', not [c for c in res['data']['cases'] if c['kind'] == 'incident' and c['plateNumber'] == 'CSE 1001'], '')
    check('the list has counts', res['data']['summary']['open'] >= 1 and res['data']['summary']['total'] >= 1, res['data']['summary'])
    code, v = verify({'plate': 'CSE 1001', 'gate_type': 'Ingress'}, guard)
    check('the gate scan shows the case holding the vehicle and its step', (v.get('case') or {}).get('key') == key and v['case']['step'] == 'Reported', v.get('case'))

    code, res = act(key, guard, action='contact', method='Carrier pigeon', result='No answer')
    check('an unknown contact method is refused -> 400', code == 400, res)
    code, res = act(key, guard, action='contact', method='Phone call', result='No answer', note='Rang three times')
    check('a guard logs a contact attempt', code == 200 and res['data']['case']['contactAttempts'] == 1 and res['data']['case']['step'] == 'Contact attempted', res)
    code, res = act(key, guard, action='note', note='INTERNAL-SECRET: owner seems evasive')
    check('a guard adds an internal note', code == 200, res)
    code, res = act(key, guard, action='police', reason='Cannot reach the owner')
    check('a guard cannot refer to the police -> 403', code == 403, code)
    code, res = act(key, guard, action='close', outcome='Clearance signed', notes='Done')
    check('a guard cannot close a case -> 403', code == 403, code)

    code, res = act(key, admin, action='police')
    check('referring to the police needs a reason -> 400', code == 400 and res['data']['code'] == 'REASON_REQUIRED', res)
    code, res = act(key, admin, action='police', reason='Owner unreachable after repeated attempts', reference='BLOTTER-2026-114')
    check('admin refers it to the police', code == 200 and res['data']['case']['policeReferred'] is True and res['data']['case']['step'] == 'Referred to police', res)
    code, res = act(key, admin, action='police', reason='Again please')
    check('...only once -> 409', code == 409, res)
    rows = call('GET', 'student.php?action=notices', token=tok1)[1]['data']
    check('the owner is told the case was referred to the police', any('referred it to the police' in r['message'] for r in rows), rows)

    code, res = act(key, guard, action='awaiting', note='Owner phoned back, coming tomorrow')
    check('a guard marks it as waiting for the owner', code == 200 and res['data']['case']['status'] == 'Awaiting clearance', res)
    code, res = act(key, guard, action='awaiting')
    check('...only once -> 409', code == 409, res)
    code, res = call('GET', 'cases.php?status=awaiting', token=admin)
    check('the Awaiting clearance filter finds it', any(c['key'] == key for c in res['data']['cases']), '')

    code, res = call('GET', 'student.php?action=cases', token=tok1)
    mine = [c for c in res['data'] if c['key'] == key]
    blob = json.dumps(res['data'])
    check('the owner sees the case with a plain-language next step', len(mine) == 1 and 'Security Office' in mine[0]['nextStep'] and mine[0]['status'] == 'Awaiting clearance', mine)
    check('...the timeline shows the steps but no staff names and no internal notes', len(mine[0]['timeline']) >= 4 and 'INTERNAL-SECRET' not in blob and 'QA Guard' not in blob and 'BLOTTER' not in blob, blob[:300])
    code, res = call('GET', 'student.php?action=cases', token=reg('CSE 9009', 'CS-9')[1])
    check("another owner does not see this case", not [c for c in res['data'] if c['key'] == key], '')

    code, res = act(key, admin, action='close', outcome='Clearance signed')
    check('closing needs notes -> 400', code == 400, res)
    code, res = act(key, admin, action='close', outcome='Paid in gold', notes='Signed at the office')
    check('an unknown outcome is refused -> 400', code == 400, res)
    code, res = act(key, admin, action='close', outcome='Clearance signed', notes='Owner signed the clearance form at the Security Office')
    check('admin closes it with an outcome', code == 200 and res['data']['case']['status'] == 'Closed' and res['data']['case']['outcome'] == 'Clearance signed', res)
    code, res = call('GET', 'vehicles.php?plate=CSE1001', token=admin)
    check('...the hold is lifted', res['data']['isBanned'] is False and res['data']['registrationStatus'] == 'Active', res['data'])
    d = get(key)
    check('...the timeline records every step in order, with who did it', [t['type'] for t in d['timeline']] == ['reported', 'contact', 'note', 'police', 'awaiting', 'closed'] and d['timeline'][-1]['by'], [t['type'] for t in d['timeline']])
    code, res = act(key, admin, action='note', note='Late note')
    check('a closed case accepts no more steps -> 409', code == 409, res)
    code, res = call('GET', 'audit.php?action=case.&q=CSE1001', token=admin)
    check('contact, police and close are in the audit log', {'case.contact', 'case.police', 'case.close'} <= {r['action'] for r in res['data']['rows']}, {r['action'] for r in res['data']['rows']})

    v2, _ = reg('CSE 2002', 'CS-2')
    k2 = issue(v2, 'Overnight / Unauthorized Overtime Parking', 'Still on campus')
    check('an overnight violation is typed Overnight', get(k2)['type'] == 'Overnight', get(k2)['type'])
    code, res = act(k2, admin, action='police', reason='Owner is not answering')
    check('police referral before any contact attempt -> 409 CONTACT_REQUIRED', code == 409 and res['data']['code'] == 'CONTACT_REQUIRED', res)
    act(k2, admin, action='contact', method='In person', result='Wrong or unreachable number')
    code, res = act(k2, admin, action='close', outcome='Dismissed', notes='Issued against the wrong vehicle')
    check('with one administrator a dismissal is applied directly', code == 200 and res['data']['case']['outcome'] == 'Dismissed', res)
    code, res = call('GET', 'vehicles.php?plate=CSE2002', token=admin)
    check('...and the hold is lifted', res['data']['isBanned'] is False, res['data'])
    code, res = call('GET', 'cases.php?status=closed&type=Overnight', token=admin)
    check('the closed and type filters work', any(c['key'] == k2 for c in res['data']['cases']) and not any(c['key'] == key for c in res['data']['cases']), '')

    v3, _ = reg('CSE 3003', 'CS-3')
    code, res = call('POST', 'incidents.php', {'plateNumber': 'CSE 3003', 'reason': 'Unauthorized driver at the gate', 'ownerName': 'Cass Case', 'gatePoint': 'Gate 1 (Main Ingress)'}, guard)
    k3 = 'I' + str(res['data']['id'])
    c3 = get(k3)
    check('a flagged vehicle is a Security case', c3['type'] == 'Security' and c3['status'] == 'Open' and c3['caseNumber'], c3)
    code, res = act(k3, admin, action='close', outcome='Clearance signed', notes='Driver identified as the owner brother')
    check('admin closes a security case', code == 200 and res['data']['case']['status'] == 'Closed', res)
    code, res = call('GET', 'vehicles.php?plate=CSE3003', token=admin)
    check('...the vehicle is released from Blocked / Alert', res['data']['status'] != 'Blocked / Alert', res['data']['status'])
    code, res = call('GET', 'cases.php?key=V999999', token=admin)
    check('an unknown case -> 404', code == 404, code)
    code, res = call('GET', 'cases.php?key=oops', token=admin)
    check('a malformed key -> 404', code == 404, code)

    # history: closed cases stay findable by plate, outcome, date and text, page by page, and can be exported
    code, res = call('GET', 'cases.php?status=closed&plate=CSE-1001', token=admin)
    check("history by plate (any spelling) finds that vehicle's closed case", code == 200 and res['data']['total'] == 1 and res['data']['cases'][0]['key'] == key, res['data'].get('total'))
    code, res = call('GET', 'cases.php?status=closed&outcome=Dismissed', token=admin)
    check('history by outcome', any(c['key'] == k2 for c in res['data']['cases']) and all(c['outcome'] == 'Dismissed' for c in res['data']['cases']), '')
    code, res = call('GET', 'cases.php?status=closed&from=2999-01-01', token=admin)
    check('history by closing date (nothing closed in the far future)', res['data']['total'] == 0, res['data']['total'])
    code, res = call('GET', 'cases.php?status=closed&from=2000-01-01&to=2999-12-31&plate=CSE1001', token=admin)
    check('history inside a date range', res['data']['total'] == 1, res['data']['total'])
    code, res = call('GET', 'cases.php?status=closed&q=hydrant', token=admin)
    check('history by text (violation notes)', any(c['key'] == key for c in res['data']['cases']), '')
    code, res = call('GET', 'cases.php?status=all&limit=2&page=2', token=admin)
    check('pages: page 2 of 2-per-page', code == 200 and res['data']['page'] == 2 and len(res['data']['cases']) == 2 and res['data']['total'] > 4, (res['data']['page'], res['data']['total']))
    code, res = call('GET', 'cases.php?status=all&plate=CSE1001', token=admin)
    check("a vehicle's full case history (for its record)", res['data']['total'] >= 1 and all(c['plateNumber'] == 'CSE 1001' for c in res['data']['cases']), res['data']['total'])
    code, res = call('GET', 'cases.php?status=closed&format=csv', token=guard)
    check('only admins can export -> 403', code == 403, code)
    req = urllib.request.Request(f'{BASE}/cases.php?status=closed&format=csv', headers={'Authorization': f'Bearer {admin}'})
    with urllib.request.urlopen(req) as r:
        body = r.read().decode('utf-8-sig')
        check('admin exports the matching cases as CSV', r.headers.get('Content-Type', '').startswith('text/csv') and body.splitlines()[0].startswith('Case,Type,Plate')
              and 'CSE 1001' in body and 'Clearance signed' in body, body[:120])
    AUTO_PAY = True


def test_visitor_photo(admin):
    """The photo of a visitor's vehicle is stored with the pass and reaches the exit guard."""
    import base64
    section('Visitor vehicle photo')
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']
    jpeg = 'data:image/jpeg;base64,' + base64.b64encode(b'\xff\xd8\xff\xe0' + b'\x00' * 300 + b'\xff\xd9').decode()

    def issue(plate, photo):
        body = {'visitorName': 'Pat Photo', 'contactNumber': '0917 111 2222', 'plateNumber': plate, 'purposeOfVisit': 'Meeting', 'personToVisit': 'Registrar'}
        if photo is not None:
            body['vehiclePhoto'] = photo
        return call('POST', 'visitors.php', body, guard)

    code, res = issue('VPH 1001', jpeg)
    check('a pass issued with a vehicle photo keeps it', code == 201 and res['data']['hasVehiclePhoto'] is True and res['data']['vehiclePhoto'].startswith('data:image/jpeg;base64,'), res)
    code, res = call('GET', 'visitors.php', token=admin)
    row = [r for r in res['data'] if r['plateNumber'] == 'VPH1001']
    check('lists say there is a photo but do not carry the heavy picture', row and row[0]['hasVehiclePhoto'] is True and row[0]['vehiclePhoto'] is None, row)
    code, res = call('GET', 'visitors.php?q=VPH1001', token=admin)
    check('looking a pass up by plate or code returns its photo (gate records and the phone use this)', code == 200 and (res['data'].get('vehiclePhoto') or '').startswith('data:image/jpeg'), res)
    code, v = verify({'plate': 'VPH 1001', 'gate_type': 'Egress'}, guard)
    check('the gate scan carries the photo for the exit guard to compare', (v.get('visitor') or {}).get('vehiclePhoto', '').startswith('data:image/jpeg'), list((v.get('visitor') or {}).keys()))
    code, res = issue('VPH 2002', 'assets/images/kriz_monares.jpg')
    check('an old app placeholder path is ignored, the pass is still issued', code == 201 and res['data']['hasVehiclePhoto'] is False, res)
    code, res = issue('VPH 3003', 'data:image/jpeg;base64,' + base64.b64encode(b'<html>not an image</html>').decode())
    check('something that is not a picture is ignored, the pass is still issued', code == 201 and res['data']['hasVehiclePhoto'] is False, res)
    code, res = issue('VPH 4004', 'data:image/jpeg;base64,' + base64.b64encode(b'\xff\xd8\xff' + b'0' * 700000).decode())
    check('an oversized picture is ignored, the pass is still issued', code == 201 and res['data']['hasVehiclePhoto'] is False, res)
    code, res = issue('VPH 5005', None)
    check('no photo at all is fine', code == 201 and res['data']['vehiclePhoto'] is None, res)

    # a security case raised for a plate that only has a visitor pass names the visitor, not "Unknown"
    import sqlite3
    code, res = call('POST', 'incidents.php', {'plateNumber': 'VPH 1001', 'reason': 'Unauthorized / Unregistered Driver'}, guard)
    incident_id = res['data']['id']
    key = 'I' + str(incident_id)
    check('a case for a visitor plate names the visitor, not Unknown', call('GET', f'cases.php?key={key}', token=admin)[1]['data']['ownerName'] == 'Pat Photo', '')
    db = sqlite3.connect(SQLITE_DB)
    db.execute("UPDATE security_incidents SET owner_name = 'Unknown' WHERE id = ?", (incident_id,))
    db.commit()
    db.close()
    rows = call('GET', 'cases.php?status=all&q=VPH1001', token=admin)[1]['data']['cases']
    check('a case saved earlier as Unknown shows the visitor name in the list too', any(c['key'] == key and c['ownerName'] == 'Pat Photo' for c in rows), [c['ownerName'] for c in rows])
    code, res = call('POST', 'incidents.php', {'plateNumber': 'ZZZ 0000', 'reason': 'Unauthorized / Unregistered Driver'}, guard)
    check('a plate nobody knows stays Unknown', call('GET', f"cases.php?key=I{res['data']['id']}", token=admin)[1]['data']['ownerName'] == 'Unknown', '')


def test_oncampus_after_case(admin):
    """Closing a case stops the On Campus screen from showing the vehicle / visitor as blocked."""
    import time
    global AUTO_PAY
    section('On Campus: a closed case no longer shows as blocked')
    AUTO_PAY = False
    guard = login('guard.qa', 'Guard-QA-2026')[1]['data']['token']

    def on_campus(kind, plate):
        data = call('GET', 'oncampus.php', token=admin)[1]['data']
        return [r for r in data[kind] if r['plateNumber'].replace(' ', '').replace('-', '') == plate.replace(' ', '')][0]

    def deny_exit_and_flag(plate, extra):
        call('POST', 'logs.php', {'plate': plate, 'action': 'Exit Denied', 'gate_type': 'Egress', **extra}, guard)

    # ---- a registered vehicle
    code, res = call('POST', 'vehicles.php', {'plateNumber': 'OCC 1001', 'ownerName': 'Olive Campus', 'ownerIdNumber': 'OC-1', 'vehicleType': '4-Wheel',
                                              'authorizedDrivers': [{'fullName': 'Olive Campus', 'relationship': 'Self (Owner)', 'licenseNo': 'N/A'}]}, admin)
    veh = res['data']
    call('POST', 'payments.php', {'action': 'cash', 'vehicleId': veh['id']}, admin)
    driver = int(veh['authorizedDrivers'][0]['id'])
    code, res = call('POST', 'logs.php', {'plate': 'OCC 1001', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'driver_id': driver}, guard)
    check('vehicle enters', code == 201, res)
    time.sleep(1.1)
    deny_exit_and_flag('OCC 1001', {'driver_id': driver})
    code, res = call('POST', 'incidents.php', {'plateNumber': 'OCC 1001', 'reason': 'Unauthorized / Unregistered Driver'}, guard)
    key = 'I' + str(res['data']['id'])
    row = on_campus('vehicles', 'OCC1001')
    check('after a blocked exit the vehicle shows as blocked', row['exitDenied'] is True and row['activeHold'] is not None, row)
    time.sleep(1.1)
    code, res = call('POST', 'cases.php', {'key': key, 'action': 'close', 'outcome': 'Clearance signed', 'notes': 'Owner cleared this at the Security Office'}, admin)
    check('the case is closed', code == 200, res)
    row = on_campus('vehicles', 'OCC1001')
    check('after the case is closed the vehicle is no longer blocked', row['exitDenied'] is False and row['activeHold'] is None, row)
    time.sleep(1.1)
    deny_exit_and_flag('OCC 1001', {'driver_id': driver})
    check('a NEW refused exit after the closure flags it again', on_campus('vehicles', 'OCC1001')['exitDenied'] is True, '')

    # ---- a visitor
    code, res = call('POST', 'visitors.php', {'visitorName': 'Maria Santos', 'contactNumber': '0917 222 3333', 'plateNumber': 'OCC 2002', 'purposeOfVisit': 'Meeting', 'personToVisit': 'Registrar'}, guard)
    pass_id = res['data']['id']
    code, res = call('POST', 'logs.php', {'plate': 'OCC 2002', 'action': 'Entry Recorded', 'gate_type': 'Ingress', 'visitor_pass_id': pass_id, 'driverName': 'Maria Santos'}, guard)
    check('visitor enters', code == 201, res)
    time.sleep(1.1)
    deny_exit_and_flag('OCC 2002', {'visitor_pass_id': pass_id, 'driverName': 'Maria Santos'})
    code, res = call('POST', 'incidents.php', {'plateNumber': 'OCC 2002', 'reason': 'Unauthorized / Unregistered Driver'}, guard)
    vkey = 'I' + str(res['data']['id'])
    row = on_campus('visitors', 'OCC2002')
    check('after a blocked exit the visitor shows as blocked', row['exitDenied'] is True and row['activeHold'] is not None, row)
    time.sleep(1.1)
    code, res = call('POST', 'cases.php', {'key': vkey, 'action': 'close', 'outcome': 'Clearance signed', 'notes': 'Visitor cleared by the Security Office'}, admin)
    row = on_campus('visitors', 'OCC2002')
    check('after the case is closed the visitor is no longer blocked', code == 200 and row['exitDenied'] is False and row['activeHold'] is None, row)
    AUTO_PAY = True


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
    test_payments(admin)
    test_vehicle_classes(admin)
    test_loophole_fixes(admin)
    test_owner_notices(admin)
    test_ops_phase2(admin)
    test_cases(admin)
    test_visitor_photo(admin)
    test_oncampus_after_case(admin)
    test_audit_and_approvals(admin)
    print(f'\n{passed} passed, {failed} failed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
