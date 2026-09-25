@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.124-sbp-channel-inventory"
set "CURRENT_BRANCH="

echo ============================================================
echo i-Retail v0.5.124 - SBP PROFILE CHANNEL INVENTORY
echo ============================================================
echo.
echo PURPOSE:
echo   Find every channel in the configured profile and prove whether
echo   any existing channel already has SBP / sbp_low_risk available.
echo.
echo SAFETY:
echo   Kozen / SmartSkyPOS / AOA / ADB are NOT used.
echo   No payment, order or channel configuration is changed.
echo   Result ZIP is automatically committed and pushed to Git.
echo ============================================================
echo.

for %%T in (git curl.exe powershell) do (
  where %%T >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] %%T was not found.
    pause
    exit /b 10
  )
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined CURRENT_BRANCH set "CURRENT_BRANCH=%%B"
if /I not "%CURRENT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong Git branch: %CURRENT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 11
)

echo [1/4] Auditing profile channels and their available payment services...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailSbpChannelInventory.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] SBP channel inventory failed.
  pause
  exit /b 20
)

echo [2/4] Finding latest result ZIP...
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\sbp_channel_inventory\SBP_CHANNEL_INVENTORY_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] Result ZIP was not created.
  pause
  exit /b 21
)

set "ARTIFACT=%CD%\test_reports\sbp_channel_inventory\%LATEST%"
echo [REPORT] %ARTIFACT%

echo [3/4] Auto-publishing artifact to current Git branch...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Publish-TestArtifact.ps1" ^
  -RepoRoot "%CD%" ^
  -ArtifactPath "%ARTIFACT%" ^
  -CommitPrefix "test: SBP profile channel inventory"
if errorlevel 1 (
  echo [ERROR] Inventory succeeded, but automatic Git publication failed.
  echo [ERROR] The ZIP remains here:
  echo %ARTIFACT%
  pause
  exit /b 22
)

echo [4/4] Complete.
echo.
echo ============================================================
echo SBP PROFILE CHANNEL INVENTORY COMPLETE
echo Financial mutation: NO
echo Git publication: AUTO_PUBLISH_OK
echo.
echo No manual archive upload is required.
echo Tell ChatGPT only that MAIN_39 has completed; the artifact is in Git.
echo ============================================================
pause
exit /b 0
