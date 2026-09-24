@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="v0.5.112-sbp-route-audit" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  exit /b 2
)

set "LATEST_ZIP="
for /f "delims=" %%F in ('dir /b /a:-d /o:-d "sbp_route_logs\SBP_ROUTE_AUDIT_*.zip" 2^>nul') do if not defined LATEST_ZIP set "LATEST_ZIP=%CD%\sbp_route_logs\%%F"
if not defined LATEST_ZIP exit /b 3
if not exist "%LATEST_ZIP%.safe.txt" exit /b 4
findstr /X /C:"SAFETY_SCAN_OK" "%LATEST_ZIP%.safe.txt" >nul 2>nul
if errorlevel 1 exit /b 5

for %%F in ("%LATEST_ZIP%") do set "ZIP_NAME=%%~nxF"
set "DEST_DIR=%CD%\test_reports\sbp_route_audit"
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

copy /Y "%LATEST_ZIP%" "%DEST_DIR%\%ZIP_NAME%" >nul || exit /b 6
copy /Y "%LATEST_ZIP%.safe.txt" "%DEST_DIR%\%ZIP_NAME%.safe.txt" >nul || exit /b 7
powershell -NoProfile -Command "$p='%DEST_DIR%\%ZIP_NAME%'; $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant(); Set-Content -Encoding ASCII -LiteralPath ($p+'.sha256.txt') -Value ($h+'  '+[IO.Path]::GetFileName($p))"
if errorlevel 1 exit /b 8

git add -- "test_reports/sbp_route_audit/%ZIP_NAME%" "test_reports/sbp_route_audit/%ZIP_NAME%.safe.txt" "test_reports/sbp_route_audit/%ZIP_NAME%.sha256.txt"
if errorlevel 1 exit /b 9
git diff --cached --quiet
if not errorlevel 1 exit /b 0
git commit -m "test: SBP route read-only audit %ZIP_NAME%"
if errorlevel 1 exit /b 10
git push origin HEAD
if errorlevel 1 exit /b 11
echo [SUCCESS] Safe SBP route audit report committed and pushed.
exit /b 0
