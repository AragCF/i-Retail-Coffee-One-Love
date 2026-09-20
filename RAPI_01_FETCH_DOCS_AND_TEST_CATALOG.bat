@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.42-s2-jl22-network-diagnostics"
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
echo i-Retail v0.5.42 - WINDOWS CURL API AUDIT
echo ============================================================
echo [1/3] Fetch current API documentation snapshot.
echo [2/3] Run the same authentication and catalog calls as Android.
echo [3/3] Sanitize, archive and publish the report to Git.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailApiCurlAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] API audit failed.
  pause
  exit /b 20
)

call "%~dp0RAPI_02_PUBLISH_LATEST_API_AUDIT.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but automatic Git publication failed.
  pause
  exit /b 21
)

echo.
echo [SUCCESS] API audit completed and published to Git.
powershell -NoProfile -Command "Write-Host 'Отчёт Retail API в Git. Можно продолжать анализ.'"
pause
exit /b 0
