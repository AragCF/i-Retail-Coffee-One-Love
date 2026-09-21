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

echo ============================================================
echo i-Retail v0.5.64 - READ-ONLY STATE RECOVERY
echo ============================================================
echo No device/register call is made by this script.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailControlledDeviceRegisterProbe.ps1" -RepoRoot "%CD%" -ReadOnlyRecovery
if errorlevel 1 (
  echo [ERROR] Read-only recovery failed.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_device_register\S3_DEVICE_REGISTER_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] ZIP report not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3DeviceRegisterProbeSafe.ps1" -ZipPath "%CD%\test_reports\s3_device_register\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed.
  pause
  exit /b 22
)

call "%~dp0S3_15_PUBLISH_DEVICE_REGISTER_PROBE.bat"
if errorlevel 1 (
  echo [ERROR] Publication failed.
  pause
  exit /b 23
)

echo [SUCCESS] Read-only recovery state published.
pause
exit /b 0
