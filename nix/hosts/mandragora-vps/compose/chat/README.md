# chat.mvr.ac

Open WebUI, Authelia-gated, talking to the desktop's Ollama over the
tailnet through the context proxy on `:11435`, which injects `AGENTS.md`
as the default system prompt exactly as the old desktop service did.

Moved here from `services.open-webui` on the desktop on 2026-10-18: the
nixpkgs package was the single largest item in the desktop's system
evaluation (about 1,500 python derivations, 5.9 GiB) for a UI that
served no human requests in the preceding 30 days. Chat state starts
fresh under `data/`; the old desktop database stays at
`/persistent/var/lib/private/open-webui` until someone removes it.

`DEFAULT_MODELS` is the `gemma` role from
`nix/snippets/local-llm-models.json`; change both when the model moves.
