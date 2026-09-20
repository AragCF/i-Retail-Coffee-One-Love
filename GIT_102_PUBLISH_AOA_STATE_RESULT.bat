@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo Publish latest AOA SmartSkyPOS state diagnostic to Git
echo ============================================================

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git was not found in PATH.
  pause
  exit /b 2
)

set "LATEST_ZIP="
for /f "delims=" %%F in ('dir /b /a:-d /o:-d "aoa_state_logs\AOA_STATE_JL22_KOZEN_*.zip" 2^>nul') do if not defined LATEST_ZIP set "LATEST_ZIP=%CD%\aoa_state_logs\%%F"
if not defined LATEST_ZIP (
  echo [ERROR] No AOA_STATE_JL22_KOZEN_*.zip found.
  pause
  exit /b 3
)

for %%F in ("%LATEST_ZIP%") do set "ZIP_NAME=%%~nxF"
set "DEST_DIR=%CD%\test_reports\aoa_state"
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

echo [COPY] %LATEST_ZIP%
copy /Y "%LATEST_ZIP%" "%DEST_DIR%\%ZIP_NAME%" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed.
  pause
  exit /b 4
)

powershell -NoProfile -Command "$p='%DEST_DIR%\%ZIP_NAME%'; $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant(); Set-Content -Encoding ASCII -LiteralPath ($p+'.sha256.txt') -Value ($h+'  '+[IO.Path]::GetFileName($p)); Write-Host ('SHA256: '+$h)"
if errorlevel 1 (
  echo [ERROR] SHA-256 generation failed.
  pause
  exit /b 5
)

git add -- "test_reports/aoa_state/%ZIP_NAME%" "test_reports/aoa_state/%ZIP_NAME%.sha256.txt"
git diff --cached --quiet
if not errorlevel 1 (
  echo [INFO] Nothing new to commit.
  pause
  exit /b 0
)

git commit -m "Add JL22-Kozen SmartSkyPOS AOA state diagnostic %ZIP_NAME%"
if errorlevel 1 (
  echo [ERROR] git commit failed.
  pause
  exit /b 6
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] git push failed. Commit remains local.
  pause
  exit /b 7
)

echo.
echo [SUCCESS] Latest AOA SmartSkyPOS state diagnostic is now in Git.
pause
exit /b 0
