@echo off
rem Starts the Firebase emulator suite (auth + firestore) against the repo
rem rules, under the app's own project id: on Android the google-services
rem plugin creates the native default app, so the app's traffic arrives under
rem alexs-note-tracking-app and a suite started as another id would serve a
rem second namespace (record cloud-sync-phase-02 §3.8). Nothing can reach the
rem live project — the id is only a label the local emulator answers for.
rem Pass another id as the first argument; anything else is forwarded to the
rem CLI — nine arguments at most, since %* cannot be used after a shift and
rem no recorded call passes more than two. The config sits beside
rem firestore.rules because the CLI refuses rules outside its directory.
setlocal
pushd "%~dp0..\.."
set "project=alexs-note-tracking-app"
set "first=%~1"
rem A leading flag belongs to the CLI, not to the project argument.
if not defined first goto start
if "%first:~0,1%"=="-" goto start
set "project=%first%"
shift
:start
call firebase emulators:start --project "%project%" --config firebase.emulators.json %1 %2 %3 %4 %5 %6 %7 %8 %9
popd
endlocal
