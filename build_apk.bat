@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo           SecurePark Mobile Terminal - Automated APK Builder
echo =====================================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "MOBILE_DIR=%SCRIPT_DIR%mobile-app"
set "DOWNLOADS_DIR=%USERPROFILE%\Downloads"

if not exist "%MOBILE_DIR%\pubspec.yaml" (
    echo [ERROR] Mobile app folder not found at: "%MOBILE_DIR%"
    pause
    exit /b 1
)

:: Read SCANNER_API_KEY from backend/config/secret.php if available, default to local-scanner-key-2026
set "SCANNER_KEY=local-scanner-key-2026"
if exist "%SCRIPT_DIR%backend\config\secret.php" (
    for /f "tokens=4 delims='" %%A in ('findstr "SP_SCANNER_API_KEY" "%SCRIPT_DIR%backend\config\secret.php" 2^>nul') do (
        set "SCANNER_KEY=%%A"
    )
)

echo [1/4] Navigating to mobile-app directory...
cd /d "%MOBILE_DIR%" || exit /b 1

echo [2/4] Fetching Flutter dependencies...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] 'flutter pub get' failed. Check your Flutter installation.
    pause
    exit /b 1
)

echo.
echo [3/4] Compiling Release APK (Key: !SCANNER_KEY!)...
echo (This may take 1-3 minutes on the first build while Gradle runs)
call flutter build apk --release --dart-define=SCANNER_API_KEY=!SCANNER_KEY!
if errorlevel 1 (
    echo [ERROR] APK compilation failed. See output above for details.
    pause
    exit /b 1
)

set "BUILT_APK=%MOBILE_DIR%\build\app\outputs\flutter-apk\app-release.apk"
if not exist "%BUILT_APK%" (
    echo [ERROR] Built APK was not found at: "%BUILT_APK%"
    pause
    exit /b 1
)

echo.
echo [4/4] Deploying APK to Downloads folder...
set "TARGET_APK=%DOWNLOADS_DIR%\SecurePark-GuardTerminal.apk"
copy /y "%BUILT_APK%" "%TARGET_APK%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy APK to: "%TARGET_APK%"
    pause
    exit /b 1
)

:: Get file size in MB
for %%I in ("%TARGET_APK%") do set "BYTES=%%~zI"
set /a "MB=!BYTES! / 1048576"

echo.
echo =====================================================================
echo                     BUILD SUCCESSFUL!
echo =====================================================================
echo Output file: %TARGET_APK%
echo File size:   ~!MB! MB (%BYTES% bytes)
echo.
echo You can transfer this APK directly to Android devices / tablets.
echo =====================================================================
echo.
if "%~1"=="" pause
