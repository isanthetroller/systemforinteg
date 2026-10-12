"""Fixed case references (SEC-0012 / VIO-0008) and no duplicate case for the same block."""
from pathlib import Path
import json
import re
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
            'current_password': 'Password123!', 'new_password': 'Reference-Admin-2026'})[0] == 200)
        c, r = req('users.php', {'username': 'refguard', 'full_name': 'Ref Guard', 'role': 'guard', 'password': 'Reference-Guard-2026', 'gate_assigned': 'Gate 1 (Main Ingress)'})
        assert c == 201, r
        guard = call(base, 'auth.php?action=login', {'username': 'refguard', 'password': 'Reference-Guard-2026'})[1]['data']['token']
        c, v = req('vehicles.php', {'plateNumber': 'REF100', 'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'Ref Owner',
                                    'ownerRole': 'Student', 'ownerIdNumber': 'OWNER-REF', 'stickerYear': '2026'})
        assert c == 201, v
        vehicle_id = v['data']['id']

        def active():
            c, r = req('cases.php?status=active&limit=100', method='GET')
            assert c == 200, r
            data = r['data']
            return data['cases'] if isinstance(data, dict) and 'cases' in data else data

        block = {'plateNumber': 'REF100', 'driverName': 'Ref Owner', 'reason': 'Unauthorized / Unregistered Driver', 'gatePoint': 'Gate 1 (Main Ingress)',
                 'notes': 'Entry blocked at the gate'}
        c, first = req('incidents.php', {**block, 'client_ref': 'ref-block-0001'}, guard)
        check('a block opens a case numbered SEC-####', c == 201 and re.fullmatch(r'SEC-\d{4}', first['data']['caseNumber']), first)
        number = first['data']['caseNumber']
        rows = active()
        check('the Cases list shows that same reference', len(rows) == 1 and rows[0]['reference'] == number, rows)
        check('the reference follows the case id', number == 'SEC-' + str(first['data']['id']).zfill(4))

        c, again = req('incidents.php', {**block, 'client_ref': 'ref-block-0002'}, guard)
        check('blocking again for the same reason returns the open case', c == 200 and again['data'].get('duplicate') is True and again['data']['caseNumber'] == number, again)
        check('no second case was created', len(active()) == 1)

        c, other = req('incidents.php', {**block, 'reason': 'Suspicious behavior', 'client_ref': 'ref-block-0003'}, guard)
        check('a different reason is a different case', c == 201 and other['data']['caseNumber'] != number, other)

        c, viol = req('violations.php', {'vehicle_id': vehicle_id, 'type': 'Other', 'notes': 'Reference test'}, guard)
        check('a violation is created', c == 201, viol)
        rows = active()
        vio = [x for x in rows if x['kind'] == 'violation']
        check('a violation case is numbered VIO-####', len(vio) == 1 and re.fullmatch(r'VIO-\d{4}', vio[0]['reference']), vio)
        check('every case has a reference', all(re.fullmatch(r'(SEC|VIO)-\d{4}', x['reference']) for x in rows), [x.get('reference') for x in rows])
        check('references are unique', len({x['reference'] for x in rows}) == len(rows))

        c, found = req('cases.php?status=all&q=' + number, method='GET')
        data = found['data']['cases'] if isinstance(found['data'], dict) else found['data']
        check('searching a reference finds exactly that case', c == 200 and [x['reference'] for x in data] == [number], data)
        c, found = req('cases.php?status=all&q=' + vio[0]['reference'].lower(), method='GET')
        data = found['data']['cases'] if isinstance(found['data'], dict) else found['data']
        check('search ignores case and finds the violation', [x['reference'] for x in data] == [vio[0]['reference']], data)
        c, none = req('cases.php?status=all&q=SEC-0999', method='GET')
        data = none['data']['cases'] if isinstance(none['data'], dict) else none['data']
        check('an unknown reference finds nothing', c == 200 and data == [], data)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/case-reference-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
