#!/usr/bin/env sh
# Starts the Firebase emulator suite (auth + firestore) against the repo rules,
# under the demo project so nothing can reach the live one. The config sits
# beside firestore.rules because the CLI refuses rules outside its directory.
set -e
cd "$(dirname "$0")/../.."
exec firebase emulators:start --project demo-anta --config firebase.emulators.json "$@"
