@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo Publish latest USB diagnostic result to Git
echo ============================================================
echo This script does not alter device state. It only copies the latest
echo USB_LINK_JL22_KOZEN_*.zip into test_reports and commits/pushes it.
echo ============================================================
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] git was not found in PATH.
    pause
    exit /b 2
)

for /f "delims=" %%R in ('git rev-parse --show-toplevel 2^>nul') do if not defined REPO_ROOT set "REPO_ROOT=%%R"
if not defined REPO_ROOT (
    echo [ERROR] This folder is not inside a Git repository.
    pause
    exit /b 3
)

set "ZIP_NAME="
for /f "delims=" %%F in ('dir /b /a-d /o-d "usb_link_logs\USB_LINK_JL22_KOZEN_*.zip" 2^>nul') do if not defined ZIP_NAME set "ZIP_NAME=%%F"

if not defined ZIP_NAME (
    echo [ERROR] No USB_LINK_JL22_KOZEN_*.zip found in:
    echo %CD%\usb_link_logs
    pause
    exit /b 4
)

set "LATEST_ZIP=%CD%\usb_link_logs\%ZIP_NAME%"
set "DEST_DIR=%CD%\test_reports\usb_link"
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

echo [COPY] %LATEST_ZIP%
echo     -> %DEST_DIR%\%ZIP_NAME%
copy /Y "%LATEST_ZIP%" "%DEST_DIR%\%ZIP_NAME%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy ZIP into test_reports.
    pause
    exit /b 5
)

powershell -NoProfile -Command "$p='%DEST_DIR%\%ZIP_NAME%'; $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant(); Set-Content -Encoding ASCII -LiteralPath ($p+'.sha256.txt') -Value ($h+'  '+[IO.Path]::GetFileName($p)); Write-Host ('SHA256: '+$h)"
if errorlevel 1 (
    echo [ERROR] Failed to create SHA-256 file.
    pause
    exit /b 6
)

echo.
echo [GIT] Current branch:
git branch --show-current
echo.

git add -- "test_reports/usb_link/%ZIP_NAME%" "test_reports/usb_link/%ZIP_NAME%.sha256.txt"
if errorlevel 1 (
    echo [ERROR] git add failed.
    pause
    exit /b 7
)

echo [GIT] Staged changes:
git diff --cached --stat
echo.

git diff --cached --quiet
if not errorlevel 1 (
    echo [INFO] Nothing new to commit. The result is already tracked.
    pause
    exit /b 0
)

git commit -m "Add JL22-Kozen USB live-link diagnostic %ZIP_NAME%"
if errorlevel 1 (
    echo [ERROR] git commit failed.
    pause
    exit /b 8
)

echo.
echo [GIT] Pushing current branch...
git push origin HEAD
if errorlevel 1 (
    echo [ERROR] git push failed. The commit remains safely in your local repository.
    pause
    exit /b 9
)

echo.
echo ============================================================
echo [SUCCESS] Latest USB diagnostic is now in Git.
echo ============================================================
pause
exit /b 0
