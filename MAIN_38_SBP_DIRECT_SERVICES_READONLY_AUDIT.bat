@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.123-sbp-direct-services-audit"
set "CURRENT_BRANCH="

echo ============================================================
echo i-Retail v0.5.123 - DIRECT SBP SERVICE AVAILABILITY AUDIT
echo ============================================================
echo.
echo PURPOSE:
echo   Prove which SBP services are actually available to this sales channel.
echo   Inspect current read-only PayIn-PayOut payment history shape.
echo.
echo SAFETY:
echo   Kozen is NOT required and is NOT contacted.
echo   SmartSkyPOS is NOT used.
echo   USB/AOA/ADB are NOT used.
echo   No order/payment/payment-in/refund is created.
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

echo [1/4] Running Kozen-free read-only server audit...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailDirectSbpServicesAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Direct SBP service audit failed.
  pause
  exit /b 20
)

echo [2/4] Finding latest result ZIP...
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\sbp_direct_services\SBP_DIRECT_SERVICES_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] Result ZIP was not created.
  pause
  exit /b 21
)

set "ARTIFACT=%CD%\test_reports\sbp_direct_services\%LATEST%"
echo [REPORT] %ARTIFACT%

echo [3/4] Auto-publishing artifact to current Git branch...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Publish-TestArtifact.ps1" ^
  -RepoRoot "%CD%" ^
  -ArtifactPath "%ARTIFACT%" ^
  -CommitPrefix "test: direct SBP service audit"
if errorlevel 1 (
  echo [ERROR] Audit succeeded, but automatic Git publication failed.
  echo [ERROR] The ZIP remains here:
  echo %ARTIFACT%
  pause
  exit /b 22
)

echo [4/4] Complete.
echo.
echo ============================================================
echo DIRECT SBP SERVICE READ-ONLY AUDIT COMPLETE
echo Kozen used: NO
echo SmartSkyPOS used: NO
echo AOA used: NO
echo Financial mutation: NO
echo Git publication: AUTO_PUBLISH_OK
echo.
echo No manual archive upload is required.
echo Tell ChatGPT only that MAIN_38 has completed; the artifact is in Git.
echo ============================================================
pause
exit /b 0
