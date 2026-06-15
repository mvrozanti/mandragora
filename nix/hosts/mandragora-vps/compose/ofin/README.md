# ofin · brazilian personal finance dashboard

Pluggy-backed dashboard for m's bank/card/investment data. Serves at
https://ofin.mvr.ac (Authelia two-factor gated via the `forward_auth`
Caddy labels in `docker-compose.yml`; `/webhook/*` is left open so Pluggy
can POST events). The app has no server-side auth of its own — gating is
entirely the proxy's job.

## Source

`~/Projects/ofin/` — FastAPI + Postgres + Pluggy REST client. Built on
the VPS itself by `deploy.sh` (no docker needed on the desktop).

## Pluggy credentials

- `client_id` is hard-coded into `deploy.sh` (treat as moderately
  sensitive; widget never sees it, only the server-side `/auth` exchange
  does). Override per-run with `PLUGGY_CLIENT_ID=...`.
- `client_secret` lives in sops at `pluggy.client_secret`
  (`nix/modules/core/secrets.nix` declares it as
  `sops.secrets."pluggy/client_secret"`, owner=m, 0400). sops-nix mounts
  it at `/run/secrets/pluggy/client_secret` on activation; `deploy.sh`
  reads that file directly (no sops CLI, no age key handling). If the
  file isn't there, run a desktop rebuild first.
- `webhook_secret` is optional. Set `PLUGGY_WEBHOOK_SECRET=...` in the
  deploy env; if empty, the receiver skips HMAC verification.

## Deploy

```bash
cd /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/ofin
./deploy.sh
```

What it does:

1. Decrypts `pluggy/client_secret` via sops (reads
   `/persistent/secrets/keys.txt`; falls back to `sudo cat` if not
   readable by user m).
2. `rsync`s `~/Projects/ofin/` into `/home/opc/ofin/src/`.
3. Writes `/home/opc/ofin/.env` (mode 0600) with both Pluggy keys, a
   freshly-generated `OFIN_DB_PASSWORD` (rotates only if the file is
   deleted), and `MVR_AC`.
4. `docker build -t ofin:latest` on the VPS.
5. `docker compose up -d`.

## Webhook

Pluggy → `https://ofin.mvr.ac/webhook/pluggy`. The backend sets
`webhookUrl` per connect-token, so it's wired automatically the first
time a bank is linked. Verify:

```bash
curl -s https://ofin.mvr.ac/webhook/pluggy -d '{"event":"item/updated","itemId":"..."}'
#   → 200 if PLUGGY_WEBHOOK_SECRET unset
#   → 401 if PLUGGY_WEBHOOK_SECRET set and X-Signature missing/wrong
```

## Schedule

APScheduler runs full resync every 12h. Webhook events trigger per-item
resync immediately. Manual sync via `POST /api/items/{id}/sync` or the
`sync` button on `/items`.

## Volumes

- `/home/opc/ofin/db` → Postgres data, persistent. Routine VPS backup
  covers it.

## Auth — two parts, both required

Gating needs BOTH, or the host is wide open:
1. **Caddy `forward_auth` labels** in `docker-compose.yml` — these make
   Caddy actually route requests through Authelia. `0_handle @webhook`
   bypasses `/webhook/*` (Pluggy); `1_handle` forward_auths everything
   else. **Without these labels Caddy proxies straight to the app and
   the Authelia rules below never run.**
2. `compose/authelia/config/configuration.yml` — `bypass` on
   `^/webhook/.*$` *before* the `two_factor` rule for the rest of the host.

The app has no auth of its own (`OFIN_AUTHED` is a client-side display
flag only), so the proxy is the sole gate. Incident 2026-06-14: the
forward_auth labels were missing → `/api/*` served bank data unauth to
the public internet. Fixed by adding them (mirrors the `fin` stack).

## Hub tile

Per AGENTS.md §16 a matching tile in `compose/hub/static/index.html`
ships in the same branch.

## Disable / rollback

```bash
ssh opc@mandragora-vps "cd /home/opc/ofin && docker compose down"
```

DB volume kept; `docker compose up -d` resumes. To wipe state:
`rm -rf /home/opc/ofin/{db,.env}`.
