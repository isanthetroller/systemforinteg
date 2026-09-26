"""
SecurePark - Backend Mirror Sync

`backend/` is the single source of truth for all PHP API code, libraries,
configuration and database scripts. The admin web app is deployed with its own
copy under `web-app-admin/`, so this script mirrors the folders there.

    python sync_backend.py          # copy backend/ -> web-app-admin/
    python sync_backend.py --check  # exit 1 if the mirror is out of date (no changes)

Never edit PHP files inside web-app-admin/{api,lib,config,database} directly.
"""
import filecmp
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(ROOT, 'backend')
TARGET = os.path.join(ROOT, 'web-app-admin')
FOLDERS = ['api', 'lib', 'config', 'database']
SKIP_DIRS = {'data', '__pycache__'}
# Production secrets are uploaded by deploy_to_infinityfree.py only, never mirrored
SKIP_FILES = {'secret.production.php'}


def iter_files(base):
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name in SKIP_FILES:
                continue
            full = os.path.join(root, name)
            yield os.path.relpath(full, base)


def plan():
    """Return (to_copy, to_delete) lists of paths relative to the folder roots."""
    to_copy, to_delete = [], []
    for folder in FOLDERS:
        src_dir = os.path.join(SOURCE, folder)
        dst_dir = os.path.join(TARGET, folder)
        src_files = set(iter_files(src_dir)) if os.path.isdir(src_dir) else set()
        dst_files = set(iter_files(dst_dir)) if os.path.isdir(dst_dir) else set()
        for rel in sorted(src_files):
            dst = os.path.join(dst_dir, rel)
            if not os.path.exists(dst) or not filecmp.cmp(os.path.join(src_dir, rel), dst, shallow=False):
                to_copy.append(os.path.join(folder, rel))
        for rel in sorted(dst_files - src_files):
            to_delete.append(os.path.join(folder, rel))
    return to_copy, to_delete


def main():
    check_only = '--check' in sys.argv
    to_copy, to_delete = plan()

    if check_only:
        for p in to_copy:
            print(f'[OUT OF DATE] {p}')
        for p in to_delete:
            print(f'[EXTRA]       {p}')
        if to_copy or to_delete:
            print('Mirror is out of date. Run: python sync_backend.py')
            sys.exit(1)
        print('Mirror is up to date.')
        return

    for rel in to_copy:
        src = os.path.join(SOURCE, rel)
        dst = os.path.join(TARGET, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        print(f'[COPY]   {rel}')
    for rel in to_delete:
        os.remove(os.path.join(TARGET, rel))
        print(f'[REMOVE] {rel}')
    print(f'Synced {len(to_copy)} file(s), removed {len(to_delete)} stale file(s).')


if __name__ == '__main__':
    main()
