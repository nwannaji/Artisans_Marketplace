#!/usr/bin/env bash
# Build a minified release APK and rename it to fixit-release.apk
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleaning..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

echo "🏗️  Building release APK..."
flutter build apk --release

# Flutter always outputs app-release.apk — rename it
APK_DIR="build/app/outputs/flutter-apk"
SRC="$APK_DIR/app-release.apk"
DST="$APK_DIR/fixit-release.apk"

if [ -f "$SRC" ]; then
    mv "$SRC" "$DST"
    # Also rename the sha1 file if it exists
    [ -f "$APK_DIR/app-release.apk.sha1" ] && mv "$APK_DIR/app-release.apk.sha1" "$APK_DIR/fixit-release.apk.sha1"
    echo "✅ Built: $DST ($(du -h "$DST" | cut -f1))"
else
    echo "❌ Build failed — $SRC not found"
    exit 1
fi