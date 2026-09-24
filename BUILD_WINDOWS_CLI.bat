@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem i-Retail Android UI v0.5.112 sbp adapter boundary
rem Windows CLI debug APK build script.
rem
rem Important:
rem DelayedExpansion is intentionally disabled because project paths may
rem contain the exclamation mark character, for example: !0719 - Coffee.
rem
rem Default mode DOES NOT run Gradle clean. On Windows, clean often fails
rem when Explorer, antivirus, Total Commander, Android Studio, adb install,
rem or another process keeps app\build\outputs\apk\debug open.
rem
rem Optional modes:
rem   BUILD_WINDOWS_CLI.bat --clean
rem   BUILD_WINDOWS_CLI.bat --hardclean

cd /d "%~dp0"
if errorlevel 1 (
    echo [ERROR] Failed to switch to the project folder:
    echo %~dp0
    exit /b 9
)

set "SCRIPT_VERSION=0.5.112-sbp-adapter-boundary"
set "DO_CLEAN=0"
set "DO_HARD_CLEAN=0"

if /I "%~1"=="clean" set "DO_CLEAN=1"
if /I "%~1"=="--clean" set "DO_CLEAN=1"
if /I "%~1"=="hardclean" set "DO_HARD_CLEAN=1"
if /I "%~1"=="--hardclean" set "DO_HARD_CLEAN=1"
if "%DO_HARD_CLEAN%"=="1" set "DO_CLEAN=0"

echo ============================================================
echo i-Retail Android UI v%SCRIPT_VERSION% - Windows CLI build
echo ============================================================
echo Project: %CD%
if "%DO_CLEAN%"=="1" echo Mode: Gradle clean, then assembleDebug
if "%DO_HARD_CLEAN%"=="1" echo Mode: hard clean folders, then assembleDebug
if "%DO_CLEAN%"=="0" if "%DO_HARD_CLEAN%"=="0" echo Mode: assembleDebug without clean

echo.

if not exist "settings.gradle" (
    echo [ERROR] settings.gradle was not found.
    echo Run this script from the project root folder.
    exit /b 10
)

where java >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Java was not found in PATH.
    echo Install JDK 17 or JDK 21 and add JAVA_HOME\bin to PATH.
    exit /b 11
)

echo [OK] Java found:
java -version
echo.

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"

if not defined SDK_PATH (
    if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
)

if not defined SDK_PATH (
    echo [ERROR] Android SDK was not found.
    echo Set ANDROID_HOME or ANDROID_SDK_ROOT, or install Android Studio SDK.
    exit /b 12
)

if not exist "%SDK_PATH%" (
    echo [ERROR] Android SDK folder does not exist:
    echo %SDK_PATH%
    exit /b 13
)

echo [OK] Android SDK: %SDK_PATH%

set "SDK_PATH_GRADLE=%SDK_PATH:\=/%"
> local.properties echo sdk.dir=%SDK_PATH_GRADLE%
echo [OK] local.properties updated.
echo.

set "GRADLE_CMD="
if exist "gradlew.bat" (
    set "GRADLE_CMD=%CD%\gradlew.bat"
) else (
    for /f "delims=" %%G in ('where gradle.bat 2^>nul') do (
        if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
    )
    if not defined GRADLE_CMD (
        for /f "delims=" %%G in ('where gradle 2^>nul') do (
            if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
        )
    )
)

if not defined GRADLE_CMD (
    echo [ERROR] Gradle was not found.
    echo Install Gradle 8.7-8.10.x and add Gradle\bin to PATH,
    echo or open the project in Android Studio once and configure a Gradle wrapper.
    exit /b 14
)

echo [OK] Gradle command: %GRADLE_CMD%
call "%GRADLE_CMD%" --version
if errorlevel 1 (
    echo [ERROR] Gradle version check failed.
    exit /b 15
)
echo.
echo [NOTE] The current project was also tested from your logs with Gradle 9.4.1.
echo [NOTE] If Android Gradle Plugin compatibility errors appear, use Gradle 8.7-8.10.x.
echo.

echo [BUILD] Stopping existing Gradle daemons, if any...
call "%GRADLE_CMD%" --stop >nul 2>nul

