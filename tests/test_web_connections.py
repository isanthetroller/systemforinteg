"""Run ONLY against the isolated verification server; never the working database."""
import json
import os
import uuid
from pathlib import Path
import test_gate_flow_e2e as gate

context = json.loads(Path('artifacts/integration-verification-context.json').read_text())
gate.BASE = context['base']
assert gate.BASE == 'http://127.0.0.1:8002/web-app-admin/api'
password = os.environ['SP_VERIFICATION_PASSWORD']
checks = []

def check(label, condition):
    assert condition, label
    checks.append(label)
    print('PASS:', label)

def call(path, method='GET', body=None, token=None, status=200):
    response = gate.request(path, method, body, token)
    assert response['_http'] == status, (path, response['_http'], response.get('message'))
    return response.get('data')

admin = call('auth.php?action=login', 'POST', {'username':'integration_admin','password':password})['token']
guard = call('auth.php?action=login', 'POST', {'username':'integration_guard','password':password})['token']
for endpoint in ['auth.php?action=me','stats.php','vehicles.php','oncampus.php','visitors.php','logs.php','incidents.php','violations.php','users.php']:
    call(endpoint, token=admin)
    check('Authenticated endpoint: '+endpoint, True)
call('violations.php', status=401)
call('users.php', token=guard, status=403)
check('Unauthenticated and guard admin restrictions', True)

suffix = uuid.uuid4().hex[:6].upper()
plate = 'VFY-'+suffix
owner = 'VERIFY-'+suffix
vehicle = call('vehicles.php', 'POST', {
    'plateNumber':plate,'ownerName':'Verification Fixture','ownerRole':'Student',
    'ownerIdNumber':owner,'department':'BSCS','ownerPhone':'09170000000',
    'vehicleType':'4-Wheel','makeModelColor':'Verification car','stickerYear':'2026',
    'authorizedDrivers':[{'fullName':'Verification Fixture','relationship':'Self (Owner)','licenseNo':'TEST-ONLY'}]
}, admin, 201)
vid = vehicle['id']
payload = {'vehicle_id':vid,'type':'Other','severity':'Warning','notes':'Isolated integration verification'}
call('violations.php', 'POST', {**payload,'notes':''}, admin, 400)
call('violations.php', 'POST', {**payload,'vehicle_id':999999999}, admin, 404)
call('violations.php', 'POST', {**payload,'severity':'Violation'}, guard, 403)
check('Violation validation and guard severity restrictions', True)
warning = call('violations.php','POST',payload,guard,201)
check('Guard warning updates vehicle strike count', warning['strikes']==1 and not warning['banned'])
call('violations.php','PUT',{'violation_id':warning['violation']['id'],'action':'resolve','notes':'Test'},admin,400)
call('violations.php','PUT',{'vehicle_id':vid,'action':'reset','notes':'Test'},guard,403)
call('violations.php','PUT',{'vehicle_id':vid,'action':'reset','notes':''},admin,400)
check('Resolution requires admin, written notes, and violation severity',True)
second = call('violations.php','POST',payload,admin,201)
third = call('violations.php','POST',payload,admin,201)
check('Three warnings enforce suspension automatically',second['strikes']==2 and third['strikes']==3 and third['banned'] and third['autoViolationId'])
verification = call('verify.php','POST',{'qr_code':vehicle['qrPayload'],'gate_type':'Ingress'},admin)
check('Suspended QR is rejected at gate',verification['result']=='BANNED')
resolved = call('violations.php','PUT',{'violation_id':third['autoViolationId'],'action':'resolve','notes':'Isolated clearance test'},admin)
current = call('vehicles.php?plate='+plate,token=admin)
check('Resolving final violation restores vehicle and clears strikes',not current['isBanned'] and current['warningCount']==0)
explicit = call('violations.php','POST',{**payload,'severity':'Violation'},admin,201)
call('violations.php','PUT',{'violation_id':explicit['violation']['id'],'action':'dismiss','notes':'Isolated dismissal test'},admin)
current = call('vehicles.php?plate='+plate,token=admin)
check('Dismissal lifts suspension',not current['isBanned'])
call('violations.php','PUT',{'violation_id':explicit['violation']['id'],'action':'dismiss','notes':'Repeated'},admin,409)
check('Completed records cannot be processed twice',True)
for status in ['Pending','Resolved','Dismissed']:
    records = call('violations.php?status='+status,token=admin)
    check('Status filter: '+status,all(r['status']==status for r in records))

account = call('students.php','POST',{'owner_id_number':owner,'action':'issue'},admin)
login = call('auth.php?action=login&realm=student','POST',{'username':owner,'password':account['tempPassword']})
student = login['token']
check('Student issued account requires first-login password change',login['student']['mustChangePassword'])
call('auth.php?action=change_password','POST',{'current_password':account['tempPassword'],'new_password':password},student)
for action in ['me','vehicles','violations','activity','alerts']:
    data = call('student.php?action='+action,token=student)
    if action=='vehicles': check('Student sees only their own vehicle',len(data)==1 and data[0]['plateNumber']==plate)
    if action=='violations': check('Student violation history is owner scoped',all(r['plateNumber']==plate for r in data))
    check('Student endpoint: '+action,True)
call('vehicles.php',token=student,status=401)
call('student.php?action=me',token=admin,status=401)
check('Student and staff realms stay isolated',True)
call('students.php','POST',{'owner_id_number':owner,'action':'set_status','status':'Inactive'},admin)
call('auth.php?action=me',token=student,status=401)
check('Deactivating an account revokes its session',True)

# Seed enough records to exercise browser pagination without touching real records.
for i in range(12):
    record = call('violations.php','POST',{**payload,'notes':f'UI pagination fixture {i+1}: longer notes remain expandable and do not distort row alignment.'},admin,201)
    call('violations.php','PUT',{'violation_id':record['violation']['id'],'action':'dismiss','notes':'Isolated UI fixture'},admin)
Path('artifacts/integration-api-results.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'fixturePlate':plate},indent=2))
print(f'{len(checks)} integration checks passed.')
