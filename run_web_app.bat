@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo   SecurePark - Starting Web Application
echo ========================================================

set "PHP_CMD=php"
where php >nul 2>nul
if %errorlevel% neq 0 (
    if exist "C:\xampp\php\php.exe" (
        set "PHP_CMD=C:\xampp\php\php.exe"
    ) else (
        echo [ERROR] PHP executable not found in PATH or C:\xampp\php\php.exe
        pause
        exit /b 1
    )
)

echo Using PHP: %PHP_CMD%
echo.
echo Staff / Admin Portal:    http://localhost:8000/web-app-admin/
echo                          http://127.0.0.1:8000/web-app-admin/
echo Student / Owner Portal:  http://localhost:8000/web-app-student/
echo                          http://127.0.0.1:8000/web-app-student/
echo.
echo Press Ctrl+C to stop the server.
echo ========================================================
echo.

"%PHP_CMD%" -S 127.0.0.1:8000 -t .
