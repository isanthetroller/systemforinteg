"""Isolated real-PHP/SQLite movement tests. Never opens the project's existing database.
Run: python tests/movement_integration.py [--smoke]
Two PHP workers share a disposable database to exercise competing confirmations.
"""
from contextlib import closing
import concurrent.futures
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import base64

ROOT = Path(__file__).resolve().parents[1]
PHP = os.environ.get('SP_TEST_PHP', r'C:\xampp\php\php.exe')
passed = 0


def check(name, ok):
    global passed
    if not ok:
        raise AssertionError(name)
    passed += 1
    print('PASS', name)


def call(base, path, body=None, token=None, method='POST', extra_headers=None):
    headers = {'Content-Type': 'application/json', **(extra_headers or {})}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(base + '/' + path, data=json.dumps(body).encode() if body is not None else None,
                                     headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


class Sandbox:
    def __enter__(self):
        self.temp = tempfile.TemporaryDirectory(prefix='securepark-movement-')
        self.root = Path(self.temp.name)
        self.servers = []
        self.logs = []
        self.key = secrets.token_hex(32)
        target = self.root / 'web-app-admin'
        for folder in ('api', 'lib', 'config', 'database'):
            shutil.copytree(ROOT / 'backend' / folder, target / folder,
                            ignore=shutil.ignore_patterns('secret.php', 'secret.production.php', 'data'))
        secret = (target / 'config' / 'secret.example.php').read_text(encoding='utf-8')
        self.scanner_key = secrets.token_hex(32)
        secret = secret.replace('CHANGE_ME_64_HEX_CHARS', self.key).replace('CHANGE_ME_SCANNER_KEY', self.scanner_key)
        secret = secret.replace("define('SP_DEBUG', false)", "define('SP_DEBUG', true)")
        secret += "\ndefine('SP_FORCE_SQLITE', true);\n"
        (target / 'config' / 'secret.php').write_text(secret, encoding='utf-8')
        (self.root / 'backend' / 'config').mkdir(parents=True)
        (self.root / 'backend' / 'config' / 'secret.php').write_text(secret, encoding='utf-8')
        self.db = target / 'data' / 'securepark.sqlite'
        self.bases = []
        for _ in range(2):
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            log = tempfile.TemporaryFile()
            self.logs.append(log)
            self.servers.append(subprocess.Popen([PHP, '-S', f'127.0.0.1:{port}', '-t', str(self.root)],
                                                  stdout=log, stderr=log))
            self.bases.append(f'http://127.0.0.1:{port}/web-app-admin/api')
            for attempt in range(50):
                try:
                    call(self.bases[-1], 'status.php', method='GET')
                    break
                except (OSError, ValueError):
                    time.sleep(.1)
            else:
                raise RuntimeError('Test PHP server did not start')
        return self

    def __exit__(self, *_):
        for server in self.servers:
            server.terminate()
            server.wait(timeout=10)
        for log in self.logs:
            log.close()
        self.temp.cleanup()


def run(s):
    base = s.bases[0]
    status, response = call(base, 'auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})
    assert status == 200, response
    admin = response['data']['token']
    call(base, 'auth.php?action=change_password', {'current_password': 'Password123!', 'new_password': 'Movement-Admin-2026'}, admin)
    guards = []
    for n in (1, 2):
        status, response = call(base, 'users.php', {'username': f'guard{n}', 'full_name': f'Guard {n}',
            'role': 'guard', 'password': 'Movement-Guard-2026', 'gate_assigned': f'Checkpoint {n}'}, admin)
        assert status == 201, response
        response = call(base, 'auth.php?action=login', {'username': f'guard{n}', 'password': 'Movement-Guard-2026'})[1]
        guards.append(response['data']['token'])
    vehicle_body = {'plateNumber': 'MOVE 100', 'vehicleType': '4-Wheel', 'makeModelColor': 'Blue test car',
                    'ownerName': 'Movement Owner', 'ownerRole': 'Student', 'ownerIdNumber': 'MOVEMENT-OWNER',
                    'stickerYear': '2026', 'registrationStatus': 'Active'}
    status, response = call(base, 'vehicles.php', vehicle_body, admin)
    assert status == 201, response
    vehicle = response['data']
    qr = vehicle['qrPayload']
    driver = vehicle['authorizedDrivers'][0]['id']

    def state():
        with closing(sqlite3.connect(s.db)) as db, db:
            return db.execute('SELECT status FROM vehicles WHERE id=?', (vehicle['id'],)).fetchone()[0], db.execute('SELECT count(*) FROM gate_logs').fetchone()[0]

    def prepare(guard, qr_value=qr, worker=0):
        code, result = call(s.bases[worker], 'movements.php', {'action': 'prepare', 'qr_code': qr_value}, guard)
        assert code == 200, result
        return result['data']

    def confirm(guard, preview, worker=0, **extra):
        return call(s.bases[worker], 'movements.php', {'action': 'confirm', 'ticket': preview['movement']['ticket'], 'driver_id': driver, **extra}, guard)

    for entry_guard, exit_guard in ((0, 0), (0, 1), (1, 0), (1, 1)):
        before = state()
        preview = prepare(guards[entry_guard])
        check(f'G{entry_guard+1} entry suggestion', preview['movement']['suggestedAction'] == 'IN' and preview['movement']['currentStatus'] == 'OUTSIDE')
        check('prepare/cancel leaves database untouched', state() == before)
        code, saved = confirm(guards[entry_guard], preview)
        check('entry confirmed exactly once', code == 201 and state() == ('Inside Campus', before[1]+1))
        with closing(sqlite3.connect(s.db)) as db, db:
            log = db.execute('SELECT gate_point, logged_by_user_id, gate_type FROM gate_logs WHERE id=?', (saved['data']['id'],)).fetchone()
        check('checkpoint recorded independently of direction', log[0] == f'Checkpoint {entry_guard+1}' and log[1] is not None and log[2] == 'Ingress')
        code, replay = confirm(guards[entry_guard], preview)
        check('duplicate entry cannot toggle to exit', code == 200 and replay['data']['duplicate'] and state() == ('Inside Campus', before[1]+1))
        out = prepare(guards[exit_guard])
        check(f'G{exit_guard+1} exit suggestion', out['movement']['suggestedAction'] == 'OUT')
        code, saved = confirm(guards[exit_guard], out)
        check('exit confirmed and history preserved', code == 201 and state() == ('Outside', before[1]+2))
        code, replay = confirm(guards[exit_guard], out)
        check('lost-response exit retry cannot create entry', code == 200 and state() == ('Outside', before[1]+2))

    before = state()
    a, b = prepare(guards[0]), prepare(guards[1], worker=1)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda args: confirm(*args), [(guards[0], a, 0), (guards[1], b, 1)]))
    check('two simultaneous guards: one save, one stale rejection', sorted(x[0] for x in results) == [201, 409])
    check('concurrent status/history agree', state() == ('Inside Campus', before[1]+1))
    confirm(guards[0], prepare(guards[0]))

    before = state()
    same = prepare(guards[0])
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda worker: confirm(guards[0], same, worker), (0, 1)))
    check('simultaneous duplicate confirmation returns one saved result', sorted(x[0] for x in results) == [200, 201] and state() == ('Inside Campus', before[1]+1))
    confirm(guards[0], prepare(guards[0]))

    before = state()
    retry = prepare(guards[0])
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute("CREATE TRIGGER test_fail_log BEFORE INSERT ON gate_logs BEGIN SELECT RAISE(ABORT, 'isolated test failure'); END")
    check('failed confirmation rolls back both history and state', confirm(guards[0], retry)[0] == 503 and state() == before)
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute('DROP TRIGGER test_fail_log')
    check('same confirmation safely retries after server failure', confirm(guards[0], retry)[0] == 201 and state() == ('Inside Campus', before[1]+1))
    confirm(guards[0], prepare(guards[0]))

    old = prepare(guards[0])
    confirm(guards[1], prepare(guards[1]))
    confirm(guards[1], prepare(guards[1]))
    before = state()
    code, rejected = confirm(guards[0], old)
    check('stale snapshot rejected even after IN/OUT returns to same status', code == 409 and rejected['data']['code'] == 'STALE_SCAN' and state() == before)
    old = prepare(guards[0])
    check('other guard cannot use confirmation ticket', confirm(guards[1], old)[0] == 403)
    body = {'action': 'confirm', 'ticket': old['movement']['ticket'] + 'tampered', 'driver_id': driver}
    check('tampered ticket rejected', call(base, 'movements.php', body, guards[0])[0] == 400)
    check('anonymous prepare rejected', call(base, 'movements.php', {'action': 'prepare', 'qr_code': qr})[0] == 401)
    check('device key alone cannot impersonate a guard', call(base, 'movements.php', {'action': 'prepare', 'qr_code': qr}, extra_headers={'X-Api-Key': s.scanner_key})[0] == 401)
    check('missing driver rejected without writes', confirm(guards[0], old, driver_id=0)[0] == 400 and state() == before)
    forged = json.loads(qr)
    forged['plate_number'] = 'FORGED-999'
    check('invalid signed QR rejected without transaction', prepare(guards[0], json.dumps(forged))['accepted'] is False and state() == before)
    check('unregistered QR rejected without transaction', prepare(guards[0], 'UNKNOWN-999')['accepted'] is False and state() == before)

    # Expiry: sign a fixture ticket with the disposable sandbox's own test key.
    encoded, _ = old['movement']['ticket'].split('.')
    snapshot = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
    snapshot['expires'] = int(time.time()) - 1
    encoded = base64.urlsafe_b64encode(json.dumps(snapshot).encode()).decode().rstrip('=')
    expired = encoded + '.' + hmac.new(s.key.encode(), ('movement:' + encoded).encode(), hashlib.sha256).hexdigest()
    code, response = call(base, 'movements.php', {'action': 'confirm', 'ticket': expired, 'driver_id': driver}, guards[0])
    check('expired scan rejected without writes', code == 409 and response['data']['code'] == 'SCAN_EXPIRED' and state() == before)

    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute('UPDATE vehicles SET is_banned=1 WHERE id=?', (vehicle['id'],))
    check('ban introduced after scan blocks confirmation', confirm(guards[0], old)[0] == 403 and state() == before)
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute('UPDATE vehicles SET is_banned=0, pass_id=? WHERE id=?', ('changed-pass', vehicle['id']))
    check('reissued pass invalidates previous confirmation', confirm(guards[0], old)[0] == 409 and state() == before)

    # Owner credentials cannot use the staff movement endpoint.
    with closing(sqlite3.connect(s.db)) as db, db:
        owner_id = db.execute('SELECT id FROM student_accounts LIMIT 1').fetchone()[0]
        token = secrets.token_hex(32)
        db.execute("INSERT INTO auth_tokens(token_hash,user_type,user_id,expires_at) VALUES(?,?,?,datetime('now','+1 day'))", (hashlib.sha256(token.encode()).hexdigest(), 'student', owner_id))
    check('owner account cannot confirm staff movement', call(base, 'movements.php', {'action': 'confirm', 'ticket': old['movement']['ticket']}, token)[0] == 401)
    check('all rejected requests preserve state/history', state() == before)

    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute("UPDATE vehicles SET pass_id=?, registration_status='Suspended' WHERE id=?", (vehicle['passId'], vehicle['id']))
    check('suspended vehicle cannot prepare a movement', prepare(guards[0])['accepted'] is False)
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute("UPDATE vehicles SET registration_status='Active' WHERE id=?", (vehicle['id'],))
    pending = prepare(guards[0])
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute("INSERT INTO security_incidents(case_number,plate_number,driver_name,reason,status,reported_at) VALUES('MOVEMENT-HOLD','MOVE 100','Test Driver','Test hold','Held',datetime('now'))")
    check('hold created after scan is rechecked on confirmation', confirm(guards[0], pending)[0] == 403 and state() == before)
    with closing(sqlite3.connect(s.db)) as db, db:
        db.execute("DELETE FROM security_incidents WHERE case_number='MOVEMENT-HOLD'")
        db.execute("UPDATE vehicles SET pass_class='VIP' WHERE id=?", (vehicle['id'],))
    pending = prepare(guards[1])
    check('VIP entry retains exemption from driver selection', confirm(guards[1], pending, driver_id=0)[0] == 201)
    check('VIP exit works at same checkpoint', confirm(guards[1], prepare(guards[1]), driver_id=0)[0] == 201)
    code, replay = confirm(guards[1], pending, driver_id=0)
    check('delayed replay reports current status without replaying old entry', code == 200 and replay['data']['currentStatus'] == 'OUTSIDE' and replay['data']['recordedStatus'] == 'INSIDE')

    code, response = call(base, 'visitors.php', {'visitor_name': 'Test Visitor', 'contact_number': '09170000000',
        'plate': 'VISIT 100', 'purpose': 'Test visit', 'person_to_visit': 'Security',
        'items': [{'name': 'Tools', 'quantity': 2}]}, guards[1])
    assert code == 201, response
    visitor_qr = response['data']['qrPayload']
    pending = prepare(guards[1], visitor_qr)
    check('visitor entry automatically detected at checkpoint 2', pending['movement']['suggestedAction'] == 'IN')
    check('visitor items must be checked before saving', confirm(guards[1], pending, driver_id=0)[0] == 400)
    check('visitor entry saves after item confirmation', confirm(guards[1], pending, driver_id=0, items_verified=True)[0] == 201)
    out = prepare(guards[0], visitor_qr)
    check('visitor exit detected at other checkpoint', out['movement']['suggestedAction'] == 'OUT')
    check('visitor exit saves after item confirmation', confirm(guards[0], out, driver_id=0, items_verified=True)[0] == 201)
    check('completed visitor pass cannot re-enter', prepare(guards[1], visitor_qr)['accepted'] is False)
    print(f'\n{passed} movement checks passed. Disposable database only.')