set "DISK_CLEANUP_THRESHOLD_MB=2048"
set "DISK_MINIMUM_MB=1024"
set "GRADLE_CACHE_ARG="
call :ReadFreeSpace
echo [DISK] Free space before build: %FREE_MB% MB

if %FREE_MB% LSS %DISK_CLEANUP_THRESHOLD_MB% (
    set "GRADLE_CACHE_ARG=--no-build-cache"
    call :LowDiskCacheCleanup
) else (
    echo [DISK] At least 2 GB is free. No cache cleanup; Gradle cache remains enabled.
)

call :ReadFreeSpace
echo [DISK] Free space before Gradle tasks: %FREE_MB% MB
if %FREE_MB% LSS %DISK_MINIMUM_MB% (
    echo [ERROR] Not enough free disk space for a reliable Android build.
    echo [ERROR] Free: %FREE_MB% MB. Required: at least %DISK_MINIMUM_MB% MB.
    echo [INFO] Recoverable caches were cleaned because free space was below 2 GB.
    echo [INFO] Free additional space on the drive containing this project and run again.
    exit /b 16
)

echo [BUILD] Removing obsolete source files from old unpacked folders, if any...
call :RemoveObsoleteSources

if "%DO_HARD_CLEAN%"=="1" (
    echo.
    echo [BUILD] Hard-cleaning build folders...
    call :HardCleanBuildFolders
)

if "%DO_CLEAN%"=="1" (
    echo.
    echo [BUILD] Running Gradle clean...
    call "%GRADLE_CMD%" --no-daemon %GRADLE_CACHE_ARG% --stacktrace :app:clean
    if errorlevel 1 (
        echo.
        echo [WARN] Gradle clean failed, most likely because Windows locked app\build.
        echo [WARN] Build will continue without clean. Close Explorer/Total Commander/Android Studio
        echo [WARN] windows opened inside app\build\outputs\apk\debug if the next step fails.
    ) else (
        echo [OK] Gradle clean completed.
    )
) else (
    echo [BUILD] Clean step skipped. This is intentional for Windows stability.
)

echo.
echo [BUILD] Assembling debug APK...
call "%GRADLE_CMD%" --no-daemon %GRADLE_CACHE_ARG% --stacktrace :app:assembleDebug
if errorlevel 1 (
    echo [ERROR] Debug APK build failed.
    echo [HINT] If the error mentions a locked APK or app\build folder, close any program
    echo [HINT] opened in app\build\outputs\apk\debug, then run:
    echo [HINT] BUILD_WINDOWS_CLI.bat --hardclean
    exit /b 21
)

set "APK_SOURCE=app\build\outputs\apk\debug\app-debug.apk"
set "DIST_DIR=dist"

if not exist "%APK_SOURCE%" (
    echo [ERROR] APK file was not created:
    echo %APK_SOURCE%
    exit /b 22
)

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

set "BUILD_TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do (
    if not defined BUILD_TS set "BUILD_TS=%%T"
)
if not defined BUILD_TS set "BUILD_TS=manual"

set "APK_TARGET=%DIST_DIR%\iRetail_Android_UI_v%SCRIPT_VERSION%-debug-%BUILD_TS%.apk"
set "APK_LATEST=%DIST_DIR%\iRetail_Android_UI_v%SCRIPT_VERSION%-debug-latest.apk"

copy /Y "%APK_SOURCE%" "%APK_TARGET%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy APK to timestamped dist file.
    exit /b 23
)

copy /Y "%APK_SOURCE%" "%APK_LATEST%" >nul
if errorlevel 1 (
    echo [WARN] Failed to update latest APK copy, probably because it is opened elsewhere.
    echo [WARN] Timestamped APK was still created successfully.
)

echo.
echo ============================================================
echo [SUCCESS] Debug APK built successfully.
echo Output:
echo %CD%\%APK_TARGET%
if exist "%APK_LATEST%" echo Latest: %CD%\%APK_LATEST%
echo ============================================================

exit /b 0

