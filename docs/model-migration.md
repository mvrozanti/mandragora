# Local LLM Migration Protocol

Local model tags used to be scattered across every consumer, so a
migration (Model A → Model B) meant editing each site or one silently
kept serving the old model. The tags now live in one file keyed by
role:

- [`../nix/snippets/local-llm-models.json`](../nix/snippets/local-llm-models.json)

Deployed (and imported by consumers) at
`/etc/nixos/mandragora/nix/snippets/local-llm-models.json`.

## Source of truth

```json
{
  "agentic": "gpt-oss:20b",
  "vtag": "qwen2.5vl:7b",
  "uncensored": "huihui_ai/qwen2.5-abliterate:14b",
  "gemma": "gemma3:27b",
  "secondary": "qwen3:14b",
  "embeddings": "nomic-embed-text"
}
```

Roles, and who reads each:

- `agentic` — primary agentic model. `mandragora.ai.agentic.model`
  default in `nix/modules/core/ai-local.nix`; crush primary
  (manual, see below).
- `vtag` — VLM. `mandragora.ai.vtag.model` default in
  `nix/modules/core/ai-local.nix`.
- `uncensored` — abliterated chat model. `mandragora.ai.uncensored.model`
  default in `nix/modules/core/ai-local.nix`; backs the MCP
  `ask_uncensored` tool via `.local/bin/local-ai-mcp-server.py`.
- `gemma` — oterm/gemma chat and the MCP `ask_gemma` tool
  (`.local/bin/gemma.py`, `.local/bin/local-ai-mcp-server.py`).
- `secondary` — crush secondary + the watch judge (both manual, see
  below).
- `embeddings` — thought embeddings (external project).

## Wired consumers (edit the JSON, nothing else)

Changing a role key in the JSON flows through automatically:

1. **Declarative pulls** — `nix/modules/core/ai-local.nix` reads the
   JSON with `builtins.fromJSON` for the `agentic`/`vtag`/`uncensored`
   option defaults. `nix/hosts/mandragora-desktop/default.nix` builds
   `mandragora.ai.extraModels` from `gemma`/`secondary`/`embeddings`.
   A pull unit is generated per tag, so every tag in one of these
   sites is fetched on a from-scratch rebuild; a tag reachable by no
   consumer is never pulled.
2. **MCP server** — `.local/bin/local-ai-mcp-server.py` reads the
   `gemma` and `uncensored` keys (env override still wins:
   `MCP_GEMMA_MODEL` / `MCP_UNCENSORED_MODEL`).
3. **gemma (oterm)** — `.local/bin/gemma.py` reads the `gemma` key
   when seeding a fresh oterm store.

Both Python consumers open the deployed JSON path and fall back to the
prior hardcoded tag if the file is unreadable.

## Manual touchpoints (the JSON does not reach these)

Edit the JSON, then also edit these by hand — each is a static tracked
file with no Nix generator, or runs where the JSON is not mounted:

1. **crush** — `.config/crush/crush.json`: `providers.ollama.models`
   list (`gpt-oss:20b` primary, `qwen3:14b` secondary) +
   `models.large`/`models.small` mappings. Static tracked JSON
   symlinked verbatim by home-manager; the crush schema has no
   include mechanism and no module writes it, so it stays a hand-edit.
   Keep it in sync with `agentic` (large/small/primary) and
   `secondary` (secondary provider entry).
2. **watch judge** — `WATCH_OLLAMA_MODEL` default (`qwen3:14b`,
   the `secondary` role) in
   `nix/hosts/mandragora-vps/compose/watch/app/judge.py` and
   `nix/hosts/mandragora-vps/compose/watch/docker-compose.yml`. The
   judge runs in a VPS container where the desktop repo JSON is not
   present; env-overridable but the in-code/compose default is a
   hand-edit.

## External projects (not tracked in this repo)

These live outside `/etc/nixos/mandragora`; migrate them in their own
repos. Listed for completeness:

1. **thought** (`~/Projects/thought`) — `model` in `thought/config.py`
   and the `model:` key in every `configs/*.yaml`; embeddings use the
   `embeddings` tag (`nomic-embed-text`).
2. **Telegram bot** (`~/Projects/llm-via-telegram`) — `OLLAMA_MODEL`
   (and `GEMINI_MODEL`) in `config.py`, overridden at runtime by the
   `llm_via_telegram/env` sops secret. Reads `AGENTS.md` +
   `docs/local-llm.md` for its system prompt, talks to raw ollama
   `:11434`.
3. **vtag** — fetched from GitHub (`nix/pkgs/vtag-cli.nix`); the VLM
   tag it pulls is the `vtag` role via the pre-pull unit, but vtag's
   own default lives upstream.

## Wrap-up

- **open-webui** talks to the context proxy on `:11435`; no model
  pinned, picks from whatever ollama has loaded — nothing to migrate.
- **Documentation** — re-check `AGENTS.md` and `docs/local-llm.md`.
  `local-llm.md` uses generic identity strings to avoid stale model
  references; keep it that way.
- **Persistence** — `mandragora-switch` to rebuild, commit, and push.
  The generated pull unit fetches the new tag on next boot/activation.
