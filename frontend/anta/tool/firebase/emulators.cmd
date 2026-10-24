@echo off
rem Starts the Firebase emulator suite (auth + firestore) against the repo rules,
rem under the demo project so nothing can reach the live one. The config sits
rem beside firestore.rules because the CLI refuses rules outside its directory.
cd /d "%~dp0..\.."
firebase emulators:start --project demo-anta --config firebase.emulators.json %*
