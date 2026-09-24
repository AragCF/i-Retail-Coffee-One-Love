@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "GIT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="v0.5.104-payment-marker-guard-fix" (
  echo [ERROR] Wrong branch for controlled payment evidence: %GIT_BRANCH%
  exit /b 10
)

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:w "fiscal_positive_payment_logs\FISCAL_POSITIVE_PAYMENT_1RUB_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No controlled-payment ZIP found.
  exit /b 11
)

set "SRC=fiscal_positive_payment_logs\%LATEST%"
set "SAFE=%SRC%.safe.txt"
if not exist "%SAFE%" (
  echo [ERROR] Safety sidecar is missing. Publication is forbidden.
  exit /b 12
)
findstr /C:"SAFETY_SCAN_OK" "%SAFE%" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Safety sidecar is invalid. Publication is forbidden.
  exit /b 13
)

set "DST_DIR=test_reports\fiscal_positive_payment_1rub"
if not exist "%DST_DIR%" mkdir "%DST_DIR%"
copy /y "%SRC%" "%DST_DIR%\%LATEST%" >nul
if errorlevel 1 exit /b 14
copy /y "%SAFE%" "%DST_DIR%\%LATEST%.safe.txt" >nul
if errorlevel 1 exit /b 15

certutil -hashfile "%DST_DIR%\%LATEST%" SHA256 > "%DST_DIR%\%LATEST%.sha256.txt" 2>&1
if errorlevel 1 exit /b 16

git add -- "%DST_DIR%\%LATEST%" "%DST_DIR%\%LATEST%.safe.txt" "%DST_DIR%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] Controlled-payment report already committed.
  exit /b 0
)

git commit -m "test: fiscal positive payment 1rub %LATEST%"
if errorlevel 1 exit /b 17
git push origin HEAD
if errorlevel 1 exit /b 18

echo [SUCCESS] Safe controlled-payment report committed and pushed.
exit /b 0
