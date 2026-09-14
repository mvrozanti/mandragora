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
  "meme": "qwen2.5vl:7b",
  "uncensored": "igorls/gemma-4-12B-it-heretic-GGUF:Q4_K_M",
  "gemma": "gemma4:12b",
  "secondary": "qwen3:14b",
  "embeddings": "nomic-embed-text"
}
```

Roles, and who reads each:

- `agentic` — primary agentic model. `mandragora.ai.agentic.model`
  default in `nix/modules/core/ai-local.nix`; crush primary
  (manual, see below).
- `meme` — VLM. `mandragora.ai.meme.model` default in
  `nix/modules/core/ai-local.nix`.
- `uncensored` — decensored chat model (Heretic, not manual
  abliteration: same weights-quality as stock, refusals removed).
  Text-only: the GGUF ships without the multimodal projector, so it
  has none of stock gemma4's vision/audio. Image work belongs on the
  `gemma` or `meme` role. `mandragora.ai.uncensored.model`
  default in `nix/modules/core/ai-local.nix`; backs the MCP
  `ask_uncensored` tool via `.local/bin/local-ai-mcp-server.py`.
- `gemma` — chat.mvr.ac default (`DEFAULT_MODELS`), oterm/gemma chat
  and the MCP `ask_gemma` tool
  (`.local/bin/gemma.py`, `.local/bin/local-ai-mcp-server.py`).
- `secondary` — crush secondary + the watch judge (both manual, see
  below).
- `embeddings` — thought embeddings (external project).

## Wired consumers (edit the JSON, nothing else)

Changing a role key in the JSON flows through automatically:

1. **Declarative pulls** — `nix/modules/core/ai-local.nix` reads the
   JSON with `builtins.fromJSON` for the `agentic`/`meme`/`uncensored`
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
3. **meme** — fetched from GitHub (`nix/pkgs/meme-cli.nix`); the VLM
   tag it pulls is the `meme` role via the pre-pull unit, but the
   upstream default lives in the vtag repo.

## Wrap-up

- **open-webui** talks to the context proxy on `:11435` and pins the
  `gemma` role as its default via `DEFAULT_MODELS` in
  `nix/modules/services/open-webui.nix`. That key is an open-webui
  *PersistentConfig* variable, so the value in its database wins over
  the environment once the instance has booted; the module therefore
  also sets `ENABLE_PERSISTENT_CONFIG = "False"` so the Nix value is
  authoritative on every start. Admin-panel edits will not survive a
  restart — that is the intended trade for declarative supremacy.
- **Documentation** — re-check `AGENTS.md` and `docs/local-llm.md`.
  `local-llm.md` uses generic identity strings to avoid stale model
  references; keep it that way.
- **Persistence** — `mandragora-switch` to rebuild, commit, and push.
  The generated pull unit fetches the new tag on next boot/activation.
