@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:w "main_ui_payment_logs\MAIN_UI_REAL_PAYMENT_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No MAIN_UI_REAL_PAYMENT_*.zip was found in main_ui_payment_logs.
  pause
  exit /b 2
)

set "SRC=main_ui_payment_logs\%LATEST%"
set "DST_DIR=test_reports\main_ui_payment"
if not exist "%DST_DIR%" mkdir "%DST_DIR%"
copy /y "%SRC%" "%DST_DIR%\%LATEST%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy %SRC%.
  pause
  exit /b 3
)

certutil -hashfile "%DST_DIR%\%LATEST%" SHA256 > "%DST_DIR%\%LATEST%.sha256.txt" 2>&1

git add -- "%DST_DIR%\%LATEST%" "%DST_DIR%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] This main-UI payment archive is already committed. Nothing to publish.
  pause
  exit /b 0
)

git commit -m "Add v0.5.21 main UI real payment %LATEST%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 4
)

git push origin v0.5.21-machine-modes
if errorlevel 1 (
  echo [ERROR] git push failed.
  pause
  exit /b 5
)

echo.
echo [SUCCESS] Latest main i-Retail UI payment diagnostic is now in Git.
echo %LATEST%
pause
