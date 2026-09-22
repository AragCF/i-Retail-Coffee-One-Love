@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.87-jl22-any-live-interface"
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  exit /b 10
)

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:w "fiscal_safe_smoke_logs\FISCAL_SAFE_SMOKE_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No FISCAL_SAFE_SMOKE_*.zip found.
  exit /b 11
)

set "SRC=fiscal_safe_smoke_logs\%LATEST%"
set "DST_DIR=test_reports\fiscal_safe_smoke"
if not exist "%DST_DIR%" mkdir "%DST_DIR%"
copy /y "%SRC%" "%DST_DIR%\%LATEST%" >nul
if errorlevel 1 exit /b 12

certutil -hashfile "%DST_DIR%\%LATEST%" SHA256 > "%DST_DIR%\%LATEST%.sha256.txt" 2>&1
if errorlevel 1 exit /b 13

git add -- "%DST_DIR%\%LATEST%" "%DST_DIR%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] Report is already committed.
  exit /b 0
)

git commit -m "test: v0.5.87 fiscal safe smoke %LATEST%"
if errorlevel 1 exit /b 14

git push origin HEAD
if errorlevel 1 exit /b 15

echo [SUCCESS] Latest fiscal safe smoke was committed and pushed.
exit /b 0
