@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "ROOT=vendotek_ftdi_audit_logs"
set "DST=test_reports\vendotek_ftdi_audit"
set "LATEST="

if not exist "%ROOT%" (
  echo [ERROR] Folder not found: %ROOT%
  pause
  exit /b 2
)

for /f "delims=" %%F in ('dir /b /a-d /o-d "%ROOT%\VENDOTEK_FTDI_AUDIT_*.zip" 2^>nul') do (
  if not defined LATEST set "LATEST=%%F"
)
if not defined LATEST (
  echo [ERROR] No VENDOTEK_FTDI_AUDIT_*.zip found in %ROOT%.
  pause
  exit /b 3
)

if not exist "%DST%" mkdir "%DST%"
copy /y "%ROOT%\%LATEST%" "%DST%\%LATEST%" >nul
if errorlevel 1 (
  echo [ERROR] Could not copy %LATEST% to %DST%.
  pause
  exit /b 4
)

certutil -hashfile "%DST%\%LATEST%" SHA256 > "%DST%\%LATEST%.sha256.txt"

git add "%DST%\%LATEST%" "%DST%\%LATEST%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] This FTDI audit archive is already committed.
  pause
  exit /b 0
)

git commit -m "Add Vendotek Windows FTDI audit %LATEST%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 5
)

git push origin HEAD:v0.5.30-vendotek-windows-ftdi-audit
if errorlevel 1 (
  echo [ERROR] git push failed.
  pause
  exit /b 6
)

echo.
echo [SUCCESS] Latest Vendotek Windows FTDI audit is now in Git.
echo %LATEST%
pause
exit /b 0
