# `fly/` — `fly.mvr.ac` reverse-proxy shim

Label-only stack. Carries the Caddy labels for `fly.mvr.ac` and forwards
TLS-terminated traffic over the tailnet to the slither-io server on
mandragora-desktop (`:8088`), which serves the MaleCNS fly brain panel at
`/simulator.html#brain`.

Generated from [`../proxy-stacks.json`](../proxy-stacks.json) by
[`../generate-proxy-stacks.py`](../generate-proxy-stacks.py) — edit the
manifest and re-run the generator, never this file. Audit check
`11-proxy-stacks` gates the drift.

## Why a shim and not a `hub/` label

`hub/` is the historical anchor for desktop-backed labels, but it is
marked `.no-deploy` (it holds live `config/*.yaml` absent from the repo)
and its remote directory is root-owned, so updating it needs root. A shim
stack lives in its own `opc`-owned slot and deploys with the ordinary
driver:

```
deploy-stacks.sh fly
```

## Two things that must be true for it to serve

1. **The desktop is up and `slither-io.service` is running.** The VPS has
   no GPU; nothing here runs the brain.
2. **The brain daemon is running**, on demand:
   `systemctl --user start fly-brain`. It is deliberately not autostarted —
   it holds ~2.1 GB of VRAM and training peaks at 14.5 GB on a 16 GB card.
   When it is down the panel renders a shaped offline state naming the
   start command, so the page is still useful.

No caddy-side path whitelist is duplicated here: `serve.py` enforces its
own allowlist (`PUBLIC_STATIC_FILES` / `PUBLIC_STATIC_PREFIXES`) and 403s
everything else. Authelia gates the vhost regardless.
