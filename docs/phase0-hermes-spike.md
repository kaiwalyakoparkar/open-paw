# Phase 0 — Hermes API spike

Date: 2026-08-16  
Hermes Agent: v0.18.2 (`~/.local/bin/hermes`)  
Gateway: launchd `ai.hermes.gateway` (PID 2690) running.

## Results

| Assumption | Verified? | Actual |
|---|---|---|
| Base URL `:8642/v1` | **No** | Port 8642 not listening. `curl http://127.0.0.1:8642/v1/models` → connection failed (HTTP 000) |
| `GET /v1/health` | **No** | Same — nothing bound on 8642 |
| SSE streaming shape | **Unverified** | Blocked on API server |
| `image_url` multimodal passthrough | **Unverified** | Phase 3 ships multimodal request + text-only fallback |
| Provider routes to `:8082/openrouter` | **Unverified** | Port 8082 has a listener (`us-cli`); Hermes API not reachable to prove routing |
| MCP tool executes via gateway | **Unverified** | Blocked on API server |
| Tool events visible in SSE stream? | **Unverified** | Client parses OpenAI-style `delta.tool_calls` **if** they appear; otherwise interrupted suffix only |

## Implication for later phases

- Default `hermes.base_url` stays `http://127.0.0.1:8642/v1` as planned.
- Enable `API_SERVER_ENABLED=true` and `API_SERVER_KEY` in Hermes env, then re-run the curl checklist.
- Phase 2 client: long SSE timeout, client `messages[]`, parse `tool_calls` deltas when present.
- Phase 3: send `image_url` parts; if the model/proxy rejects them, still send the spoken prompt as text.
