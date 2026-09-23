@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if not defined GIT_BRANCH (
  echo [ERROR] Detached HEAD is not supported for report publication.
  exit /b 10
)

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:w "fiscal_dryrun_selftest_logs\FISCAL_DRYRUN_SELFTEST_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No FISCAL_DRYRUN_SELFTEST_*.zip found.
  exit /b 11
)

set "SRC=fiscal_dryrun_selftest_logs\%LATEST%"
set "DST_DIR=test_reports\fiscal_dryrun_selftest"
if not exist "%DST_DIR%" mkdir "%DST_DIR%"
copy /y "%SRC%" "%DST_DIR%\%LATEST%" >nul
if errorlevel 1 exit /b 12

certutil -hashfile "%DST_DIR%\%LATEST%" SHA256 > "%DST_DIR%\%LATEST%.sha256.txt" 2>&1
if errorlevel 1 exit /b 13

git add -- "%DST_DIR%\%LATEST%" "%DST_DIR%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] Report already committed.
  exit /b 0
)

git commit -m "test: fiscal positive dryrun selftest %LATEST%"
if errorlevel 1 exit /b 14
git push origin HEAD
if errorlevel 1 exit /b 15

echo [SUCCESS] Fiscal DRY_RUN self-test report committed and pushed.
exit /b 0
