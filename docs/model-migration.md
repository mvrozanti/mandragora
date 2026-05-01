# Local LLM Migration Protocol

Migrating to a new local model (Model A → Model B) requires updating
every reference site or one of them silently keeps serving the old
model. Run all six steps.

1. **Ollama** — `ollama pull <model>`.
2. **Projects/thought** — `RunConfig` in `thought/config.py` (default
   model) and any existing `config.yaml` files.
3. **Telegram bot** — `OLLAMA_MODEL` in
   `/etc/nixos/mandragora/.local/share/llm-via-telegram/config.py`
   (default) and any associated secrets/env files.
4. **Crush** — `/etc/nixos/mandragora/.config/crush/crush.json`
   (provider models + default mappings).
5. **Documentation** — re-check `AGENTS.md` and `local-llm.md`.
   `local-llm.md` should use generic identity strings to avoid stale
   references.
6. **Persistence** — `mandragora-switch` to commit and sync the live
   environment.
