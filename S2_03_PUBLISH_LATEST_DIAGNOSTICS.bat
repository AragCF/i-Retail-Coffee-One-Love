@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.44-s2-tls-chain-probe"
set "GIT_BRANCH="
where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 11
)
for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 12
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 13
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index already contains staged changes.
  git status --short
  pause
  exit /b 14
)

set "LATEST_ZIP="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s2_catalog_diagnostics\S2_DIAGNOSTICS_*.zip" 2^>nul') do if not defined LATEST_ZIP set "LATEST_ZIP=%CD%\test_reports\s2_catalog_diagnostics\%%F"

if not defined LATEST_ZIP (
  echo [ERROR] No S2_DIAGNOSTICS_*.zip found.
  echo Run S2_02_CATALOG_DIAGNOSTICS.bat first.
  pause
  exit /b 20
)

echo [INFO] Latest report:
echo %LATEST_ZIP%

powershell -NoProfile -Command "$z='%LATEST_ZIP%'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $a=[IO.Compression.ZipFile]::OpenRead($z); try{$n=$a.Entries.FullName; if($n -notcontains 'SUMMARY.txt'){exit 21}; if($n -notcontains '06_catalog_logcat.txt'){exit 22}} finally {$a.Dispose()}; exit 0"
set "ZIP_RC=%ERRORLEVEL%"
if "%ZIP_RC%"=="21" (
  echo [ERROR] ZIP has no SUMMARY.txt.
  pause
  exit /b 21
)
if "%ZIP_RC%"=="22" (
  echo [ERROR] ZIP has no 06_catalog_logcat.txt.
  pause
  exit /b 22
)
if not "%ZIP_RC%"=="0" (
  echo [ERROR] ZIP validation failed.
  pause
  exit /b 23
)

git add -- "%LATEST_ZIP%"
if errorlevel 1 (
  echo [ERROR] Could not stage report ZIP.
  pause
  exit /b 30
)

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
git commit -m "test: S2 catalog diagnostics %STAMP%"
if errorlevel 1 (
  echo [ERROR] Commit failed.
  pause
  exit /b 31
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] Push failed. Commit remains local and can be pushed later.
  pause
  exit /b 32
)

echo.
echo [SUCCESS] Latest S2 diagnostics ZIP was committed and pushed.
powershell -NoProfile -Command "Write-Host 'Отчёт в Git, продолжай.'"
pause
exit /b 0
