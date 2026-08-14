@echo off
rem Usage: build_release.bat [arm64]
rem   arm64  - Build for arm64 only (smaller APK, modern devices)
rem   (none) - Build for all platforms

set PLATFORM_FLAG=
set PLATFORM_LABEL=all platforms
if /i "%1"=="arm64" (
    set PLATFORM_FLAG=--target-platform android-arm64
    set PLATFORM_LABEL=arm64 only
)

echo ============================================
echo  Flutter Release Build
echo  Target: %PLATFORM_LABEL%
echo ============================================
echo.

echo [1/4] Running code generation (Drift)...
call dart run build_runner build --delete-conflicting-outputs
if %ERRORLEVEL% neq 0 (
    echo ERROR: build_runner failed.
    exit /b %ERRORLEVEL%
)

echo [2/4] Generating localizations...
call flutter gen-l10n
if %ERRORLEVEL% neq 0 (
    echo ERROR: gen-l10n failed.
    exit /b %ERRORLEVEL%
)

echo [3/4] Cleaning previous build...
call flutter clean
if %ERRORLEVEL% neq 0 (
    echo ERROR: flutter clean failed.
    exit /b %ERRORLEVEL%
)

echo [4/4] Building release APK (%PLATFORM_LABEL%)...
call flutter build apk --release %PLATFORM_FLAG% --obfuscate --split-debug-info=build\debug-info
if %ERRORLEVEL% neq 0 (
    echo ERROR: flutter build apk failed.
    exit /b %ERRORLEVEL%
)

echo.
echo Build successful! APK is at: build\app\outputs\flutter-apk\app-release.apk
explorer build\app\outputs\flutter-apk
