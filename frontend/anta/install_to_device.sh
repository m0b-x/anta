#!/bin/bash
# Usage: ./install_to_device.sh [arm64]
#   arm64  - Build for arm64 only (smaller APK, modern devices)
#   (none) - Build for all platforms
# Requires: USB debugging enabled, phone connected via USB
set -e

PLATFORM_FLAG=""
PLATFORM_LABEL="all platforms"
if [ "$1" = "arm64" ]; then
    PLATFORM_FLAG="--target-platform android-arm64"
    PLATFORM_LABEL="arm64 only"
fi

echo "============================================"
echo " Build + Install to Device"
echo " Target: $PLATFORM_LABEL"
echo "============================================"
echo ""

echo "[1/5] Running code generation (Drift)..."
dart run build_runner build --delete-conflicting-outputs

echo "[2/5] Generating localizations..."
flutter gen-l10n

echo "[3/5] Cleaning previous build..."
flutter clean

echo "[4/5] Building release APK ($PLATFORM_LABEL)..."
flutter build apk --release $PLATFORM_FLAG --obfuscate --split-debug-info=build/debug-info

echo "[5/5] Installing to device..."
adb install -r build/app/outputs/flutter-apk/app-release.apk

echo ""
echo "Installed successfully! The app should be on your device."
