@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.76-s3-admin-auth-permission-audit"
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
echo i-Retail v0.5.76 - READ-ONLY ADMIN AUTH / PERMISSION AUDIT
echo ============================================================
echo.
echo This test compares ordinary and admin authentication.
echo It reads permissions and may read admin/device/find only if admin login succeeds.
echo It does NOT create, update, activate, register, pay or send orders.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailAdminAuthPermissionAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Admin-auth permission audit failed.
  pause
  exit /b 20
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_admin_auth_permission\S3_ADMIN_AUTH_PERMISSION_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] ZIP report not found.
  pause
  exit /b 21
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3AdminAuthPermissionSafe.ps1" -ZipPath "%CD%\test_reports\s3_admin_auth_permission\%LATEST_FILE%"
if errorlevel 1 (
  echo [ERROR] ZIP safety validation failed.
  pause
  exit /b 22
)

call "%~dp0S3_25_PUBLISH_ADMIN_AUTH_PERMISSION.bat"
if errorlevel 1 (
  echo [ERROR] Publication failed.
  pause
  exit /b 23
)

echo [SUCCESS] Admin-auth permission audit completed and published.
powershell -NoProfile -Command "Write-Host 'Права обычной и административной авторизации опубликованы в Git, продолжай.'"
pause
exit /b 0
