"""Chrome: literal hostile-looking text, invalid forms, lost save replies and retries."""
import json
import shutil
from playwright.sync_api import sync_playwright
from movement_integration import ROOT, Sandbox, call
from adversarial_runtime import OUT, setup


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    checks=[];errors=[];dialogs=[]
    def check(name,ok):
        checks.append({'name':name,'passed':bool(ok)})
        print(('PASS ' if ok else 'FAIL ')+name,flush=True)
    with Sandbox() as s:
        admin,guards,vehicle=setup(s)
        base=s.bases[0]
        for name in ('index.html','assets','css','js'):
            source=ROOT/'web-app-admin'/name;dest=s.root/'web-app-admin'/name
            if source.is_dir():shutil.copytree(source,dest,dirs_exist_ok=True)
            else:shutil.copy2(source,dest)
        with sync_playwright() as pw:
            browser=pw.chromium.launch(channel='chrome',headless=True)
            page=browser.new_page(viewport={'width':1366,'height':900})
            page.on('pageerror',lambda error:errors.append(str(error)))
            responses=[]
            page.on('response',lambda r: responses.append({'status':r.status,'body':r.text()[:1000]}) if r.request.method=='POST' and 'visitors.php' in r.url else None)
            def dialog(d):dialogs.append(d.message);d.dismiss()
            page.on('dialog',dialog)
            page.goto(base.replace('/api','/'),wait_until='domcontentloaded')
            page.locator('#loginUsername').fill('admin');page.locator('#loginPassword').fill('Adversarial-Admin-2026');page.locator('#loginSubmitBtn').click()
            page.locator('#loginOverlay').wait_for(state='hidden',timeout=15000)
            page.evaluate("SP.switchView('visitorsView')")
            for i,name in enumerate(["O'Brien",'José Niño','李明','Visitor 🚗','<img src=x onerror=alert(1)>',"Robert'); DROP TABLE vehicles;--"]):
                plate=f'WEBADV{i}'
                page.locator('#visitorsNewBtn').click()
                for selector,value in [('#vpName',name),('#vpContact','09123456789'),('#vpPlate',plate),('#vpHost','Security'),('#vpPurpose','Input roundtrip')]:page.locator(selector).fill(value)
                page.locator('#visitorSubmitBtn').click()
                page.wait_for_function("!document.getElementById('visitorSubmitBtn').disabled")
                if not page.locator('#visitorCardModal').is_visible():
                    check(f'literal visitor text survives browser save {i}',False)
                    checks[-1]['detail']={'name':name,'formError':page.locator('#visitorFormError').text_content(),'response':responses[-1:] ,'pageErrors':errors[:]}
                    if page.locator('#visitorModal').is_visible():page.locator('#visitorCancelBtn').click()
                    continue
                check(f'literal visitor text survives browser save {i}',name in page.locator('#visitorCard').inner_text())
                check(f'no executable markup from visitor text {i}',page.locator('#visitorCard [onerror="alert(1)"]').count()==0 and not dialogs)
                page.locator('#visitorCardCloseBtn').click()
            page.locator('#visitorsNewBtn').click()
            for selector,value in [('#vpName','Interrupted Visitor'),('#vpContact','bad-contact'),('#vpPlate','WEBLOST'),('#vpHost','Security'),('#vpPurpose','Lost reply probe')]:page.locator(selector).fill(value)
            page.locator('#visitorSubmitBtn').click()
            page.locator('#visitorFormError').wait_for(state='visible')
            check('invalid contact retains entered form',page.locator('#vpName').input_value()=='Interrupted Visitor' and page.locator('#visitorModal').is_visible())
            page.locator('#vpContact').fill('09123456789')
            def lose_reply(route):
                if route.request.method=='POST':
                    route.fetch() # Actual backend commits; the browser never receives its answer.
                    route.abort('connectionreset')
                else:route.continue_()
            page.route('**/visitors.php',lose_reply)
            page.locator('#visitorSubmitBtn').click()
            page.wait_for_function("!document.getElementById('visitorSubmitBtn').disabled")
            page.locator('#visitorFormError').wait_for(state='visible')
            check('lost save response preserves editable form without success card',page.locator('#vpPlate').input_value()=='WEBLOST' and not page.locator('#visitorCardModal').is_visible())
            c,r=call(base,'visitors.php?all=1',token=admin,method='GET')
            check('server committed one visitor despite lost reply',c==200 and sum(x['plateNumber']=='WEBLOST' for x in r['data'])==1)
            page.unroute('**/visitors.php',lose_reply)
            page.locator('#visitorSubmitBtn').click()
            page.wait_for_function("document.getElementById('visitorFormError').textContent.includes('already exists')")
            c,r=call(base,'visitors.php?all=1',token=admin,method='GET')
            check('retry after ambiguous save does not create a second pass',sum(x['plateNumber']=='WEBLOST' for x in r['data'])==1)
            page.wait_for_function("document.getElementById('visitorsTableBody').textContent.includes('WEBLOST')",timeout=15000)
            check('committed visitor appears in open browser without reload',True)
            check('no uncaught browser exceptions or injected dialogs',not errors and not dialogs)
            page.screenshot(path=str(OUT/'browser-lost-reply.png'),animations='disabled')
            browser.close()
    report={'total':len(checks),'passed':sum(x['passed'] for x in checks),'failed':sum(not x['passed'] for x in checks),'checks':checks,'pageErrors':errors,'dialogs':dialogs}
    (OUT/'browser-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return int(report['failed']>0)


if __name__=='__main__':raise SystemExit(main())
