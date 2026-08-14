@echo off
echo ============================================
echo  Full Clean
echo ============================================
echo.

echo [1/4] Running flutter clean...
call flutter clean
if %ERRORLEVEL% neq 0 (
    echo WARNING: flutter clean had issues, continuing...
)

echo [2/4] Removing .dart_tool...
if exist .dart_tool rmdir /s /q .dart_tool

echo [3/4] Removing build_runner cache...
if exist .dart_tool\build rmdir /s /q .dart_tool\build

echo [4/4] Running flutter pub get...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo ERROR: flutter pub get failed.
    exit /b %ERRORLEVEL%
)

echo.
echo Full clean complete. Run generate_drift.bat to regenerate .g.dart files.