:ReadFreeSpace
set "FREE_MB="
for /f "delims=" %%F in ('powershell -NoProfile -Command "$r=[System.IO.Path]::GetPathRoot((Get-Location).Path); $d=Get-PSDrive -Name $r.Substring(0,1); [math]::Floor($d.Free/1MB)" 2^>nul') do if not defined FREE_MB set "FREE_MB=%%F"
if not defined FREE_MB set "FREE_MB=0"
exit /b 0

:LowDiskCacheCleanup
echo [DISK] Less than 2 GB is free. Cleaning recoverable development caches...
call "%GRADLE_CMD%" --stop >nul 2>nul

echo [DISK] Project caches and build outputs...
if exist ".gradle" rmdir /S /Q ".gradle" 2>nul
if exist "build" rmdir /S /Q "build" 2>nul
for /d %%D in (*) do (
    if exist "%%D\build" rmdir /S /Q "%%D\build" 2>nul
)

echo [DISK] Temporary Gradle and Kotlin caches...
if exist "%USERPROFILE%\.gradle\.tmp" rmdir /S /Q "%USERPROFILE%\.gradle\.tmp" 2>nul
if exist "%USERPROFILE%\.gradle\daemon" rmdir /S /Q "%USERPROFILE%\.gradle\daemon" 2>nul
for /d %%D in ("%USERPROFILE%\.gradle\caches\build-cache-*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul
for /d %%D in ("%USERPROFILE%\.gradle\caches\transforms-*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul
for /d %%D in ("%USERPROFILE%\.gradle\caches\jars-*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul
if exist "%USERPROFILE%\.kotlin\daemon" rmdir /S /Q "%USERPROFILE%\.kotlin\daemon" 2>nul
if exist "%LOCALAPPDATA%\kotlin\daemon" rmdir /S /Q "%LOCALAPPDATA%\kotlin\daemon" 2>nul
if exist "%USERPROFILE%\.android\cache" rmdir /S /Q "%USERPROFILE%\.android\cache" 2>nul

echo [DISK] Temporary files with Gradle/Kotlin/Android prefixes...
for /d %%D in ("%TEMP%\gradle*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul
for /d %%D in ("%TEMP%\kotlin*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul
for /d %%D in ("%TEMP%\android*") do if exist "%%~fD" rmdir /S /Q "%%~fD" 2>nul

call :ReadFreeSpace
if %FREE_MB% LSS %DISK_CLEANUP_THRESHOLD_MB% (
    echo [DISK] Still below 2 GB. Clearing Gradle dependency cache; dependencies may be downloaded again.
    if exist "%USERPROFILE%\.gradle\caches\modules-2" rmdir /S /Q "%USERPROFILE%\.gradle\caches\modules-2" 2>nul
)

echo [DISK] Low-space cache cleanup completed. Source files and Android SDK packages were not touched.
exit /b 0

:HardCleanBuildFolders
call "%GRADLE_CMD%" --stop >nul 2>nul
if exist "app\build" (
    rmdir /S /Q "app\build" 2>nul
    if exist "app\build" (
        echo [WARN] Could not remove app\build. A Windows process is still using it.
        echo [WARN] Continuing anyway; assembleDebug often works without deleting this folder.
    ) else (
        echo [OK] Removed app\build.
    )
) else (
    echo [OK] app\build does not exist.
)

if exist "build" (
    rmdir /S /Q "build" 2>nul
    if exist "build" (
        echo [WARN] Could not remove root build folder. Continuing anyway.
    ) else (
        echo [OK] Removed root build folder.
    )
) else (
    echo [OK] root build folder does not exist.
)
exit /b 0


:RemoveObsoleteSources
if exist "app\src\main\java\com\coffeeonelove\iretail\ui\MockGateways.kt" (
    del /F /Q "app\src\main\java\com\coffeeonelove\iretail\ui\MockGateways.kt" >nul 2>nul
    if exist "app\src\main\java\com\coffeeonelove\iretail\ui\MockGateways.kt" (
        echo [WARN] Could not remove obsolete MockGateways.kt. Gradle will try to remove it too.
    ) else (
        echo [OK] Removed obsolete MockGateways.kt.
    )
) else (
    echo [OK] No obsolete MockGateways.kt found.
)
exit /b 0
