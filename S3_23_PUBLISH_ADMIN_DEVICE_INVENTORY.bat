@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.73-s3-admin-device-inventory-audit"
set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"

if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
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

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_admin_device_inventory\S3_ADMIN_DEVICE_INVENTORY_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] No admin device inventory ZIP found.
  pause
  exit /b 20
)

set "REL=test_reports\s3_admin_device_inventory\%LATEST_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3AdminDeviceInventorySafe.ps1" -ZipPath "%CD%\%REL%"
if errorlevel 1 exit /b 21

git add -- "%REL%"
if errorlevel 1 exit /b 30

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
git commit -m "test: S3 admin device inventory %STAMP%"
if errorlevel 1 exit /b 31

git push origin HEAD
if errorlevel 1 exit /b 32

echo [SUCCESS] Latest admin-device inventory ZIP committed and pushed.
exit /b 0
