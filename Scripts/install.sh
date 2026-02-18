#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/usr/local/share/ghostwriter"
APP_INSTALL_DIR="/Applications"
APP_NAME="Ghostwriter.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ghostwriter.agent.plist"
VENV_DIR="$INSTALL_DIR/.venv"
MODEL_NAME="mlx-community/Llama-3.2-3B-Instruct-4bit"

echo "=== Ghostwriter Installer ==="
echo ""

# 1. Build and bundle the .app
echo "[1/6] Building Ghostwriter.app..."
cd "$PROJECT_DIR"
bash Scripts/bundle.sh

# 2. Install the .app bundle
echo "[2/6] Installing $APP_NAME to $APP_INSTALL_DIR..."
if [ -d "$APP_INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$APP_INSTALL_DIR/$APP_NAME"
fi
cp -R ".build/$APP_NAME" "$APP_INSTALL_DIR/$APP_NAME"
echo "  → Installed to $APP_INSTALL_DIR/$APP_NAME"

# 3. Install server files
echo "[3/6] Installing server files..."
sudo mkdir -p "$INSTALL_DIR/Server"
sudo cp Server/ghostwriter_server.py "$INSTALL_DIR/Server/"
sudo cp Server/prompts.py "$INSTALL_DIR/Server/"
sudo cp Server/requirements.txt "$INSTALL_DIR/Server/"
echo "  → Installed to $INSTALL_DIR/Server/"

# 4. Create virtual environment and install Python dependencies
echo "[4/6] Setting up Python virtual environment..."
sudo python3 -m venv "$VENV_DIR"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r Server/requirements.txt
echo "  → Virtual environment created at $VENV_DIR"
echo "  → Python dependencies installed"

# 5. Pre-download the MLX model
echo "[5/6] Downloading MLX model ($MODEL_NAME)..."
echo "  This may take a few minutes on first install (~2-4 GB)."
sudo "$VENV_DIR/bin/python3" -c "
from mlx_lm import load
print('Downloading and caching model...')
load('$MODEL_NAME')
print('Model cached successfully.')
"
echo "  → Model downloaded and cached"

# 6. Install LaunchAgent
echo "[6/6] Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "Resources/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
echo "  → LaunchAgent plist installed"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "  1. Open the app once to trigger permission prompts:"
echo "     open /Applications/$APP_NAME"
echo ""
echo "  2. Grant permissions in System Settings > Privacy & Security:"
echo "     • Accessibility → enable Ghostwriter"
echo "     • Input Monitoring → enable Ghostwriter"
echo ""
echo "  3. Start the background service:"
echo "     launchctl load ~/Library/LaunchAgents/$PLIST_NAME"
echo ""
echo "Logs: /tmp/ghostwriter.stdout.log and /tmp/ghostwriter.stderr.log"
echo "Uninstall: $SCRIPT_DIR/uninstall.sh"
