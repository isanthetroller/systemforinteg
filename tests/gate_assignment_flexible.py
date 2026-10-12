"""Guards whose assigned gate is not Gate 1 / Gate 2 (All Gates, Gate 3, blank) must still be able to record passages.

Regression for: 'Ask an administrator to assign Gate 1 or Gate 2 before recording a passage' shown to a guard assigned
'All Gates' or 'Gate 3 (Motorcycle & Bike Lane)'. Accounts locked to Gate 1 / Gate 2 must keep their direction rules.
"""
from contextlib import closing
from pathlib import Path
import json
import sqlite3
from movement_integration import Sandbox, call


def run():
    results = []
    def check(name, condition, detail=None):
        assert condition, (name, detail)
        results.append(name)
        print('PASS', name)

    with Sandbox() as s:
        base = s.bases[0]
        _, login = call(base, 'auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})
        admin = login['data']['token']
        def req(path, body=None, token=admin, method='POST'):
            return call(base, path, body, token, method)
        check('admin changes temporary password', req('auth.php?action=change_password', {
            'current_password': 'Password123!', 'new_password': 'Flexible-Gate-2026'})[0] == 200)

        def guard(username, gate):
            c, r = req('users.php', {'username': username, 'full_name': username, 'role': 'guard',
                                     'password': 'Flexible-Guard-2026', 'gate_assigned': gate})
            assert c == 201, r
            _, r = call(base, 'auth.php?action=login', {'username': username, 'password': 'Flexible-Guard-2026'})
            return r['data']['token']
        tokens = {
            'All Gates': guard('flexall', 'All Gates'),
            'Gate 3': guard('flexg3', 'Gate 3 (Motorcycle & Bike Lane)'),
            'Gate 1 locked': guard('lockg1', 'Gate 1 (Main Ingress)'),
            'Gate 2 locked': guard('lockg2', 'Gate 2 (Main Egress)'),
        }
        guard('flexblank', 'Gate 1 (Main Ingress)')
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute("UPDATE system_users SET gate_assigned='' WHERE username='flexblank'")
        _, r = call(base, 'auth.php?action=login', {'username': 'flexblank', 'password': 'Flexible-Guard-2026'})
        tokens['blank'] = r['data']['token']

        def vehicle(plate):
            c, r = req('vehicles.php', {'plateNumber': plate, 'vehicleType': 'Bicycle', 'category': 'non-plated',
                'ownerName': 'Flex Owner', 'ownerRole': 'Student', 'ownerIdNumber': 'OWNER-' + plate, 'stickerYear': '2026'})
            assert c == 201, r
            return r['data']
        def prepare(v, token):
            c, r = req('movements.php', {'action': 'prepare', 'qr_code': v['qrPayload']}, token)
            assert c == 200, r
            return r['data']
        def confirm(p, v, token):
            return req('movements.php', {'action': 'confirm', 'ticket': p['movement']['ticket'],
                                         'driver_id': v['authorizedDrivers'][0]['id']}, token)

        # Flexible accounts: entry then exit in NORMAL operation, each at the gate that matches the direction
        for n, label in enumerate(('All Gates', 'Gate 3', 'blank'), start=1):
            v = vehicle(f'FLX{n}00')
            token = tokens[label]
            p = prepare(v, token)
            check(f'{label}: entry is accepted (not "assign a gate")', p['accepted'] and p['result'] != 'GATE_DIRECTION_DENIED', p)
            check(f'{label}: entry recorded at Gate 1', p['movement']['checkpoint'] == 'Gate 1', p['movement'])
            check(f'{label}: entry saved', confirm(p, v, token)[0] == 201)
            p = prepare(v, token)
            check(f'{label}: exit is accepted in normal operation', p['accepted'] and p['result'] != 'GATE_DIRECTION_DENIED', p)
            check(f'{label}: exit recorded at Gate 2', p['movement']['checkpoint'] == 'Gate 2', p['movement'])
            check(f'{label}: exit saved', confirm(p, v, token)[0] == 201)

        # Accounts locked to a gate keep the old rules
        v = vehicle('FLX900')
        check('Gate 2 account still refuses entry', prepare(v, tokens['Gate 2 locked'])['result'] == 'GATE_DIRECTION_DENIED')
        p = prepare(v, tokens['Gate 1 locked']); check('Gate 1 account still permits entry', p['accepted'])
        check('Gate 1 account entry saved', confirm(p, v, tokens['Gate 1 locked'])[0] == 201)
        check('Gate 1 account still refuses exit', prepare(v, tokens['Gate 1 locked'])['result'] == 'GATE_DIRECTION_DENIED')

        # The policy endpoint shown on the phone no longer tells these guards to ask an administrator
        c, r = req('gate_policy.php', method='GET', token=tokens['All Gates'])
        check('policy endpoint: All Gates guard sees no "assign a gate" message',
              c == 200 and 'Ask an administrator' not in r['data']['message'] and r['data']['canSelectCheckpoint'], r)
        c, r = req('gate_policy.php', method='GET', token=tokens['Gate 1 locked'])
        check('policy endpoint: Gate 1 guard stays locked to Gate 1', c == 200 and r['data']['gateNumber'] == 1 and not r['data']['canSelectCheckpoint'], r)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/gate-assignment-flexible-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
