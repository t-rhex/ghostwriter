#!/bin/bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/ghostwriter"
APP_INSTALL_DIR="/Applications"
APP_NAME="Ghostwriter.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ghostwriter.agent.plist"

echo "=== Ghostwriter Uninstaller ==="

# 1. Unload LaunchAgent
echo "[1/3] Unloading LaunchAgent..."
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
    rm "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "  → LaunchAgent removed"
else
    echo "  → LaunchAgent not found (skipped)"
fi

# 2. Remove .app bundle
echo "[2/3] Removing $APP_NAME..."
if [ -d "$APP_INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$APP_INSTALL_DIR/$APP_NAME"
    echo "  → $APP_NAME removed from $APP_INSTALL_DIR"
else
    echo "  → $APP_NAME not found (skipped)"
fi

# 3. Remove server files + virtual environment
echo "[3/3] Removing server files and virtual environment..."
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"
    echo "  → Server files and venv removed"
else
    echo "  → Install directory not found (skipped)"
fi

echo ""
echo "=== Uninstallation Complete ==="
echo "All files removed cleanly (venv included, no global packages to clean up)."
