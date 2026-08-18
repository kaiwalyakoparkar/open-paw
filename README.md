# Agent Meow

macOS overlay buddy (pixel orange cat). Wake with a tap or **Control+Option+Space**, talk via Gradium STT, act through Hermes MCP, annotate the screen with **right-click → Explain this**.

## Quick start

**First-time setup:** see **[docs/INSTALL.md](docs/INSTALL.md)** for prerequisites, config, Hermes gateway, permissions, and troubleshooting.

```bash
swift run AgentMeowCheck          # unit checks
swift build --product AgentMeow   # build
swift run AgentMeow               # run
```

Copy `config.example.json` → `~/.config/agent-meow/config.json` and add your API keys before running. Never commit real keys.

## Usage

- **Tap cat** (under ~3pt / ~300ms) or **Control+Option+Space**: toggle wake/sleep
- **Hold Right Option** (default): push-to-talk
- **Drag cat**: reposition
- **Right-click cat → Explain this**: freeze screenshot, draw circle/rect/freehand, speak a prompt
- Idle timeout (default 300s) sleeps and clears `messages[]`

## Docs

- [First-time installation](docs/INSTALL.md)
- [Phase 0 — Hermes API spike](docs/phase0-hermes-spike.md)

## License

TBD
