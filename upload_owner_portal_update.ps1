<#
  SecurePark - upload the owner-portal update (Activity / Cases tables, filters, evidence photos) to the live site.

  What changed (student portal at htdocs/student/):
   - Evidence: the photos a guard attaches to a case, violation, flag or gate passage now show in the owner's portal
     (thumbnails, tap to enlarge). The server returns each photo only to the owner of that vehicle.
   - Cases tab: a table with search, status / type / vehicle filters and a "With photos" filter. Each row opens to the
     progress steps, what to do, what happened and the evidence photos. Open cases start expanded.
   - Sidebar: the same look as the admin web app (emblem and brand, grouped navigation, account card with Sign Out at the
     bottom, page name and date in the top bar). Phones keep the bottom tab bar.
   - Activity tab: a table with search, vehicle / entries / exits / refused filters and a period filter (today, 7 days,
     30 days). Narrow screens show each row as a labelled card.
  No database change.

  Run it YOURSELF from the repo root, on branch integration/dashboard-audit-merge-20261012:
      powershell -ExecutionPolicy Bypass -File ./upload_owner_portal_update.ps1 -DryRun     # check only, uploads nothing
      powershell -ExecutionPolicy Bypass -File ./upload_owner_portal_update.ps1             # real upload

  - Asks for the FTP username and password (typed hidden, never stored or written to a file).
  - Before replacing a file it downloads the live copy into ftp-backup-<timestamp>\ so you can roll back.
  - Nothing is ever deleted; secret/config files and the database are NOT touched.
  - The API file goes up first, then the portal files, so the new page never asks for something the server lacks.
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
    @('web-app-admin/api/student.php',            'htdocs/api/student.php'),
    @('web-app-student/js/api.js',                'htdocs/student/js/api.js'),
    @('web-app-student/js/app.js',                'htdocs/student/js/app.js'),
    @('web-app-student/js/portal.js',             'htdocs/student/js/portal.js'),
    @('web-app-student/css/portal-layout.css',    'htdocs/student/css/portal-layout.css'),
    @('web-app-student/index.html',               'htdocs/student/index.html')
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
    $files | ForEach-Object { '{0,-42} -> /{1}' -f $_[0], $_[1] }
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
Write-Host "Done. Sign in to the owner portal (Ctrl+F5 first), open Cases and Activity, and check the filters and that evidence photos show."
