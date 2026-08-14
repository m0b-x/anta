#!/bin/bash
# Full nuclear clean: removes all caches and regenerates dependencies
set -e

echo "============================================"
echo " Full Clean"
echo "============================================"
echo ""

echo "[1/4] Running flutter clean..."
flutter clean || echo "WARNING: flutter clean had issues, continuing..."

echo "[2/4] Removing .dart_tool..."
rm -rf .dart_tool

echo "[3/4] Removing build_runner cache..."
rm -rf .dart_tool/build

echo "[4/4] Running flutter pub get..."
flutter pub get

echo ""
echo "Full clean complete. Run ./generate_drift.sh to regenerate .g.dart files."
