# First-time installation

Open Paw is a macOS menu-bar companion: pixel cat overlay, Gradium voice I/O, Hermes Agent for reasoning and MCP tools, screen annotation via right-click.

## Requirements

| Requirement | Version / notes |
|---|---|
| macOS | 14.2 (Sonoma) or later |
| Xcode | 15+ (Swift 5.9+) |
| [Hermes Agent](https://hermes-agent.nousresearch.com/) | With API server enabled |
| LLM proxy | OpenRouter-compatible endpoint (Hermes default: `http://localhost:8082/openrouter/`) |
| Gradium | API key from [gradium.ai](https://gradium.ai/) |

## 1. Clone and build

```bash
git clone <your-remote-url> open-paw
cd open-paw

# Run unit checks (no network, no API keys required)
swift run OpenPawCheck

# Build the app
swift build --product OpenPaw
```

**Xcode:** open `Package.swift` (File → Open). The bundled `OpenPaw.xcodeproj` is a thin wrapper around the same Swift package.

## 2. Create local config (secrets stay out of git)

Open Paw reads **`~/.config/open-paw/config.json`**. The repo ships only `config.example.json` — copy it locally:

```bash
mkdir -p ~/.config/open-paw
cp config.example.json ~/.config/open-paw/config.json
chmod 0600 ~/.config/open-paw/config.json
```

Edit `~/.config/open-paw/config.json`:

| Field | Required | Description |
|---|---|---|
| `gradium.api_key` | Yes | Gradium API key |
| `hermes.api_key` | Yes | Must match Hermes `API_SERVER_KEY` |
| `hermes.base_url` | No | Default `http://127.0.0.1:8642/v1` |
| `hermes.model` | No | Default `hermes-agent` |
| `hotkey.hold` | No | Default: hold **Right Option** to talk |
| `hotkey.toggle` | No | Default: **Control+Option+Space** wake/sleep |
| `ui.idle_timeout_seconds` | No | Auto-sleep after idle (default 300) |

**Environment fallback:** empty `api_key` fields fall back to `GRADIUM_API_KEY` and `HERMES_API_KEY`. This works when launching from a terminal; Finder / Dock launches do **not** inherit shell env.

```bash
export GRADIUM_API_KEY="your-gradium-key"
export HERMES_API_KEY="your-hermes-server-key"
swift run OpenPaw
```

> **Security:** never commit `config.json`, `.env`, or real API keys. The repo `.gitignore` blocks common secret paths.

## 3. Set up Hermes Agent

Hermes MCP servers and provider routing live in **`~/.hermes/config.yaml`** (separate from Open Paw config).

Enable the OpenAI-compatible API server. In `~/.hermes/.env` (or your Hermes env):

```bash
API_SERVER_ENABLED=true
API_SERVER_KEY=<same value as hermes.api_key in config.json>
```

Start the gateway:

```bash
hermes gateway
```

Or use the launchd service if you installed Hermes that way (`ai.hermes.gateway`).

Verify the API is reachable:

```bash
curl -s http://127.0.0.1:8642/v1/models \
  -H "Authorization: Bearer $HERMES_API_KEY" | jq .
```

If connection fails, see [phase0-hermes-spike.md](phase0-hermes-spike.md) for the full curl checklist.

## 4. macOS permissions

On first run, grant:

- **Microphone** — Gradium STT while you hold the talk hotkey
- **Screen Recording** — screenshot capture for "Explain this"
- **Documents** (optional) — local Obsidian vault lookup when Hermes cannot access Documents

The app runs as a menu-bar accessory (`LSUIElement`); look for the 🐱 icon in the status bar.

## 5. Run

```bash
swift run OpenPaw
```

Or run the built binary:

```bash
.build/debug/OpenPaw
```

## Usage quick reference

| Action | Result |
|---|---|
| Tap cat (short click) or **Control+Option+Space** | Wake / sleep |
| Hold **Right Option** (default) | Push-to-talk via Gradium STT |
| Drag cat | Reposition overlay |
| Right-click cat → **Explain this** | Freeze screen, draw annotation, speak a prompt |
| Menu bar 🐱 → Cancel session | Stop current Hermes stream |
| Idle timeout | Sleep and clear conversation history |

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Add gradium.api_key…" bubble | Set key in `~/.config/open-paw/config.json` or `GRADIUM_API_KEY` |
| "Invalid API key" from Hermes | Match `hermes.api_key` ↔ `API_SERVER_KEY`; restart gateway |
| Connection refused on `:8642` | Start Hermes with `API_SERVER_ENABLED=true` |
| No speech detected | Check mic permission; adjust `gradium.stt.vad_threshold` |
| App silent from Finder | Use config file keys instead of shell env vars |

## Project layout

```
open-paw/
├── OpenPaw/          # macOS app (UI, voice, vision, hotkeys)
├── OpenPawCore/      # Shared library (config, Hermes client, prompts)
├── OpenPawTests/     # OpenPawCheck executable tests
├── config.example.json # Template — copy to ~/.config/open-paw/
├── Package.swift
└── docs/
```
