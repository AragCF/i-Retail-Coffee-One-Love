@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.70-s3-external-register-probe"
set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"

if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail v0.5.70 - EXTERNAL REGISTER READ-ONLY RECOVERY
echo ============================================================
echo No register-external-system call is made by this script.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailControlledExternalSystemRegisterProbe.ps1" -RepoRoot "%CD%" -ReadOnlyRecovery
if errorlevel 1 (
  echo [ERROR] Read-only recovery failed.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_external_register\S3_EXTERNAL_REGISTER_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] ZIP report not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3ExternalSystemRegisterProbeSafe.ps1" -ZipPath "%CD%\test_reports\s3_external_register\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed.
  pause
  exit /b 22
)

call "%~dp0S3_20_PUBLISH_EXTERNAL_SYSTEM_REGISTER_PROBE.bat"
if errorlevel 1 (
  echo [ERROR] Publication failed.
  pause
  exit /b 23
)

echo [SUCCESS] Read-only external-register recovery state published.
pause
exit /b 0
