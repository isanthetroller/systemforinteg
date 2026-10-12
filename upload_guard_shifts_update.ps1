<#
  SecurePark - upload the Guard Shifts update (new admin tab) to the live site.

  What changed (admin web at htdocs/):
   - New "Guard Shifts" tab in the sidebar (administrators only). It shows who is on duty at which gate right now, a
     timeline of every shift (one row per guard), hours per guard, and the list of shifts. A shift opens to the handover
     note and a time-ordered log of what that guard did (entries, exits, refusals, violations, held vehicles, photos,
     visitor passes). Shifts closed automatically, shifts over 12 hours and scans made while not on duty are flagged.
     The period can be today, yesterday, 7 or 30 days, or any dates, and the list exports to CSV.
   - The mobile app's "Go on duty" / "End shift" buttons already record shifts; no APK change is needed.
  No database change.

  Run it YOURSELF from the repo root, on branch integration/dashboard-audit-merge-20261012:
      powershell -ExecutionPolicy Bypass -File ./upload_guard_shifts_update.ps1 -DryRun     # check only, uploads nothing
      powershell -ExecutionPolicy Bypass -File ./upload_guard_shifts_update.ps1             # real upload

  - Asks for the FTP username and password (typed hidden, never stored or written to a file).
  - Before replacing a file it downloads the live copy into ftp-backup-<timestamp>\ so you can roll back.
  - Nothing is ever deleted; secret/config files and the database are NOT touched.
  - The API file goes up first, then the page files, so the new tab never asks for something the server lacks.
#>
param(
    [string]$FtpHost = 'ftpupload.net',
    [switch]$DryRun,
    [switch]$UseSsl
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# (local path) -> (remote path under the FTP root). The admin app lives at htdocs/, the owner portal at htdocs/student/.
$files = @(
    @('web-app-admin/api/shifts.php',     'htdocs/api/shifts.php'),
    @('web-app-admin/js/api.js',          'htdocs/js/api.js'),
    @('web-app-admin/js/shifts.js',       'htdocs/js/shifts.js'),
    @('web-app-admin/js/workspace.js',    'htdocs/js/workspace.js'),
    @('web-app-admin/css/workspace.css',  'htdocs/css/workspace.css'),
    @('web-app-admin/index.html',         'htdocs/index.html')
)

# ---- safety checks -------------------------------------------------------
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'integration/dashboard-audit-merge-20261012') {
    throw "You are on '$branch'. Switch to integration/dashboard-audit-merge-20261012 first."
}
$missing = $files | Where-Object { -not (Test-Path (Join-Path $root $_[0])) }
if ($missing) { throw "Missing local files: $($missing | ForEach-Object { $_[0] })" }
foreach ($f in $files) {
    if ($f[0] -like '*secret*') { throw "Refusing to upload a secret file: $($f[0])" }
}

Write-Host ""
Write-Host "Branch : $branch"
Write-Host "Server : $FtpHost   Files: $($files.Count)   Mode: $(if ($DryRun) {'DRY RUN (no changes)'} else {'UPLOAD'})"
Write-Host ""
if ($DryRun) {
    $files | ForEach-Object { '{0,-36} -> /{1}' -f $_[0], $_[1] }
    Write-Host "`nDry run only. Nothing was contacted or uploaded."
    return
}

# ---- credentials (hidden input) -------------------------------------------
$user   = Read-Host 'FTP username'
$secure = Read-Host 'FTP password' -AsSecureString
$cred   = New-Object System.Net.NetworkCredential($user, $secure)
$secure.Dispose()

function New-FtpRequest($remotePath, $method) {
    $req = [System.Net.FtpWebRequest]::Create("ftp://$FtpHost/$remotePath")
    $req.Method      = $method
    $req.Credentials = $cred
    $req.UsePassive  = $true
    $req.UseBinary   = $true
    $req.KeepAlive   = $false
    $req.EnableSsl   = [bool]$UseSsl
    $req.Timeout     = 60000
    return $req
}

function Get-RemoteSize($remotePath) {
    try {
        $resp = (New-FtpRequest $remotePath ([System.Net.WebRequestMethods+Ftp]::GetFileSize)).GetResponse()
        $size = $resp.ContentLength; $resp.Close(); return $size
    } catch { return -1 }   # -1 = file does not exist yet
}

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "ftp-backup-$stamp"
$ok = 0; $failed = @()

foreach ($f in $files) {
    $local  = Join-Path $root $f[0]
    $remote = $f[1]
    $name   = $f[0]
    try {
        # 1) back up the live copy (if there is one)
        if ((Get-RemoteSize $remote) -ge 0) {
            $dest = Join-Path $backup ($remote -replace '/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            $resp = (New-FtpRequest $remote ([System.Net.WebRequestMethods+Ftp]::DownloadFile)).GetResponse()
            $in = $resp.GetResponseStream(); $out = [System.IO.File]::Create($dest)
            $in.CopyTo($out); $out.Close(); $in.Close(); $resp.Close()
        }
        # 2) upload
        $bytes = [System.IO.File]::ReadAllBytes($local)
        $req = New-FtpRequest $remote ([System.Net.WebRequestMethods+Ftp]::UploadFile)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
        $req.GetResponse().Close()
        # 3) verify size
        $size = Get-RemoteSize $remote
        if ($size -ne $bytes.Length) { throw "size mismatch (local $($bytes.Length), remote $size)" }
        Write-Host ("OK     {0}" -f $name) -ForegroundColor Green
        $ok++
    } catch {
        Write-Host ("FAILED {0}  ->  {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        $failed += $name
    }
}

$cred = $null
Write-Host ""
Write-Host "$ok of $($files.Count) files uploaded."
if (Test-Path $backup) { Write-Host "Previous live copies saved in: $backup" }
if ($failed.Count) {
    Write-Host "NOT uploaded (re-run the script; it is safe to repeat):" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "Done. Hard-refresh the admin site (Ctrl+F5), open Guard Shifts in the sidebar and check the timeline."
