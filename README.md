# Open Paw 🐱: Your buddy, on your Mac, at your cursor

<p align="center">
  <img src="docs/assets/open-paw-logo.png" alt="Open Paw, a pixel orange cat overlay assistant for macOS" width="128">
</p>

<p align="center">
  <a href="https://github.com/kaiwalyakoparkar/open-paw"><img src="https://img.shields.io/badge/platform-macOS%2014.2+-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.2+"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/swift-5.9+-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License: MIT"></a>
</p>

Open Paw is a macOS menu-bar companion: a pixel orange cat overlay that wakes on your hotkey, listens through Gradium STT, reasons through a selectable agent harness (Hermes, Claude Code, or Codex), and annotates your screen when you ask it to explain what you see.

[First-time installation](docs/INSTALL.md) · [Run with Claude or Codex](#run-with-claude-or-codex) · [Hermes API spike](docs/phase0-hermes-spike.md) · [Inspired by OpenClaw](https://github.com/openclaw/openclaw)

## Install

Open Paw targets macOS 14.2 (Sonoma) or later. You need Xcode 15+ (Swift 5.9+), a [Gradium](https://gradium.ai/) API key, and one agent harness: [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude` on PATH), Codex CLI (`codex` on PATH), or a running [Hermes Agent](https://hermes-agent.nousresearch.com/) gateway.

```bash
git clone https://github.com/kaiwalyakoparkar/open-paw.git
cd open-paw
swift run OpenPawCheck   # unit checks (no network, no keys)
swift build --product OpenPaw
```

Copy `config.example.json` → `~/.config/open-paw/config.json` and add `gradium.api_key`. See the [installation guide](docs/INSTALL.md) for harness setup, macOS permissions, and troubleshooting.

## Run with Claude or Codex

Already use Claude Code or Codex CLI? Start here. No Hermes gateway. No `hermes.api_key`. `--claude` / `--codex` override `harness` for **that process only**.

### Claude Code (`--claude`)

Install [`claude`](https://docs.anthropic.com/en/docs/claude-code) so it is on PATH (or set `claude.bin`). MCP stays in `~/.claude.json`.

```bash
mkdir -p ~/.config/open-paw
cp config.example.json ~/.config/open-paw/config.json
chmod 0600 ~/.config/open-paw/config.json
# edit config: add gradium.api_key only

swift run OpenPaw --claude
```

To make Claude the default, set `"harness": "claude"` in config and run `swift run OpenPaw` with no flag.

### Codex CLI (`--codex`)

Install `codex` so it is on PATH (or set `codex.bin`). MCP stays in `~/.codex/config.toml`.

```bash
mkdir -p ~/.config/open-paw
cp config.example.json ~/.config/open-paw/config.json
chmod 0600 ~/.config/open-paw/config.json
# edit config: add gradium.api_key only

swift run OpenPaw --codex
```

To make Codex the default, set `"harness": "codex"` in config and run `swift run OpenPaw` with no flag.

On first launch, grant **Microphone** and **Screen Recording** when macOS prompts. Look for the 🐱 icon in the menu bar.

Then:

- **Tap the cat** or press **Control+Option+Space** to wake / sleep
- **Hold Right Option** (default) for push-to-talk
- **Right-click the cat → Explain this** to freeze the screen, draw a circle or rectangle, and speak a prompt

Idle timeout (default 300s) sleeps the buddy and clears conversation history.

## Quick start (Hermes)

Hermes needs a running gateway plus `hermes.api_key`. After config is ready:

```bash
mkdir -p ~/.config/open-paw
cp config.example.json ~/.config/open-paw/config.json
chmod 0600 ~/.config/open-paw/config.json
# edit ~/.config/open-paw/config.json (gradium.api_key + hermes.api_key)

swift run OpenPaw
```

## How it fits together

- The **overlay buddy** is a floating pixel cat (`BuddyWindow`) you can drag anywhere on screen.
- **Gradium** handles speech-to-text while you hold the talk hotkey and text-to-speech for replies.
- **[Hermes Agent](https://hermes-agent.nousresearch.com/)**, **Claude Code**, or **Codex CLI** is the agent harness (set `harness` in config or pass `--claude` / `--codex` / `--hermes`). MCP stays in that tool's own config.
- **Screen annotation** captures a screenshot, lets you mark a region, and sends the annotated image plus your voice prompt to the selected harness.
- **Hotkeys** (`GlobalHotkey`, `HoldToTalkMonitor`) map wake/toggle and push-to-talk without leaving your current app.

Open Paw reads config from `~/.config/open-paw/config.json`. MCP servers live with the harness: `~/.hermes/config.yaml`, `~/.claude.json`, or `~/.codex/config.toml`. Process flags `--claude` / `--codex` / `--hermes` override `harness` for that run only.

## Security

Treat voice prompts and annotated screenshots as sensitive input. API keys belong in `~/.config/open-paw/config.json` (mode `0600`) or shell env vars. Never commit them to the repo.

Hermes, Claude Code, and Codex tools run on the host through *their* configs. Review permissions and MCP server scope before connecting production accounts or filesystem access. Voice plus `bypassPermissions` is a loaded gun.

## Documentation

| Goal | Start here |
| --- | --- |
| Run with Claude Code (`--claude`) or Codex (`--codex`) | [Run with Claude or Codex](#run-with-claude-or-codex) |
| First-time setup, permissions, troubleshooting | [docs/INSTALL.md](docs/INSTALL.md) |
| Hermes API connectivity checklist | [docs/phase0-hermes-spike.md](docs/phase0-hermes-spike.md) |
| Local config template | [config.example.json](config.example.json) |
| Hotkeys and UI defaults | `hotkey.*` and `ui.*` in config |

## Development

The repository is a Swift Package with an optional Xcode wrapper.

```bash
git clone https://github.com/kaiwalyakoparkar/open-paw.git
cd open-paw
swift run OpenPawCheck          # all unit checks
swift build --product OpenPaw   # build the app
swift run OpenPaw               # run from terminal
```

Open `Package.swift` in Xcode (File → Open). The bundled `OpenPaw.xcodeproj` wraps the same package.

```
open-paw/
├── OpenPaw/          # macOS app (UI, voice, vision, hotkeys)
├── OpenPawCore/      # Shared library (config, agent harness, prompts)
├── OpenPawTests/     # OpenPawCheck executable tests
├── config.example.json
├── Package.swift
└── docs/
```

## License

MIT. See [LICENSE](LICENSE).
