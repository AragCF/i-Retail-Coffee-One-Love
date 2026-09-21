@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.64-s3-device-register-probe"
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
echo i-Retail v0.5.64 - CONTROLLED DEVICE REGISTER PROBE
echo ============================================================
echo.
echo This is the approved one-shot S3 experiment.
echo It will:
echo   1. read current server device/shift state;
echo   2. call iretail/device/register exactly once;
echo   3. read server state again;
echo   4. never update local device configuration automatically.
echo.
echo If the result is uncertain, automatic retry is blocked.
echo No order, payment, shift-open/close or coffee command is sent.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailControlledDeviceRegisterProbe.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Controlled device/register probe did not complete.
  echo [IMPORTANT] If a marker was created, DO NOT delete it to retry automatically.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_device_register\S3_DEVICE_REGISTER_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] Probe completed but ZIP report was not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3DeviceRegisterProbeSafe.ps1" -ZipPath "%CD%\test_reports\s3_device_register\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed. Report will not be published.
  pause
  exit /b 22
)

call "%~dp0S3_15_PUBLISH_DEVICE_REGISTER_PROBE.bat"
if errorlevel 1 (
  echo [ERROR] Report exists but publication failed.
  pause
  exit /b 23
)

echo.
echo [SUCCESS] Controlled device/register probe completed and published.
powershell -NoProfile -Command "Write-Host 'Проба device/register опубликована в Git, продолжай.'"
pause
exit /b 0