if __name__ == '__main__':
    if '--baseline-smoke' not in sys.argv:
        with Sandbox() as sandbox:
            run(sandbox)
    if '--smoke' in sys.argv or '--baseline-smoke' in sys.argv:
        with Sandbox() as sandbox:
            baseline = '--baseline-smoke' in sys.argv
            if baseline:
                for name in ('verify.php', 'logs.php', 'sync.php'):
                    content = subprocess.check_output(['git', 'show', f'HEAD:backend/api/{name}'], cwd=ROOT)
                    (sandbox.root / 'web-app-admin' / 'api' / name).write_bytes(content)
            (sandbox.root / 'tests').mkdir()
            shutil.copy2(ROOT / 'tests' / 'api_smoke.py', sandbox.root / 'tests' / 'api_smoke.py')
            result = subprocess.run([sys.executable, str(sandbox.root / 'tests' / 'api_smoke.py')],
                                    env={**os.environ, 'SP_API': sandbox.bases[0]}, capture_output=True, text=True)
            report = ROOT / 'artifacts' / ('movement-baseline-smoke.txt' if baseline else 'movement-regression-smoke.txt')
            report.write_text(result.stdout + '\n' + result.stderr, encoding='utf-8')
            print('Existing API smoke exit:', result.returncode, 'Report:', report)
            sys.exit(result.returncode)
