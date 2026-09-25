@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.122-sbp-direct-server-audit"
set "CURRENT_BRANCH="

echo ============================================================
echo i-Retail v0.5.122 - DIRECT SBP SERVER READ-ONLY AUDIT
echo ============================================================
echo.
echo PURPOSE:
echo   Verify how JL22 can create/show SBP QR WITHOUT Kozen.
echo.
echo SAFETY:
echo   Kozen is NOT required and is NOT contacted.
echo   SmartSkyPOS is NOT used.
echo   USB/AOA is NOT used.
echo   No order/payment/payment-in is created.
echo   Only public API docs + authenticated read-only service/channel calls.
echo ============================================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git was not found.
  pause
  exit /b 10
)

where curl.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] curl.exe was not found.
  pause
  exit /b 11
)

where powershell >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell was not found.
  pause
  exit /b 12
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined CURRENT_BRANCH set "CURRENT_BRANCH=%%B"
if /I not "%CURRENT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong Git branch: %CURRENT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 13
)

echo [1/3] Auditing current i-Retail API documentation and read-only service configuration...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailDirectSbpReadonlyAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Direct SBP read-only audit failed.
  pause
  exit /b 20
)

echo [2/3] Finding latest report...
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\sbp_direct_server\SBP_DIRECT_SERVER_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] Audit ZIP was not created.
  pause
  exit /b 21
)

echo [REPORT] %CD%\test_reports\sbp_direct_server\%LATEST%

echo [3/3] Complete.
echo.
echo ============================================================
echo DIRECT SBP SERVER READ-ONLY AUDIT COMPLETE
echo Kozen used: NO
echo SmartSkyPOS used: NO
echo AOA used: NO
echo Financial mutation: NO
echo.
echo Send this file:
echo   test_reports\sbp_direct_server\%LATEST%
echo ============================================================
pause
exit /b 0
