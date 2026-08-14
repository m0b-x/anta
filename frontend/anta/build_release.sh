#!/bin/bash
# Usage: ./build_release.sh [arm64]
#   arm64  - Build for arm64 only (smaller APK, modern devices)
#   (none) - Build for all platforms
set -e

PLATFORM_FLAG=""
PLATFORM_LABEL="all platforms"
if [ "$1" = "arm64" ]; then
    PLATFORM_FLAG="--target-platform android-arm64"
    PLATFORM_LABEL="arm64 only"
fi

echo "============================================"
echo " Flutter Release Build"
echo " Target: $PLATFORM_LABEL"
echo "============================================"
echo ""

echo "[1/4] Running code generation (Drift)..."
dart run build_runner build --delete-conflicting-outputs

echo "[2/4] Generating localizations..."
flutter gen-l10n

echo "[3/4] Cleaning previous build..."
flutter clean

echo "[4/4] Building release APK ($PLATFORM_LABEL)..."
flutter build apk --release $PLATFORM_FLAG --obfuscate --split-debug-info=build/debug-info

echo ""
echo "Build successful! APK is at: build/app/outputs/flutter-apk/app-release.apk"
echo "Debug symbols saved to:       build/debug-info/"
open build/app/outputs/flutter-apk
