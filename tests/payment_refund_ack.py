"""Marking duplicate payments as refunded: the Cashier warning counts only the ones still waiting for a refund."""
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
            'current_password': 'Password123!', 'new_password': 'Refund-Admin-2026'})[0] == 200)
        c, r = req('users.php', {'username': 'refundguard', 'full_name': 'Refund Guard', 'role': 'guard', 'password': 'Refund-Guard-2026', 'gate_assigned': 'Gate 1 (Main Ingress)'})
        guard = call(base, 'auth.php?action=login', {'username': 'refundguard', 'password': 'Refund-Guard-2026'})[1]['data']['token']

        c, v = req('vehicles.php', {'plateNumber': 'RFD 100', 'vehicleType': '4-Wheel', 'category': 'plated', 'ownerName': 'Refund Owner',
                                    'ownerRole': 'Student', 'ownerIdNumber': 'OWNER-RFD', 'stickerYear': '2026'})
        assert c == 201, v
        c, paid = req('payments.php', {'action': 'cash', 'vehicleId': v['data']['id']})
        assert c == 201, paid

        # Two online payments arrived for the already paid vehicle: the server flags them DUPLICATE
        with closing(sqlite3.connect(s.db)) as db, db:
            db.row_factory = sqlite3.Row
            original = dict(db.execute('SELECT * FROM payments ORDER BY id LIMIT 1').fetchone())
            for n in (1, 2):
                row = {k: v for k, v in original.items() if k != 'id'}
                row['receipt_number'] = f"{original['receipt_number']}-D{n}"
                row['method'] = 'PayMongo'
                row['notes'] = 'DUPLICATE: the vehicle was already settled when this payment arrived. Refund it.'
                for unique in ('provider_session_id', 'provider_payment_id'):
                    if unique in row:
                        row[unique] = None
                cols = ', '.join(row)
                db.execute(f'INSERT INTO payments ({cols}) VALUES ({", ".join("?" * len(row))})', list(row.values()))

        def history():
            c, r = req('payments.php', method='GET')
            assert c == 200, r
            return r['data']
        data = history()
        dups = [p for p in data['payments'] if (p['notes'] or '').startswith('DUPLICATE')]
        check('two duplicate payments are flagged', data['summary']['duplicates'] == 2 and len(dups) == 2, data['summary'])
        fee = paid['data']['payment']['amount']
        check('before any refund, today counts all three payments', abs(data['summary']['collectedToday'] - 3 * fee) < 0.01, data['summary'])

        check('a guard cannot mark payments refunded', req('payments.php', {'action': 'mark_refunded', 'all': True}, guard)[0] == 403)
        check('marking needs payments or all', req('payments.php', {'action': 'mark_refunded'})[0] == 400)

        c, r = req('payments.php', {'action': 'mark_refunded', 'paymentIds': [dups[0]['id']], 'reference': 'rf_test_123'})
        check('one payment is marked refunded', c == 200 and r['data']['marked'] == 1 and r['data']['remaining'] == 1, r)
        data = history()
        marked = next(p for p in data['payments'] if p['id'] == dups[0]['id'])
        check('the warning count dropped to 1', data['summary']['duplicates'] == 1, data['summary'])
        check('a refunded payment is no longer counted as collected today', abs(data['summary']['collectedToday'] - 2 * fee) < 0.01, data['summary'])
        check('the note says who, when and the PayMongo reference', marked['notes'].startswith('REFUNDED') and 'rf_test_123' in marked['notes'] and 'by ' in marked['notes'], marked['notes'])
        check('the other duplicate is untouched', next(p for p in data['payments'] if p['id'] == dups[1]['id'])['notes'].startswith('DUPLICATE'))

        c, again = req('payments.php', {'action': 'mark_refunded', 'paymentIds': [dups[0]['id']]})
        check('marking the same payment again is refused (409)', c == 409 and again['data']['code'] == 'NOTHING_TO_REFUND', again)
        check('a normal paid payment cannot be marked', req('payments.php', {'action': 'mark_refunded', 'paymentIds': [paid['data']['payment']['id']]})[0] == 409)

        c, r = req('payments.php', {'action': 'mark_refunded', 'all': True})
        check('mark all clears the rest', c == 200 and r['data']['marked'] == 1 and r['data']['remaining'] == 0, r)
        data = history()
        check('the warning is gone', data['summary']['duplicates'] == 0, data['summary'])
        check('after refunding both, today counts only the real payment', abs(data['summary']['collectedToday'] - fee) < 0.01, data['summary'])
        check('marking all with nothing left is refused (409)', req('payments.php', {'action': 'mark_refunded', 'all': True})[0] == 409)

        c, log = req('audit.php?action=payment.refunded', method='GET')
        check('each refund is in the admin activity log', c == 200 and json.dumps(log).count('marked refunded') >= 2, log)
        check('the original paid payment is still Paid', next(p for p in data['payments'] if p['id'] == paid['data']['payment']['id'])['status'] == 'Paid')

    return results


if __name__ == '__main__':
    results = run()
    Path('artifacts').mkdir(exist_ok=True)
    Path('artifacts/payment-refund-ack-results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2), encoding='utf-8')
    print(f'{len(results)} checks passed')
