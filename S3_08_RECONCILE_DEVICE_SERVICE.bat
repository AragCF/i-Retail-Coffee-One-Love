@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.51-s3-device-service-reconciliation"
set "GIT_BRANCH="

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 11
)
where curl.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] curl.exe not found in PATH.
  pause
  exit /b 12
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong Git branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 13
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 14
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index contains staged local changes.
  git status --short
  pause
  exit /b 15
)

echo ============================================================
echo i-Retail v0.5.51 - S3 DEVICE / SERVICE RECONCILIATION
echo ============================================================
echo [1/2] Authenticate and read device/service state.
echo [2/2] Sanitize, package and publish evidence to Git.
echo.
echo [SAFETY] No device registration, shift mutation, employee auth,
echo [SAFETY] payment creation or order synchronization is called.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailDeviceServiceReconciliation.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] S3 device/service reconciliation failed.
  pause
  exit /b 20
)

call "%~dp0S3_09_PUBLISH_DEVICE_SERVICE_RECONCILIATION.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but Git publication failed.
  pause
  exit /b 21
)

echo.
echo [SUCCESS] S3 device/service reconciliation completed and published.
powershell -NoProfile -Command "Write-Host 'Устройства и платёжные службы S3 в Git, продолжай.'"
pause
exit /b 0
