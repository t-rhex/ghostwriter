#!/bin/bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/ghostwriter"
APP_INSTALL_DIR="/Applications"
APP_NAME="Ghostwriter.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ghostwriter.agent.plist"

echo "=== Ghostwriter Uninstaller ==="

# 1. Kill running processes
echo "[1/5] Stopping running processes..."
pkill -x "Ghostwriter" 2>/dev/null && echo "  → Ghostwriter app killed" || echo "  → Ghostwriter app not running (skipped)"
PYTHON_PID=$(lsof -ti :9274 2>/dev/null || true)
if [ -n "$PYTHON_PID" ]; then
    kill "$PYTHON_PID" 2>/dev/null || true
    echo "  → Python server on port 9274 killed (PID $PYTHON_PID)"
else
    echo "  → Python server not running (skipped)"
fi

# 2. Unload LaunchAgent
echo "[2/5] Unloading LaunchAgent..."
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
    rm "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "  → LaunchAgent removed"
else
    echo "  → LaunchAgent not found (skipped)"
fi

# 3. Remove .app bundle
echo "[3/5] Removing $APP_NAME..."
if [ -d "$APP_INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "${APP_INSTALL_DIR:?}/${APP_NAME:?}"
    echo "  → $APP_NAME removed from $APP_INSTALL_DIR"
else
    echo "  → $APP_NAME not found (skipped)"
fi

# 4. Remove server files + virtual environment
echo "[4/5] Removing server files and virtual environment..."
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"
    echo "  → Server files and venv removed"
else
    echo "  → Install directory not found (skipped)"
fi

# 5. Clean up log files and caches
echo "[5/5] Cleaning up logs and caches..."
for logfile in /tmp/ghostwriter.stdout.log /tmp/ghostwriter.stderr.log; do
    if [ -f "$logfile" ]; then
        rm "$logfile"
        echo "  → Removed $logfile"
    fi
done

HF_CACHE="$HOME/.cache/huggingface/hub/models--mlx-community--Llama-3.2-3B-Instruct-4bit"
LT_CACHE="$HOME/.cache/language_tool_python"
if [ -d "$HF_CACHE" ] || [ -d "$LT_CACHE" ]; then
    echo ""
    echo "Found model/tool caches (these are large but re-downloadable):"
    [ -d "$HF_CACHE" ] && echo "  - $HF_CACHE"
    [ -d "$LT_CACHE" ] && echo "  - $LT_CACHE"
    printf "Delete these caches? [y/N] "
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        [ -d "$HF_CACHE" ] && rm -rf "$HF_CACHE" && echo "  → Removed HuggingFace model cache"
        [ -d "$LT_CACHE" ] && rm -rf "$LT_CACHE" && echo "  → Removed LanguageTool cache"
    else
        echo "  → Caches kept"
    fi
fi

echo ""
echo "=== Uninstallation Complete ==="
echo "All files removed cleanly (venv included, no global packages to clean up)."
