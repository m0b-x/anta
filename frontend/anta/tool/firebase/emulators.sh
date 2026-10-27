#!/usr/bin/env sh
# Starts the Firebase emulator suite (auth + firestore) against the repo
# rules, under the app's own project id: on Android the google-services plugin
# creates the native default app, so the app's traffic arrives under
# alexs-note-tracking-app and a suite started as another id would serve a
# second namespace (record cloud-sync-phase-02 §3.8). Nothing can reach the
# live project — the id is only a label the local emulator answers for. Pass
# another id as the first argument; anything else is forwarded to the CLI. The
# config sits beside firestore.rules because the CLI refuses rules outside its
# directory.
set -e
cd "$(dirname "$0")/../.."
project=alexs-note-tracking-app
# A leading flag belongs to the CLI, not to the project argument.
case "${1-}" in '' | -*) ;; *) project=$1; shift ;; esac
exec firebase emulators:start --project "$project" --config firebase.emulators.json "$@"
