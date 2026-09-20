@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
set "EXPECTED=v0.5.33-vendotek-network-access"
set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
if not "%BRANCH%"=="%EXPECTED%" (
  echo [ERROR] Expected branch: %EXPECTED%
  echo Current branch: %BRANCH%
  pause
  exit /b 2
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Existing staged changes found. Resolve them first; they will not be committed by this script.
  pause
  exit /b 3
)
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-n "vendotek_network_logs\VENDOTEK_NETWORK_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] No new network report was found.
  pause
  exit /b 4
)
set "DST=test_reports\vendotek_network"
if not exist "%DST%" mkdir "%DST%"
copy /y "vendotek_network_logs\%LATEST%" "%DST%\%LATEST%" >nul
if errorlevel 1 goto FAILED
certutil -hashfile "%DST%\%LATEST%" SHA256 > "%DST%\%LATEST%.sha256.txt"
if errorlevel 1 goto FAILED
git add -- "%DST%\%LATEST%" "%DST%\%LATEST%.sha256.txt"
if errorlevel 1 goto FAILED
git diff --cached --quiet
if not errorlevel 1 goto PUSH
git commit -m "Add Vendotek limited network diagnostic %LATEST%"
if errorlevel 1 goto FAILED
:PUSH
git push origin HEAD:%EXPECTED%
if errorlevel 1 goto FAILED
echo.
echo [SUCCESS] Latest Vendotek network access result is now in Git.
echo %LATEST%
pause
exit /b 0
:FAILED
echo [ERROR] Publication stopped. Existing commits are preserved; no force push was used.
pause
exit /b 5
