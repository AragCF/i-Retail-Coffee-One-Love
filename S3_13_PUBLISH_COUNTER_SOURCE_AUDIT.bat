@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.56-s3-counter-source-audit"
set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 12
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 13
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index already contains staged changes.
  git status --short
  pause
  exit /b 14
)

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_counter_sources\S3_COUNTER_SOURCES_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] No S3_COUNTER_SOURCES_*.zip found.
  pause
  exit /b 20
)

set "LATEST_REL=test_reports\s3_counter_sources\%LATEST_FILE%"

git add -- "%LATEST_REL%"
if errorlevel 1 (
  echo [ERROR] Could not stage S3 counter-source report.
  pause
  exit /b 30
)

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
git commit -m "test: S3 counter source docs %STAMP%"
if errorlevel 1 (
  echo [ERROR] Commit failed.
  pause
  exit /b 31
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] Push failed. Commit remains local.
  pause
  exit /b 32
)

echo [SUCCESS] Latest S3 counter-source ZIP was committed and pushed.
exit /b 0
