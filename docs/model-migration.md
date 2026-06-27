# Local LLM Migration Protocol

Migrating a local model (Model A → Model B) requires updating every
reference site or one of them silently keeps serving the old model.
Most sites hardcode their own tag, so there is no single switch.

## Declarative pulls (source of truth for what exists on disk)

`nix/modules/core/ai-local.nix` owns every model that is pulled
declaratively. Add/replace the tag here, never via a bare
`ollama pull` (that is imperative and lost on a fresh install):

- `mandragora.ai.agentic.model` — primary agentic model
  (default `gpt-oss:20b`).
- `mandragora.ai.vtag.model` — VLM (default `qwen2.5vl:7b`).
- `mandragora.ai.uncensored.model` — abliterated chat model
  (default `huihui_ai/qwen2.5-abliterate:14b`); backs the MCP
  `ask_uncensored` tool.
- `mandragora.ai.extraModels` — list set in
  `nix/hosts/mandragora-desktop/default.nix`; covers consumers that
  hardcode their own tag (`gemma3:27b`, `qwen3:14b`,
  `nomic-embed-text`).

A pull unit is generated per tag, so any new model MUST be added to
one of the above or it will not exist after a from-scratch rebuild.

## Consumer reference sites

1. **thought** — `model` in `~/Projects/thought/thought/config.py` and
   the `model:` key in every `~/Projects/thought/configs/*.yaml`;
   embeddings use `nomic-embed-text`.
2. **Telegram bot** — `OLLAMA_MODEL` (and `GEMINI_MODEL`) in
   `~/Projects/llm-via-telegram/config.py`, overridable via the
   `llm_via_telegram/env` sops secret. Reads `AGENTS.md` +
   `docs/local-llm.md` for its system prompt, talks to raw ollama
   `:11434`.
3. **crush** — `.config/crush/crush.json`: `providers.ollama.models`
   list + `models.large`/`models.small` mappings.
4. **MCP server** — `.local/bin/local-ai-mcp-server.py`: `GEMMA_MODEL`
   / `UNCENSORED_MODEL` defaults (env-overridable via
   `MCP_GEMMA_MODEL` / `MCP_UNCENSORED_MODEL`).
5. **gemma (oterm)** — `.local/bin/gemma.py` hardcodes its tag.
6. **open-webui** — talks to the context proxy on `:11435`; no model
   pinned, picks from whatever ollama has loaded.

## Wrap-up

7. **Documentation** — re-check `AGENTS.md` and `docs/local-llm.md`.
   `local-llm.md` uses generic identity strings to avoid stale model
   references; keep it that way.
8. **Persistence** — `mandragora-switch` to rebuild, commit, and push.
   The generated pull unit fetches the new tag on next boot/activation.
