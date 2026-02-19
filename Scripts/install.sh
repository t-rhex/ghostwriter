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

# 1. Validate Java is available (required by LanguageTool)
echo "[1/8] Checking Java installation..."
if ! command -v java &>/dev/null; then
    echo ""
    echo "ERROR: Java is required but not found."
    echo ""
    echo "LanguageTool needs Java 8+ to run. Install it with one of:"
    echo "  brew install openjdk"
    echo "  # or download from https://adoptium.net"
    echo ""
    echo "After installing, re-run this script."
    exit 1
fi
JAVA_VERSION=$(java -version 2>&1 | head -1)
echo "  → Found Java: $JAVA_VERSION"

# 2. Build and bundle the .app
echo "[2/8] Building Ghostwriter.app..."
cd "$PROJECT_DIR"
bash Scripts/bundle.sh

# 3. Install the .app bundle
echo "[3/8] Installing $APP_NAME to $APP_INSTALL_DIR..."
if [ -d "$APP_INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "${APP_INSTALL_DIR:?}/${APP_NAME:?}"
fi
cp -R ".build/$APP_NAME" "$APP_INSTALL_DIR/$APP_NAME"
echo "  → Installed to $APP_INSTALL_DIR/$APP_NAME"

# 4. Install server files
echo "[4/8] Installing server files..."
sudo mkdir -p "$INSTALL_DIR/Server"
sudo chown -R "$(whoami)" "$INSTALL_DIR"
cp Server/ghostwriter_server.py "$INSTALL_DIR/Server/"
cp Server/prompts.py "$INSTALL_DIR/Server/"
cp Server/requirements.txt "$INSTALL_DIR/Server/"
echo "  → Installed to $INSTALL_DIR/Server/"

# 5. Create virtual environment and install Python dependencies
echo "[5/8] Setting up Python virtual environment..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r Server/requirements.txt
echo "  → Virtual environment created at $VENV_DIR"
echo "  → Python dependencies installed"

# 6. Pre-download LanguageTool server (~200MB)
echo "[6/8] Pre-downloading LanguageTool server..."
echo "  This may take a minute on first install (~200 MB)."
"$VENV_DIR/bin/python3" -c "
import language_tool_python
print('Downloading LanguageTool server...')
tool = language_tool_python.LanguageTool('en-US')
print('LanguageTool downloaded and ready.')
tool.close()
"
echo "  → LanguageTool downloaded and cached"

# 7. Pre-download the MLX model
echo "[7/8] Downloading MLX model ($MODEL_NAME)..."
echo "  This may take a few minutes on first install (~2-4 GB)."
"$VENV_DIR/bin/python3" -c "
from mlx_lm import load
print('Downloading and caching model...')
load('$MODEL_NAME')
print('Model cached successfully.')
"
echo "  → Model downloaded and cached"

# 8. Install LaunchAgent
echo "[8/8] Installing LaunchAgent..."
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
