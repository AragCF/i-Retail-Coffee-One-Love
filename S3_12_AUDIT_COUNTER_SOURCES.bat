@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.56-s3-counter-source-audit"
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
  echo [ERROR] Wrong branch: %GIT_BRANCH%
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
echo i-Retail v0.5.56 - S3 COUNTER SOURCE DOCUMENTATION AUDIT
echo ============================================================
echo [1/3] Fetch the current published API documentation index.
echo [2/3] Discover every iretail controller page and locate counters.
echo [3/3] Publish the documentation-only evidence ZIP to Git.
echo.
echo [SAFETY] Documentation GET requests only.
echo [SAFETY] No authentication, device registration, shift mutation,
echo [SAFETY] employee authorization, payment creation or order synchronization.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailCounterSourceDocsAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] S3 counter-source documentation audit failed.
  pause
  exit /b 20
)

call "%~dp0S3_13_PUBLISH_COUNTER_SOURCE_AUDIT.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but Git publication failed.
  pause
  exit /b 21
)

echo.
echo [SUCCESS] S3 counter-source audit completed and published.
powershell -NoProfile -Command "Write-Host 'Источники счётчиков S3 в Git, продолжай.'"
pause
exit /b 0
