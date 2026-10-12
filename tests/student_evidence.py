"""Evidence photos in the owner portal: listed with each case / passage / flag, fetched one at a time, and only the owner's own."""
from pathlib import Path
import base64
import json
from movement_integration import Sandbox, call

JPEG = base64.b64encode(b'\xff\xd8\xff\xe0' + b'\x00' * 200 + b'\xff\xd9').decode()


def run():
    results = []

    def check(name, condition, detail=None):
        assert condition, (name, detail)
        results.append(name)
        print('PASS', name)

    with Sandbox() as s:
        base = s.bases[0]

        def req(path, body=None, token=None, method='POST'):
            return call(base, path, body, token, method)

        admin = req('auth.php?action=login', {'username': 'admin', 'password': 'Password123!'})[1]['data']['token']
        check('admin changes temporary password', req('auth.php?action=change_password', {
            'current_password': 'Password123!', 'new_password': 'Evidence-Admin-2026'}, admin)[0] == 200)
        guard_pw = 'Evidence-Guard-2026'
        c, r = req('users.php', {'username': 'guard.ev', 'full_name': 'Evidence Guard', 'role': 'guard', 'password': guard_pw, 'gate_assigned': 'Gate 1'}, admin)
        guard = req('auth.php?action=login', {'username': 'guard.ev', 'password': guard_pw})[1].get('data', {}).get('token')
        check('a guard account exists', bool(guard), (c, r))

        def register(plate, owner_id, name):
            c, r = req('vehicles.php', {'plateNumber': plate, 'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': name, 'ownerRole': 'Student',
                                        'ownerIdNumber': owner_id, 'stickerYear': '2026'}, admin)
            assert c == 201, r
            acct = r['data']['studentAccount']
            t = req('auth.php?action=login&realm=student', {'username': owner_id, 'password': acct['tempPassword']})[1]['data']['token']
            assert req('auth.php?action=change_password', {'current_password': acct['tempPassword'], 'new_password': 'Student-Ev-2026'}, t)[0] == 200
            return r['data'], req('auth.php?action=login&realm=student', {'username': owner_id, 'password': 'Student-Ev-2026'})[1]['data']['token']

        mine, mine_tok = register('EVD 1001', 'EV-1001', 'Eva Owner')
        other, other_tok = register('EVD 2002', 'EV-2002', 'Otto Other')

        c, v = req('violations.php', {'vehicle_id': mine['id'], 'type': 'Parking in Fire Lane / Restricted Zone', 'notes': 'Seen by patrol'}, guard)
        check('guard issues a violation', c == 201, v)
        c, listing = req('violations.php?plate=EVD%201001', token=admin, method='GET')
        vid = listing['data'][0]['id']
        photos = []
        for _ in range(2):
            c, r = req('evidence.php', {'kind': 'violation', 'plate': 'EVD 1001', 'violationId': vid, 'image': JPEG}, guard)
            check('guard attaches a violation photo', c == 201, r)
            photos.append(r['data']['id'])
        c, inc = req('incidents.php', {'plateNumber': 'EVD 2002', 'reason': 'Unauthorized Driver at Helm', 'driverName': 'Stranger'}, guard)
        c, r = req('evidence.php', {'kind': 'incident', 'plate': 'EVD 2002', 'incidentId': inc['data']['id'], 'image': JPEG}, guard)
        other_photo = r['data']['id']

        # the case lists its photos (details only, never the picture)
        c, cases = req('student.php?action=cases', token=mine_tok, method='GET')
        case = [x for x in cases['data'] if x['key'] == f'V{vid}'][0]
        check('the owner\'s case lists both photos', [p['id'] for p in case['evidence']] == photos, case['evidence'])
        check('the list carries no picture and no staff name', all(set(p) == {'id', 'kind', 'takenAt', 'purged'} for p in case['evidence']), case['evidence'])
        check('the case has a readable reference', case.get('reference', '').startswith('VIO-'), case.get('reference'))

        # one picture at a time
        c, photo = req(f'student.php?action=evidence&id={photos[0]}', token=mine_tok, method='GET')
        check('the owner can fetch the picture of their own case', c == 200 and photo['data']['image'].startswith('data:image/jpeg;base64,'), photo)
        c, r = req(f'student.php?action=evidence&id={other_photo}', token=mine_tok, method='GET')
        check('...but not a photo from another owner\'s vehicle -> 404', c == 404, r)
        c, r = req(f'student.php?action=evidence&id=99999', token=mine_tok, method='GET')
        check('an unknown photo -> 404', c == 404, r)
        c, r = req(f'student.php?action=evidence&id={photos[0]}', token=other_tok, method='GET')
        check('the other owner cannot fetch it either -> 404', c == 404, r)
        c, r = req(f'student.php?action=evidence&id={photos[0]}', method='GET')
        check('no sign-in -> 401', c == 401, r)

        # the other owner sees the incident photo on the flag
        c, alerts = req('student.php?action=alerts', token=other_tok, method='GET')
        check('a flag lists its photo', [p['id'] for p in alerts['data']['active'][0]['evidence']] == [other_photo], alerts['data'])
        c, cases2 = req('student.php?action=cases', token=other_tok, method='GET')
        check('the security case lists its photo too', [p['id'] for p in cases2['data'][0]['evidence']] == [other_photo], cases2['data'])

        # a photo removed by the retention job still lists, but has no picture
        import sqlite3
        from contextlib import closing
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute("UPDATE evidence_photos SET data = NULL, purged_at = '2026-10-12 00:00:00' WHERE id = ?", (photos[1],))
        c, photo = req(f'student.php?action=evidence&id={photos[1]}', token=mine_tok, method='GET')
        check('a purged photo reports purged and has no picture', c == 200 and photo['data']['purged'] is True and photo['data']['image'] is None, photo)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/student-evidence-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
