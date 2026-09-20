@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo Publish latest SmartSkyPOS READ-ONLY acquiring audit to Git
 echo ============================================================

set "SRC=smartskypos_acquirer_audit_logs"
set "DST=test_reports\smartskypos_acquirer_audit"
if not exist "%SRC%" (
  echo [ERROR] Folder not found: %CD%\%SRC%
  pause
  exit /b 2
)
if not exist "%DST%" mkdir "%DST%"

set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "%SRC%\SMARTSKYPOS_ACQUIRER_AUDIT_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No SMARTSKYPOS_ACQUIRER_AUDIT_*.zip found.
  pause
  exit /b 3
)

echo [COPY] %SRC%\%LATEST%
copy /Y "%SRC%\%LATEST%" "%DST%\%LATEST%" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed.
  pause
  exit /b 4
)

certutil -hashfile "%DST%\%LATEST%" SHA256 > "%DST%\%LATEST%.sha256.txt"
if errorlevel 1 (
  echo [ERROR] SHA256 calculation failed.
  pause
  exit /b 5
)

git add -- "%DST%\%LATEST%" "%DST%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] This exact latest audit is already committed; nothing to publish.
  pause
  exit /b 0
)

git commit -m "Add SmartSkyPOS read-only acquiring audit %LATEST%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 6
)

git push origin HEAD:v0.5.22-payment-diagnostics
if errorlevel 1 (
  echo [ERROR] git push failed.
  pause
  exit /b 7
)

echo.
echo [SUCCESS] Latest SmartSkyPOS read-only acquiring audit is now in Git.
echo %LATEST%
pause
exit /b 0
