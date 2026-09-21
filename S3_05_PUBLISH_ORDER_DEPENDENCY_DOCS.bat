@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.49-s3-order-dependency-audit"
set "GIT_BRANCH="
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

set "LATEST_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "test_reports\s3_order_dependencies\S3_ORDER_DEPS_*.zip" 2^>nul') do if not defined LATEST_FILE set "LATEST_FILE=%%F"
if not defined LATEST_FILE (
  echo [ERROR] No S3_ORDER_DEPS_*.zip found.
  pause
  exit /b 20
)

set "LATEST_REL=test_reports\s3_order_dependencies\%LATEST_FILE%"
set "LATEST_ZIP=%CD%\%LATEST_REL%"

powershell -NoProfile -Command "$z='%LATEST_ZIP%'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $a=[IO.Compression.ZipFile]::OpenRead($z); try{$n=$a.Entries.FullName; if($n -notcontains 'SUMMARY.txt'){exit 21}; if($n -notcontains '03_keyword_contexts.txt'){exit 22}} finally {$a.Dispose()}; exit 0"
if errorlevel 1 (
  echo [ERROR] ZIP validation failed.
  pause
  exit /b 23
)

git add -- "%LATEST_REL%"
if errorlevel 1 (
  echo [ERROR] Could not stage S3 dependency report.
  pause
  exit /b 30
)

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
git commit -m "test: S3 order dependency docs audit %STAMP%"
if errorlevel 1 (
  echo [ERROR] Commit failed.
  pause
  exit /b 31
)

git push origin HEAD
if errorlevel 1 (
  echo [ERROR] Push failed. Commit remains local.
  pause
  exit /b 32
)

echo [SUCCESS] Latest S3 dependency documentation ZIP was committed and pushed.
exit /b 0
