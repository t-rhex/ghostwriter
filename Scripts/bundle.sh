#!/bin/bash
#
# Build Ghostwriter and package it as a macOS .app bundle.
# The bundle is what macOS needs to show the app in
# System Settings > Privacy & Security > Input Monitoring / Accessibility.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Ghostwriter.app"
APP_DIR="$PROJECT_DIR/.build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "=== Building Ghostwriter.app ==="

# 1. Build release binary
echo "[1/2] Compiling..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

# 2. Assemble .app bundle
echo "[2/3] Assembling $APP_NAME..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp ".build/release/Ghostwriter" "$MACOS/Ghostwriter"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

# Add CFBundleExecutable to Info.plist (required for .app)
/usr/libexec/PlistBuddy -c "Delete :CFBundleExecutable" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Ghostwriter" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundlePackageType" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"

# 3. Ad-hoc code sign (required for macOS to show the app in Input Monitoring)
echo "[3/3] Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"
echo "  → Signed: $(codesign -dv "$APP_DIR" 2>&1 | grep 'Signature=' || echo 'ad-hoc')"

echo ""
echo "=== Done ==="
echo "Bundle: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install to /Applications:"
echo "  cp -R $APP_DIR /Applications/"
