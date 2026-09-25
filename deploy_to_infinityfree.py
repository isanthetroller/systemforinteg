import os
import ftplib
import sys

FTP_HOST = os.environ.get('FTP_HOST', 'ftpupload.net')
FTP_USER = os.environ.get('FTP_USER', '')
FTP_PASS = os.environ.get('FTP_PASS', '')
LOCAL_DIR = os.path.abspath('web-app-admin')
REMOTE_TARGET = 'htdocs'

def ensure_remote_dir(ftp, remote_path):
    """Navigate from root / and create each component of remote_path if missing."""
    ftp.cwd('/')
    parts = [p for p in remote_path.replace('\\', '/').split('/') if p]
    for part in parts:
        try:
            ftp.cwd(part)
        except Exception:
            try:
                print(f"[FTP] Creating remote directory: {part}")
                ftp.mkd(part)
                ftp.cwd(part)
            except Exception as e:
                print(f"[FTP] Directory create note: {e}")

def upload_directory():
    if not FTP_USER or not FTP_PASS:
        print("[FTP ERROR] Please set FTP_USER and FTP_PASS environment variables before running.", file=sys.stderr)
        sys.exit(1)

    print(f"[FTP] Connecting to {FTP_HOST}:21 ...")
    ftp = ftplib.FTP(FTP_HOST, timeout=30)
    ftp.login(FTP_USER, FTP_PASS)
    print(f"[FTP] Logged in successfully as {FTP_USER}")

    total_files = 0
    uploaded_files = 0

    for root, dirs, files in os.walk(LOCAL_DIR):
        rel_dir = os.path.relpath(root, LOCAL_DIR).replace('\\', '/')
        if rel_dir == '.':
            target_dir = f"/{REMOTE_TARGET}"
        else:
            target_dir = f"/{REMOTE_TARGET}/{rel_dir}"

        ensure_remote_dir(ftp, target_dir)

        for filename in files:
            total_files += 1
            local_file_path = os.path.join(root, filename)

            print(f"[FTP] Uploading: {rel_dir}/{filename} ...", end=' ', flush=True)
            with open(local_file_path, 'rb') as f:
                ftp.storbinary(f"STOR {filename}", f)
            print("DONE")
            uploaded_files += 1

    print(f"\n[FTP] SUCCESS: Uploaded {uploaded_files}/{total_files} files to InfinityFree {REMOTE_TARGET}/")
    
    # List uploaded files inside htdocs
    ftp.cwd(f"/{REMOTE_TARGET}")
    print("\n[FTP] Top-level files in /htdocs:")
    for item in ftp.nlst():
        print(f"  - {item}")

    ftp.quit()

if __name__ == '__main__':
    try:
        upload_directory()
    except Exception as e:
        print(f"\n[FTP ERROR]: {e}", file=sys.stderr)
        sys.exit(1)
