@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.48-s3-order-contract-audit-fix"
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
echo i-Retail v0.5.48 - S3 ORDER CONTRACT DOCUMENTATION AUDIT
echo ============================================================
echo [1/2] Fetch current order-related API documentation.
echo [2/2] Package and publish evidence to Git.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\\iRetailOrderDocsAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Order API documentation audit failed.
  pause
  exit /b 20
)

call "%~dp0S3_03_PUBLISH_ORDER_API_DOCS.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but Git publication failed.
  pause
  exit /b 21
)

echo.
echo [SUCCESS] S3 order contract documentation audit completed and published.
powershell -NoProfile -Command "Write-Host 'Документация заказа в Git, продолжай.'"
pause
exit /b 0
