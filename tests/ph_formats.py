"""Philippine mobile numbers and driver's license numbers on the vehicle forms (server side)."""
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
            'current_password': 'Password123!', 'new_password': 'Formats-Admin-2026'})[0] == 200)

        n = [0]
        refused = []   # plates of registrations the server turned down
        def register(**over):
            n[0] += 1
            body = {'plateNumber': f'FMT{n[0]:03d}', 'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'Format Owner', 'ownerRole': 'Student',
                    'ownerIdNumber': f'OWNER-FMT-{n[0]}', 'stickerYear': '2026'}
            body.update(over)
            return req('vehicles.php', body)

        # ---- owner phone
        for given in ('09279100511', '0927 910 0511', '+639279100511', '+63 927 910 0511', '639279100511', '9279100511', '0927-910-0511'):
            c, r = register(ownerPhone=given)
            check(f'phone "{given}" is accepted and stored as +63 927 910 0511', c == 201 and r['data']['ownerPhone'] == '+63 927 910 0511', r)
        check('no phone is allowed', register()[0] == 201)
        for bad in ('0927 910 051', '0927 910 05112', '0827 910 0511', '02-8123-4567', 'abc', '09279100511x', '+63 8279100511', '555-1234'):
            c, r = register(ownerPhone=bad)
            refused.append(f'FMT{n[0]:03d}')
            check(f'phone "{bad}" is refused', c == 400 and r['data']['code'] == 'INVALID_PHONE', r)

        # ---- drivers
        def with_driver(**drv):
            return register(authorizedDrivers=[{'fullName': 'Format Driver', 'relationship': 'Designated Driver', **drv}])
        c, r = with_driver(licenseNo='N01-23-456789', phone='09171234567')
        drv = r['data']['authorizedDrivers'][0]
        check('a valid license and phone are stored', c == 201 and drv['licenseNo'] == 'N01-23-456789' and drv['phone'] == '+63 917 123 4567', drv)
        c, r = with_driver(licenseNo='n0123456789')
        check('a license typed without dashes or in lower case is tidied', c == 201 and r['data']['authorizedDrivers'][0]['licenseNo'] == 'N01-23-456789', r)
        for blank in ('', 'N/A', 'n/a'):
            c, r = with_driver(licenseNo=blank)
            check(f'license "{blank}" means none (N/A)', c == 201 and r['data']['authorizedDrivers'][0]['licenseNo'] == 'N/A', r)
        for bad in ('N01-23-45678', 'N01-23-4567890', '101-23-456789', 'NO-12883166', 'N01 23 45678A'):
            c, r = with_driver(licenseNo=bad)
            refused.append(f'FMT{n[0]:03d}')
            check(f'license "{bad}" is refused', c == 400 and r['data']['code'] == 'INVALID_LICENSE', r)
        c, r = with_driver(phone='12345')
        refused.append(f'FMT{n[0]:03d}')
        check('a bad driver phone is refused', c == 400 and r['data']['code'] == 'INVALID_PHONE', r)
        c, listing = req('vehicles.php', method='GET')
        saved = {v['plateNumber'] for v in listing['data']}
        check('refused registrations left no vehicle behind', len(refused) == 14 and not (saved & set(refused)), sorted(saved & set(refused)))
        check('the accepted ones were saved', len(saved) >= 12, len(saved))

        # ---- institutional ID: free-form, letters / numbers / hyphens, 3 to 20 characters, stored in capitals
        for given, stored in (('NCST-2024-58522', 'NCST-2024-58522'), ('ncst-2024-58523', 'NCST-2024-58523'), ('PRES-129', 'PRES-129'), ('EMP-0412', 'EMP-0412'),
                              ('2024-05182', '2024-05182'), (' abc-1 ', 'ABC-1'), ('A' * 20, 'A' * 20)):
            c, r = register(ownerIdNumber=given)
            check(f'id "{given}" is accepted and stored as {stored}', c == 201 and r['data']['ownerIdNumber'] == stored, r)
        for bad in ('AB', 'A' * 21, 'NCST 2024', 'NCST_2024', 'NCST/2024', '-NCST-2024', 'NCST.2024', 'ID#1'):
            c, r = register(ownerIdNumber=bad)
            refused.append(f'FMT{n[0]:03d}')
            check(f'id "{bad}" is refused', c == 400 and r['data']['code'] == 'INVALID_OWNER_ID', r)
        c, r = register(ownerIdNumber='')
        check('a blank id is still refused as missing', c == 400, r)

        # ---- editing: new values are checked, values the record already has are accepted unchanged
        c, r = register(ownerPhone='09279100511', authorizedDrivers=[{'fullName': 'Format Driver', 'relationship': 'Designated Driver', 'licenseNo': 'N01-23-456789'}])
        vid = r['data']['id']
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute('UPDATE vehicles SET owner_phone = ? WHERE id = ?', ('+63 92777198838', vid))   # legacy value that is one digit too long
            db.execute('UPDATE authorized_drivers SET license_no = ? WHERE vehicle_id = ?', ('NO-12883166', vid))
        legacy_driver = {'fullName': 'Format Driver', 'relationship': 'Designated Driver', 'licenseNo': 'NO-12883166'}
        c, r = req('vehicles.php', {'id': vid, 'department': 'Edited without touching the old numbers', 'ownerPhone': '+63 92777198838', 'authorizedDrivers': [legacy_driver]}, method='PUT')
        check('editing a record that keeps its old, non-conforming numbers still works', c == 200, r)
        c, r = req('vehicles.php', {'id': vid, 'ownerPhone': '555-9999'}, method='PUT')
        check('changing the phone to another bad value is refused', c == 400 and r['data']['code'] == 'INVALID_PHONE', r)
        c, r = req('vehicles.php', {'id': vid, 'ownerPhone': '0927 777 1983'}, method='PUT')
        check('changing the phone to a good value works and is tidied', c == 200 and r['data']['ownerPhone'] == '+63 927 777 1983', r)
        c, r = req('vehicles.php', {'id': vid, 'authorizedDrivers': [{**legacy_driver, 'licenseNo': 'XX-1'}]}, method='PUT')
        check('changing a license to a bad value is refused', c == 400 and r['data']['code'] == 'INVALID_LICENSE', r)
        c, r = req('vehicles.php', {'id': vid, 'authorizedDrivers': [{**legacy_driver, 'licenseNo': 'D12-34-567890'}]}, method='PUT')
        check('changing a license to a good value works', c == 200 and r['data']['authorizedDrivers'][0]['licenseNo'] == 'D12-34-567890', r)

        # ---- editing the institutional ID
        with closing(sqlite3.connect(s.db)) as db, db:
            db.execute('UPDATE vehicles SET owner_id_number = ? WHERE id = ?', ('legacy id 7', vid))   # an old record with a space and lower case
        c, r = req('vehicles.php', {'id': vid, 'ownerIdNumber': 'LEGACY ID 7', 'department': 'Same id, different capitals'}, method='PUT')
        check('an ID the record already has is accepted (any capitals) and kept exactly as stored', c == 200 and r['data']['ownerIdNumber'] == 'legacy id 7', r)
        c, r = req('vehicles.php', {'id': vid, 'ownerIdNumber': 'bad id!'}, method='PUT')
        check('changing the ID to an invalid value is refused', c == 400 and r['data']['code'] == 'INVALID_OWNER_ID', r)
        c, r = req('vehicles.php', {'id': vid, 'ownerIdNumber': ''}, method='PUT')
        check('blanking the ID is refused', c == 400 and r['data']['code'] == 'INVALID_OWNER_ID', r)
        c, r = req('vehicles.php', {'id': vid, 'ownerIdNumber': 'ncst-2025-00042'}, method='PUT')
        check('changing the ID to a good value works and is stored in capitals', c == 200 and r['data']['ownerIdNumber'] == 'NCST-2025-00042', r)

        # ---- a vehicle has the primary driver plus at most 5 more (6 in all)
        def roster(k):
            return [{'fullName': f'Roster Driver {i}', 'relationship': 'Designated Driver', 'licenseNo': 'N/A'} for i in range(k)]
        c, r = register(authorizedDrivers=roster(6))
        check('six drivers (the primary driver plus 5) are accepted', c == 201 and len(r['data']['authorizedDrivers']) == 6, r)
        full = r['data']['id']
        c, r = register(authorizedDrivers=roster(7))
        check('a seventh driver is refused at registration', c == 400 and r['data']['code'] == 'TOO_MANY_DRIVERS', r)
        c, r = req('vehicles.php', {'id': full, 'authorizedDrivers': roster(7)}, method='PUT')
        check('a seventh driver is refused when editing', c == 400 and r['data']['code'] == 'TOO_MANY_DRIVERS', r)
        c, r = req('vehicles.php', {'id': full, 'authorizedDrivers': roster(5)}, method='PUT')
        check('removing a driver brings the roster back under the limit', c == 200 and len(r['data']['authorizedDrivers']) == 5, r)

        # ---- a VIP owner needs no institutional ID: the server generates one (VIP-<year>-0001, 0002, ...)
        import datetime
        vip = {'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'Vera Guest', 'ownerPhone': '09171234567', 'passClass': 'VIP', 'reason': 'Guest of honour', 'stickerYear': '2026'}
        year = datetime.date.today().year
        c, r = req('vehicles.php', {**vip, 'plateNumber': 'VIPGEN1'})
        check('a VIP is registered without an ID and gets VIP-<year>-0001', c == 201 and r['data']['ownerIdNumber'] == f'VIP-{year}-0001', r)
        check('...with the role VIP and no portal login', r['data']['ownerRole'] == 'VIP' and r['data'].get('studentAccount') is None, r['data'])
        c, r = req('vehicles.php', {**vip, 'plateNumber': 'VIPGEN2', 'ownerName': 'Victor Guest'})
        check('the next VIP gets the next number', c == 201 and r['data']['ownerIdNumber'] == f'VIP-{year}-0002', r)
        c, r = req('vehicles.php', {'vehicleType': 'Bicycle', 'category': 'non-plated', 'ownerName': 'No Id', 'plateNumber': 'NOVIPID1', 'stickerYear': '2026'})
        check('a standard registration still needs an ID', c == 400, r)

        # ---- visitor day pass contact number: the same Philippine mobile rule, stored tidied
        visitor = {'visitor_name': 'Format Visitor', 'plate': 'FMTVIS01', 'purpose': 'Delivery', 'person_to_visit': 'Registrar'}
        for i, given in enumerate(('09279100511', '0927 910 0511', '+639279100511', '0927-910-0511')):
            c, r = req('visitors.php', {**visitor, 'plate': f'FMTVIS{i + 10}', 'contact_number': given})
            check(f'visitor contact "{given}" is accepted and stored as +63 927 910 0511', c == 201 and r['data']['contactNumber'] == '+63 927 910 0511', r)
        for bad in ('0927 910 051', '0827 910 0511', '02-8123-4567', 'abc', '555-1234', '1234567'):
            c, r = req('visitors.php', {**visitor, 'plate': 'FMTVIS99', 'contact_number': bad})
            check(f'visitor contact "{bad}" is refused', c == 400 and r['data']['code'] == 'INVALID_PHONE', r)

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/ph-formats-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
