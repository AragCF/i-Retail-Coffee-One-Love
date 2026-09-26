@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_BRANCH=v0.5.127-api-lifecycle-safety"
set "CURRENT_BRANCH="

echo ============================================================
echo i-Retail v0.5.125 - SBP SERVER CONFIG DOCUMENTATION AUDIT
echo ============================================================
echo.
echo PURPOSE:
echo   Determine from current public documentation whether SBP/shop
echo   enablement and verification can be done through an API, or
echo   requires i-Retail / PayIn-PayOut operator configuration.
echo.
echo SAFETY:
echo   Public documentation GET only.
echo   No authentication.
echo   No Kozen / ADB / SmartSkyPOS.
echo   No payment or configuration mutation.
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

echo [1/4] Auditing public server configuration documentation...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\iRetailSbpServerConfigDocsAudit.ps1" -RepoRoot "%CD%"
if errorlevel 1 (
  echo [ERROR] SBP server configuration documentation audit failed.
  pause
  exit /b 20
)

echo [2/4] Finding latest result ZIP...
set "LATEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\sbp_server_config_docs\SBP_SERVER_CONFIG_DOCS_*.zip" 2^>nul') do if not defined LATEST set "LATEST=%%F"
if not defined LATEST (
  echo [ERROR] Result ZIP was not created.
  pause
  exit /b 21
)

set "ARTIFACT=%CD%\test_reports\sbp_server_config_docs\%LATEST%"
echo [REPORT] %ARTIFACT%

echo [3/4] Auto-publishing artifact to current Git branch...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Publish-TestArtifact.ps1" ^
  -RepoRoot "%CD%" ^
  -ArtifactPath "%ARTIFACT%" ^
  -CommitPrefix "test: SBP server config docs audit"
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
echo SBP SERVER CONFIG DOCUMENTATION AUDIT COMPLETE
echo Public docs only: YES
echo Financial mutation: NO
echo Configuration mutation: NO
echo Git publication: AUTO_PUBLISH_OK
echo.
echo No manual archive upload is required.
echo Tell ChatGPT only that MAIN_40 has completed; the artifact is in Git.
echo ============================================================
pause
exit /b 0
