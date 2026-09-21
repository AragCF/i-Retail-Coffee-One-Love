@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.66-s3-device-code-source-audit"
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

echo ============================================================
echo i-Retail v0.5.66 - READ-ONLY DEVICE CODE SOURCE AUDIT
echo ============================================================
echo No device/register call will be made.
echo No local configuration will be changed.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailDeviceCodeSourceAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Device-code source audit failed.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_device_code_source\S3_DEVICE_CODE_SOURCE_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] ZIP report not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3DeviceCodeSourceSafe.ps1" -ZipPath "%CD%\test_reports\s3_device_code_source\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed.
  pause
  exit /b 22
)

call "%~dp0S3_18_PUBLISH_DEVICE_CODE_SOURCE_AUDIT.bat"
if errorlevel 1 (
  echo [ERROR] Publication failed.
  pause
  exit /b 23
)

echo [SUCCESS] Device-code source audit completed and published.
powershell -NoProfile -Command "Write-Host 'Источник device_code проверен, отчёт в Git, продолжай.'"
pause
exit /b 0
