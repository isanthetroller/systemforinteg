"""
SecurePark - Deploy to InfinityFree over FTP

    python deploy_to_infinityfree.py          # DRY RUN: show what would be uploaded (default)
    python deploy_to_infinityfree.py --yes    # actually upload

Layout on the server:
    web-app-admin/   -> htdocs/          (admin & guard portal + PHP API in htdocs/api)
    web-app-student/ -> htdocs/student/  (student portal, calls ../api)

Safety checks (the upload is refused if any fails):
    1. backend/ and web-app-admin/{api,lib,config,database} are in sync (run sync_backend.py).
    2. backend/config/secret.production.php exists, has no CHANGE_ME values, strong keys and
       SP_DEBUG = false. It is uploaded as htdocs/config/secret.php.
       The local development config/secret.php is NEVER uploaded.
    3. FTP_USER and FTP_PASS environment variables are set (only for --yes).

Never uploaded: local SQLite data (data/), SQL scripts (database/), local secret.php, README files.
"""
import ftplib
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
FTP_HOST = os.environ.get('FTP_HOST', 'ftpupload.net')
FTP_USER = os.environ.get('FTP_USER', '')
FTP_PASS = os.environ.get('FTP_PASS', '')
REMOTE_ROOT = 'htdocs'

TARGETS = [
    # (local folder, remote folder under htdocs)
    (os.path.join(ROOT, 'web-app-admin'), ''),
    (os.path.join(ROOT, 'web-app-student'), 'student'),
]
PROD_SECRET = os.path.join(ROOT, 'backend', 'config', 'secret.production.php')
SKIP_DIRS = {'data', 'database', '__pycache__', '.git'}
SKIP_FILES = {'README.md', 'README.txt', '.DS_Store', 'Thumbs.db'}


def fail(message):
    print(f'[DEPLOY BLOCKED] {message}', file=sys.stderr)
    sys.exit(1)


def check_mirror():
    result = subprocess.run([sys.executable, os.path.join(ROOT, 'sync_backend.py'), '--check'],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        fail('web-app-admin/ is out of date with backend/. Run: python sync_backend.py')


def check_production_secret():
    if not os.path.exists(PROD_SECRET):
        fail('backend/config/secret.production.php is missing. Copy secret.example.php to it and set production values.')
    text = open(PROD_SECRET, encoding='utf-8').read()
    if 'CHANGE_ME' in text:
        fail('secret.production.php still contains CHANGE_ME placeholders.')
    if not re.search(r"define\('SP_DEBUG',\s*false\)", text):
        fail("secret.production.php must set define('SP_DEBUG', false).")
    for name, min_len in (('SP_QR_SECRET', 32), ('SP_SCANNER_API_KEY', 24)):
        m = re.search(rf"define\('{name}',\s*'([^']*)'\)", text)
        if not m or len(m.group(1)) < min_len:
            fail(f'{name} in secret.production.php must be at least {min_len} characters.')
    if not re.search(r"^\s*define\('SP_DB_PASS',\s*'[^']+'\)", text, re.M):
        print('[DEPLOY WARNING] SP_DB_PASS is not set in secret.production.php: the live site will use the '
              'SQLite fallback file (htdocs/data/securepark.sqlite), not MySQL.')
    local = os.path.join(ROOT, 'backend', 'config', 'secret.php')
    if os.path.exists(local):
        local_key = re.search(r"define\('SP_QR_SECRET',\s*'([^']*)'\)", open(local, encoding='utf-8').read())
        prod_key = re.search(r"define\('SP_QR_SECRET',\s*'([^']*)'\)", text)
        if local_key and prod_key and local_key.group(1) == prod_key.group(1):
            fail('Production SP_QR_SECRET must differ from the local development key.')


def collect_uploads():
    """Returns a list of (local_path, remote_path)."""
    uploads = []
    for local_root, remote_sub in TARGETS:
        for root, dirs, files in os.walk(local_root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            rel_dir = os.path.relpath(root, local_root).replace('\\', '/')
            for name in sorted(files):
                if name in SKIP_FILES:
                    continue
                rel = name if rel_dir == '.' else f'{rel_dir}/{name}'
                if rel in ('config/secret.php', 'config/secret.production.php'):
                    continue  # handled below
                remote = '/'.join(p for p in (REMOTE_ROOT, remote_sub, rel) if p)
                uploads.append((os.path.join(root, name), remote))
    uploads.append((PROD_SECRET, f'{REMOTE_ROOT}/config/secret.php'))
    return uploads


def ensure_remote_dir(ftp, remote_dir, created):
    ftp.cwd('/')
    current = ''
    for part in [p for p in remote_dir.split('/') if p]:
        current = f"{current}/{part}" if current else part
        if current not in created:
            try:
                ftp.cwd(part)
            except ftplib.error_perm:
                ftp.mkd(part)
                ftp.cwd(part)
            created.add(current)
        else:
            ftp.cwd(part)


def main():
    really = '--yes' in sys.argv
    check_mirror()
    check_production_secret()
    uploads = collect_uploads()

    print(f"{'UPLOADING' if really else 'DRY RUN'}: {len(uploads)} files to {FTP_HOST}:/{REMOTE_ROOT}")
    for local, remote in uploads:
        print(f'  {os.path.relpath(local, ROOT):55s} -> /{remote}')

    if not really:
        print('\nNothing was uploaded. Re-run with --yes to deploy.')
        return
    if not FTP_USER or not FTP_PASS:
        fail('Set the FTP_USER and FTP_PASS environment variables.')

    print(f'[FTP] Connecting to {FTP_HOST}...')
    sys.stdout.flush()
    ftp = ftplib.FTP(FTP_HOST, timeout=30)
    ftp.login(FTP_USER, FTP_PASS)
    ftp.set_pasv(True)
    print('[FTP] Logged in successfully.')
    sys.stdout.flush()

    created = set()
    for local, remote in uploads:
        remote_dir, filename = remote.rsplit('/', 1)
        ensure_remote_dir(ftp, remote_dir, created)
        with open(local, 'rb') as fh:
            ftp.storbinary(f'STOR {filename}', fh)
        print(f'[FTP] /{remote}')
        sys.stdout.flush()
    ftp.quit()
    print(f'\n[FTP] SUCCESS: uploaded {len(uploads)} files.')
    sys.stdout.flush()
    print('Remember: run the migrations in backend/database/migrations/ (001, then 002) in phpMyAdmin once each before first use.')


if __name__ == '__main__':
    try:
        main()
    except ftplib.all_errors as e:
        fail(f'FTP error: {e}')
