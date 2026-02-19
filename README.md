# Ghostwriter

A macOS background service that silently corrects grammar and suggests text completions as you type — across all apps, with zero UI.

## How It Works

1. **You type** — Ghostwriter captures keystrokes via a listen-only event tap (never blocks input)
2. **You pause for ~1 second** — It reads the focused text field, corrects grammar via LanguageTool, and applies fixes
3. **You pause for 2s on short text** — It suggests a completion, shown as highlighted text
4. **Press Tab** to accept a suggestion, or just keep typing to dismiss it

Everything runs locally. No data leaves your machine.

## Architecture

```
┌─────────────────────────┐     HTTP (localhost:9274)     ┌──────────────────────┐
│   Swift Background Agent │ ◄──────────────────────────► │  Python MLX Server   │
│                          │                               │                      │
│  • CGEventTap (listen)   │                               │  • FastAPI + uvicorn │
│  • AXUIElement read/write│                               │  • LanguageTool (correction) │
│  • Debounce + safety     │                               │  • mlx-lm (elaboration)      │
│  • Tone detection        │                               │  • Post-processing   │
└─────────────────────────┘                               └──────────────────────┘
```

## Features

- **Grammar correction** — deterministic, rule-based correction via [LanguageTool](https://languagetool.org/) (6000+ rules, ~20-100ms)
- **Text completion** — suggests continuations for short text fragments via MLX LLM (ghost text)
- **Tone-aware** — adapts behavior per app:
  | App | Tone | Behavior |
  |-----|------|----------|
  | Slack, Messages, Discord | Casual | Contractions OK, natural |
  | Mail, Outlook | Professional | Polished, no slang |
  | Terminal, Xcode, VS Code | Technical | Skipped (no corrections) |
  | Everything else | Neutral | Standard English |
- **Safe** — skips password fields, rejects rewrites >30% different, prevents correction loops
- **Local** — LanguageTool runs via Java, Llama 3.2 3B (4-bit) runs via Apple MLX — nothing leaves your machine

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon Mac (M1/M2/M3/M4)
- Python 3.9+
- Java 8+ (e.g., `brew install openjdk`) — required by LanguageTool
- ~4 GB RAM for the 3B model + ~300-500 MB for LanguageTool's Java server

## Quick Start

```bash
# Clone
git clone https://github.com/t-rhex/ghostwriter.git
cd ghostwriter

# Build
swift build

# Set up Python venv
python3 -m venv .venv
.venv/bin/pip install -r Server/requirements.txt

# Build the .app bundle (needed for macOS permissions)
bash Scripts/bundle.sh

# Launch (first run downloads the model, ~4 GB)
open .build/Ghostwriter.app
```

On first launch, grant both permissions in **System Settings > Privacy & Security**:
1. **Accessibility** — enable Ghostwriter
2. **Input Monitoring** — enable Ghostwriter

## Install as Background Service

```bash
bash Scripts/install.sh
```

This builds, installs to `/Applications`, sets up the Python venv, validates Java, downloads LanguageTool (~200 MB) and the MLX model (~4 GB), and installs a LaunchAgent.

## Uninstall

```bash
bash Scripts/uninstall.sh
```

## Project Structure

```
ghostwriter/
├── Package.swift                          # Swift package manifest
├── Sources/Ghostwriter/
│   ├── main.swift                         # Entry point, permission polling
│   ├── App/
│   │   ├── GhostwriterApp.swift           # Orchestrator
│   │   ├── Configuration.swift            # Timing, thresholds, model config
│   │   └── Permissions.swift              # Accessibility + Input Monitoring
│   ├── Input/
│   │   ├── KeystrokeMonitor.swift         # CGEventTap (listen-only)
│   │   ├── KeystrokeBuffer.swift          # Character accumulator
│   │   └── TypingDebouncer.swift          # ~1s / 2s pause detection
│   ├── Context/
│   │   ├── AppDetector.swift              # Frontmost app detection
│   │   ├── ToneProfile.swift              # Per-app tone mapping
│   │   └── TextFieldReader.swift          # AX text field reading
│   ├── LLM/
│   │   ├── LLMClient.swift               # HTTP client for MLX server
│   │   ├── PromptBuilder.swift            # Request payloads
│   │   └── LLMResponse.swift             # Response models
│   ├── Output/
│   │   ├── TextReplacer.swift             # AX text replacement (3 strategies)
│   │   ├── GhostTextController.swift      # Ghost text insert/accept/dismiss
│   │   └── UndoManager.swift              # Correction history tracking
│   └── Server/
│       └── MLXServerManager.swift         # Python server lifecycle
├── Server/
│   ├── requirements.txt
│   ├── ghostwriter_server.py              # FastAPI: /v1/correct (LanguageTool), /v1/elaborate (MLX)
│   └── prompts.py                         # Elaboration prompts + few-shot examples
├── Scripts/
│   ├── bundle.sh                          # Build .app bundle
│   ├── install.sh                         # Full install + LaunchAgent
│   └── uninstall.sh
├── Resources/
│   ├── Info.plist
│   └── com.ghostwriter.agent.plist
└── Tests/GhostwriterTests/
    ├── TypingDebouncerTests.swift
    ├── PromptBuilderTests.swift
    └── ToneProfileTests.swift
```

## Configuration

Edit `Sources/Ghostwriter/App/Configuration.swift`:

| Setting | Default | Description |
|---------|---------|-------------|
| `shortPauseInterval` | 1.0s | Pause before correction triggers |
| `longPauseInterval` | 2.0s | Pause before elaboration triggers |
| `maxEditDistanceRatio` | 0.30 | Reject corrections >30% different |
| `maxTextLength` | 2000 | Max chars sent to LLM |

To change the model, edit `MODEL_NAME` in `Server/ghostwriter_server.py`.

## License

MIT
