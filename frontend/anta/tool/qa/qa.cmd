@echo off
rem Entry point for cmd.exe and PowerShell. Compiles the tool on first use and
rem then runs the binary, so no verb pays for Dart's JIT startup.
setlocal
set "QA_ROOT=%~dp0..\.."
set "QA_EXE=%QA_ROOT%\build\qa\qa.exe"
if exist "%QA_EXE%" goto :run
>&2 echo qa: compiling %QA_EXE% (one-off, ~30 s)...
if not exist "%QA_ROOT%\build\qa" mkdir "%QA_ROOT%\build\qa"
pushd "%QA_ROOT%"
rem `call`, because `dart` on PATH is dart.bat and a .bat invoked without
rem `call` from a .cmd never comes back: control transfers and this script
rem silently ends before the verb ever runs.
call dart compile exe tool\qa\qa.dart -o build\qa\qa.exe 1>&2
popd
if exist "%QA_EXE%" goto :run
>&2 echo qa: could not compile the exe; falling back to `dart run`
pushd "%QA_ROOT%"
call dart run tool\qa\qa.dart %*
popd
exit /b %ERRORLEVEL%

:run
"%QA_EXE%" %*
exit /b %ERRORLEVEL%
