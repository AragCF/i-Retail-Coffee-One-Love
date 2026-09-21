@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.73-s3-admin-device-inventory-audit"
set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"

if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 11
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 12
)

git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index contains staged changes.
  git status --short
  pause
  exit /b 13
)

echo ============================================================
echo i-Retail v0.5.73 - READ-ONLY ADMIN DEVICE INVENTORY
echo ============================================================
echo.
echo This test only reads admin device inventory.
echo It does NOT create, update, activate, remove, register or send orders.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailAdminDeviceInventoryAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Admin device inventory audit failed.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_admin_device_inventory\S3_ADMIN_DEVICE_INVENTORY_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] ZIP report not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3AdminDeviceInventorySafe.ps1" -ZipPath "%CD%\test_reports\s3_admin_device_inventory\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed.
  pause
  exit /b 22
)

call "%~dp0S3_23_PUBLISH_ADMIN_DEVICE_INVENTORY.bat"
if errorlevel 1 (
  echo [ERROR] Publication failed.
  pause
  exit /b 23
)

echo [SUCCESS] Read-only admin device inventory completed and published.
powershell -NoProfile -Command "Write-Host 'Административный список устройств опубликован в Git, продолжай.'"
pause
exit /b 0
