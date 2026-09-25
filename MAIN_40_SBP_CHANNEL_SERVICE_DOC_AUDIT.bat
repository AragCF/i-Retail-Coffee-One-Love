@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.125-sbp-channel-service-doc-audit"
set "CURRENT_BRANCH="

echo ============================================================
echo i-Retail v0.5.125 - SBP CHANNEL/SERVICE DOCUMENTATION AUDIT
echo ============================================================
echo.
echo PURPOSE:
echo   Find the documented way to attach/enable/verify SBP services
echo   for an i-Retail channel/shop before involving support.
echo.
echo SAFETY:
echo   Public API documentation GET only.
echo   No authentication.
echo   No working API calls.
echo   No channel/payment/shop mutation.
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

echo [1/4] Auditing current public API documentation...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailSbpChannelServiceDocsAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] Documentation audit failed.
  pause
  exit /b 20
)

echo [2/4] Finding latest result ZIP...
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\sbp_channel_service_docs\SBP_CHANNEL_SERVICE_DOCS_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] Result ZIP was not created.
  pause
  exit /b 21
)

set "ARTIFACT=%CD%\test_reports\sbp_channel_service_docs\%LATEST%"
echo [REPORT] %ARTIFACT%

echo [3/4] Auto-publishing artifact to current Git branch...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Publish-TestArtifact.ps1" ^
  -RepoRoot "%CD%" ^
  -ArtifactPath "%ARTIFACT%" ^
  -CommitPrefix "test: SBP channel service docs"
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
echo SBP CHANNEL/SERVICE DOCUMENTATION AUDIT COMPLETE
echo Working API calls: 0
echo Financial mutation: NO
echo Git publication: AUTO_PUBLISH_OK
echo.
echo No manual archive upload is required.
echo Tell ChatGPT only that MAIN_40 has completed; the artifact is in Git.
echo ============================================================
pause
exit /b 0
