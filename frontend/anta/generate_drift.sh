#!/bin/bash
# Usage: ./generate_drift.sh [watch]
#   watch  - Continuously watch for changes and regenerate
#   (none) - One-time generation
set -e

if [ "$1" = "watch" ]; then
    echo "Watching for Drift changes... (Ctrl+C to stop)"
    dart run build_runner watch --delete-conflicting-outputs
else
    echo "Generating Drift classes..."
    dart run build_runner build --delete-conflicting-outputs
fi
