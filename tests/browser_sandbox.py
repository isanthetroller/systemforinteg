"""Isolated local browser fixture. Stop this process to clean up all fixtures."""
from movement_integration import Sandbox,call
import shutil,json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with Sandbox() as s:
    target=s.root/'web-app-admin'
    for name in ['index.html','assets','css','js']:
        source=ROOT/'web-app-admin'/name
        if source.is_dir(): shutil.copytree(source,target/name,dirs_exist_ok=True)
        else: shutil.copy2(source,target/name)
    shutil.copytree(ROOT/'web-app-student',s.root/'web-app-student')
    call(s.bases[0],'auth.php?action=login',{'username':'admin','password':'Password123!'})
    context={'url':s.bases[0].replace('/api','/'),'base':s.bases[0],'other':s.bases[1]}
    (ROOT/'artifacts'/'realtime-browser-context.json').write_text(json.dumps(context))
    print(json.dumps(context),flush=True)
    try:
        while True: time.sleep(1)
    except KeyboardInterrupt: pass
