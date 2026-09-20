@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo Publish latest Kozen-local SmartSkyPOS isolation result
 echo ============================================================

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:w "smartskypos_local_logs\SMARTSKYPOS_LOCAL_ISOLATION_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No SMARTSKYPOS_LOCAL_ISOLATION_*.zip found.
  pause
  exit /b 2
)

set "SRC=smartskypos_local_logs\%LATEST%"
set "DST=test_reports\smartskypos_local_isolation"
if not exist "%DST%" mkdir "%DST%"
copy /y "%SRC%" "%DST%\%LATEST%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy %SRC%.
  pause
  exit /b 3
)

certutil -hashfile "%DST%\%LATEST%" SHA256 > "%DST%\%LATEST%.sha256.txt" 2>&1

git add -- "%DST%\%LATEST%" "%DST%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] This archive is already committed. Nothing to publish.
  pause
  exit /b 0
)

git commit -m "Add Kozen-local SmartSkyPOS isolation %LATEST%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 4
)

git push origin v0.5.22-payment-diagnostics
if errorlevel 1 (
  echo [ERROR] git push failed.
  pause
  exit /b 5
)

echo.
echo [SUCCESS] Latest Kozen-local SmartSkyPOS isolation result is now in Git.
echo %LATEST%
pause
exit /b 0
