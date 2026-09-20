@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "SRC_DIR=vendotek_usb_logs"
set "DST_DIR=test_reports\vendotek_usb_discovery"

if not exist "%SRC_DIR%" (
  echo [ERROR] Folder not found: %SRC_DIR%
  pause
  exit /b 2
)

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "%SRC_DIR%\VENDOTEK_USB_DISCOVERY_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No VENDOTEK_USB_DISCOVERY_*.zip found in %SRC_DIR%
  pause
  exit /b 3
)

if not exist "%DST_DIR%" mkdir "%DST_DIR%"
copy /Y "%SRC_DIR%\%LATEST%" "%DST_DIR%\%LATEST%" >nul
if errorlevel 1 (
  echo [ERROR] Could not copy report ZIP.
  pause
  exit /b 4
)

certutil -hashfile "%DST_DIR%\%LATEST%" SHA256 > "%DST_DIR%\%LATEST%.sha256.txt" 2>&1

git add "%DST_DIR%\%LATEST%" "%DST_DIR%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] This exact report is already committed or there are no staged changes.
  echo %LATEST%
  pause
  exit /b 0
)

git commit -m "Add Vendotek USB discovery %LATEST%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 5
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] git push failed. Commit remains local.
  pause
  exit /b 6
)

echo.
echo [SUCCESS] Latest Vendotek USB discovery is now in Git.
echo %LATEST%
pause
exit /b 0
