@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo Publish latest HARDENED PRODUCTION BRIDGE SAFE AUDIT to Git
echo ============================================================

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git was not found in PATH.
  pause
  exit /b 2
)

set "LATEST_ZIP="
for /f "delims=" %%F in ('dir /b /a:-d /o:-d "aoa_production_bridge_logs\AOA_PROD_BRIDGE_JL22_KOZEN_*.zip" 2^>nul') do if not defined LATEST_ZIP set "LATEST_ZIP=%CD%\aoa_production_bridge_logs\%%F"
if not defined LATEST_ZIP (
  echo [ERROR] No AOA_PROD_BRIDGE_JL22_KOZEN_*.zip found in:
  echo %CD%\aoa_production_bridge_logs
  pause
  exit /b 4
)

for %%F in ("%LATEST_ZIP%") do set "ZIP_NAME=%%~nxF"
set "DEST_DIR=%CD%\test_reports\aoa_production_bridge"
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

echo [COPY] %LATEST_ZIP%
copy /Y "%LATEST_ZIP%" "%DEST_DIR%\%ZIP_NAME%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy ZIP.
  pause
  exit /b 5
)

powershell -NoProfile -Command "$p='%DEST_DIR%\%ZIP_NAME%'; $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant(); Set-Content -Encoding ASCII -LiteralPath ($p+'.sha256.txt') -Value ($h+'  '+[IO.Path]::GetFileName($p)); Write-Host ('SHA256: '+$h)"
if errorlevel 1 (
  echo [ERROR] Failed to create SHA-256.
  pause
  exit /b 6
)

git add -- "test_reports/aoa_production_bridge/%ZIP_NAME%" "test_reports/aoa_production_bridge/%ZIP_NAME%.sha256.txt"
if errorlevel 1 (
  echo [ERROR] git add failed.
  pause
  exit /b 7
)

git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] Nothing new to commit.
  pause
  exit /b 0
)

git commit -m "Add hardened production bridge safe audit %ZIP_NAME%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 8
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] git push failed. Commit remains local.
  pause
  exit /b 9
)

echo.
echo [SUCCESS] Latest hardened production bridge safe audit is now in Git.
pause
exit /b 0
