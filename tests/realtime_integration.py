"""Real PHP/SQLite revision and session tests; disposable database only."""
from movement_integration import Sandbox, call
import sqlite3
from contextlib import closing
import json
checks=[]

def data_revisions(snapshot):
    # Clock can legitimately change at a minute boundary while database rows do not.
    return {key:value for key,value in snapshot['revisions'].items() if key != 'clock'}
def check(name, condition):
    if not condition: raise AssertionError(name)
    checks.append(name); print('PASS', name)

def run(s):
    base, other=s.bases
    code,r=call(base,'auth.php?action=login',{'username':'admin','password':'Password123!'})
    admin=r['data']['token']
    call(base,'auth.php?action=change_password',{'current_password':'Password123!','new_password':'Realtime-Admin-2026'},admin)
    def snapshot(token=admin, where=other):
        code,r=call(where,'updates.php',token=token,method='GET')
        assert code==200, (code,r.get('message'))
        return r['data']
    initial=snapshot()
    check('authenticated revision transport covers admin domains', all(k in initial['revisions'] for k in ['vehicles','movements','cases','visitors','staff','approvals','payments','settings','shifts']))
    check('unchanged database gives stable revision snapshot', data_revisions(initial)==data_revisions(snapshot()))
    check('anonymous revision access rejected',call(base,'updates.php',method='GET')[0]==401)
    code,r=call(base,'users.php',{'username':'liveguard','full_name':'Live Guard','role':'guard','password':'Realtime-Guard-2026','gate_assigned':'Checkpoint 2'},admin)
    assert code==201
    uid=r['data']['user']['id']
    guard=call(base,'auth.php?action=login',{'username':'liveguard','password':'Realtime-Guard-2026'})[1]['data']['token']
    check('second client sees staff creation revision',snapshot()['revisions']['staff']!=initial['revisions']['staff'])
    g=snapshot(guard)
    check('guard revision feed does not disclose admin-only domains',not any(k in g['revisions'] for k in ['staff','activity','approvals','payments']))
    call(base,'users.php',{'id':uid,'action':'set_status','status':'Inactive'},admin,method='PUT')
    for path in ['updates.php','vehicles.php','logs.php']:
        check('deactivated staff rejected by '+path,call(other,path,token=guard,method='GET')[0]==401)
    check('revoked bearer cannot fall back even with valid device key',call(other,'verify.php',{'plate':'NONE'},guard,extra_headers={'X-Api-Key':s.scanner_key})[0]==401)
    check('anonymous legacy scanner access rejected',call(other,'verify.php',{'plate':'NONE'})[0]==401)
    call(base,'users.php',{'id':uid,'action':'set_status','status':'Active'},admin,method='PUT')
    check('reactivation does not revive revoked token',call(other,'updates.php',token=guard,method='GET')[0]==401)
    guard=call(base,'auth.php?action=login',{'username':'liveguard','password':'Realtime-Guard-2026'})[1]['data']['token']
    check('reactivated guard can establish new session',snapshot(guard)['user']['status']=='Active')
    before=snapshot()
    with closing(sqlite3.connect(s.db)) as db:
        db.execute("UPDATE system_users SET full_name='Changed externally' WHERE id=?",(uid,))
        db.commit()
    check('direct database edits invalidate revisions',snapshot()['revisions']['staff']!=before['revisions']['staff'])
    check('open session receives latest profile',snapshot(guard)['user']['fullName']=='Changed externally')
    with closing(sqlite3.connect(s.db)) as db:
        db.execute("UPDATE system_users SET role='admin' WHERE id=?",(uid,))
        db.commit()
    check('role change adjusts feed capabilities without relogin','approvals' in snapshot(guard)['revisions'])
    check('transport never returns bearer token or password fields',not any(k in json.dumps(snapshot()) for k in ['password_hash','token_hash','passwordHash']))
    owners=[]
    for owner in ['LIVE-OWNER-A','LIVE-OWNER-B']:
        body={'plateNumber':owner,'vehicleType':'4-Wheel','makeModelColor':'Live vehicle','ownerName':owner,'ownerRole':'Student','ownerIdNumber':owner,'stickerYear':'2026'}
        code,r=call(base,'vehicles.php',body,admin)
        assert code==201, (code,r.get('message'))
        with closing(sqlite3.connect(s.db)) as db:
            db.execute("INSERT OR REPLACE INTO student_accounts(owner_id_number, full_name, password_hash, status, must_change_password) SELECT ?,?,password_hash,'Active',0 FROM system_users WHERE username='admin'",(owner,owner)); db.commit()
        token=call(base,'auth.php?action=login&realm=student',{'username':owner,'password':'Realtime-Admin-2026'})[1]['data']['token']
        owners.append(token)
    a,b=map(snapshot,owners)
    check('owner transport is scoped and excludes staff domains', 'staff' not in a['revisions'] and 'visitors' not in a['revisions'])
    with closing(sqlite3.connect(s.db)) as db:
        db.execute("UPDATE vehicles SET make_model_color='Changed for A only' WHERE owner_id_number='LIVE-OWNER-A'"); db.commit()
    check('owner sees their vehicle edit without a summary-count change',snapshot(owners[0])['revisions']['vehicles']!=a['revisions']['vehicles'])
    check('other owner does not receive unrelated revision changes',data_revisions(snapshot(owners[1]))==data_revisions(b))
    print(f'{len(checks)} realtime API checks passed; no production data used.')
if __name__=='__main__':
    with Sandbox() as s: run(s)
