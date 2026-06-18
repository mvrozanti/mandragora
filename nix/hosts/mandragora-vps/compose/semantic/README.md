# semantic.mvr.ac

Public, authelia-gated front door for the LLM analogy + semantic-arithmetic
visualizer (`~/Projects/llm-visualizer`). The app itself runs on
**mandragora-desktop** as `systemd --user` services (frontend `:3001`,
FastAPI backend `:8000`, both bound `0.0.0.0`). This stack is a
reverse-proxy-only container: caddy reaches the desktop over tailscale.

- `/api/*` → `100.115.80.79:8000` (prefix stripped) — the backend.
- everything else → `100.115.80.79:3001` — the static frontend.
- Both behind `forward_auth` (authelia, two_factor). **The backend runs LLM
  inference on the desktop GPU — never expose it unauthenticated.**

The frontend detects a `*.mvr.ac` origin and calls the API at the relative
`/api` path, so the same build serves both the public host and the tailnet
(`mandragora-desktop:3001`, which talks to `:8000` directly).

## Deploy

```bash
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/semantic/ \
  opc@mandragora-vps:/home/opc/semantic/
ssh opc@mandragora-vps 'cd /home/opc/semantic && sudo docker compose up -d'
```

authelia must allow `semantic.mvr.ac` (added to the `two_factor` rule in
`compose/authelia/config/configuration.yml`); reload authelia after changing
its access rules. The desktop must be powered on for the site to work.

## Upstreams (override via `.env` if the desktop's tailscale IP changes)

```
SEMANTIC_WEB_UPSTREAM=100.115.80.79:3001
SEMANTIC_API_UPSTREAM=100.115.80.79:8000
```
