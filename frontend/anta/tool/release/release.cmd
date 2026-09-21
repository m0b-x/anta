@echo off
rem Entry point for cmd.exe and PowerShell; see ./release for why `dart run`.
setlocal
pushd "%~dp0..\.."
rem `call`, because `dart` on PATH is dart.bat and a .bat invoked without
rem `call` never hands control back to this script.
call dart run tool\release\release.dart %*
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
