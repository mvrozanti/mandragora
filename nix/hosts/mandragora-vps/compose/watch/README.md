# `watch` — perception layer

FastAPI app + background poller that watches external sources (GitHub
users/repos, Reddit users/subs) and emits new items as webhook POSTs.
Served at `https://watch.mvr.ac`, Authelia-gated.

## What it polls (v1)

| kind            | endpoint                                  |
|-----------------|-------------------------------------------|
| `github_user`   | `/users/:login/events/public`             |
| `github_repo`   | `/repos/:owner/:repo/events`              |
| `reddit_user`   | `/user/:name.json`                        |
| `reddit_sub`    | `/r/:name/new.json`                       |

Twitter intentionally skipped in v1 — nitter is unreliable, RSSHub
self-host is the planned route. Add a `twitter_*` kind in `sources.py`
when ready.

## Fan-out

Every new event is POSTed as JSON to `WATCH_WEBHOOK_URL` (typically a
slug on the sibling `webhook` stack). Payload shape:

```json
{
  "source": "mandragora-watch",
  "kind": "github_user",
  "target": "octocat",
  "name": "octocat",
  "external_id": "12345",
  "title": "octocat PushEvent octocat/hello-world",
  "summary": "first commit message | second",
  "link": "https://github.com/octocat/hello-world",
  "occurred_at": "2026-05-19T12:34:56Z"
}
```

This reuses the existing desktop notifier on `webhook.mvr.ac` —
no second pipeline.

## Layout on VPS

```
/home/opc/watch/
├── docker-compose.yml         ← repo copy
├── app/                       ← repo copy (Dockerfile, *.py, static/)
├── .env                       ← root-owned, NOT in repo
└── data/                      ← SQLite (watch.db)
```

## `.env`

```
MVR_AC=mvr.ac
WATCH_POLL_INTERVAL=300
WATCH_MAX_EVENTS_PER_WATCHER=500
WATCH_WEBHOOK_URL=https://webhook.mvr.ac/h/<slug>
GITHUB_PAT=ghp_xxx
TELEGRAM_BOT_TOKEN=123456:abc
TELEGRAM_CHAT_ID=12345678
```

`TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` are optional. When both are
set, the bot pushes every new event to the chat and accepts commands:
`/list`, `/add <kind> <target>`, `/del <id>`, `/pause <id>`,
`/resume <id>`, `/poll <id>`, `/recent [n]`. `TELEGRAM_CHAT_ID`
accepts a single id or a comma/space-separated list; only those ids
are allowed to issue commands.

`GITHUB_PAT` is optional. Without it the GitHub API allows 60
requests/hour per source IP; with a PAT 5 000 req/hour.

The desktop-side sops entry `github/personal_access_token` (added
in `nix/modules/core/secrets.nix`) is the canonical store of the
token value; copy it into `/home/opc/watch/.env` when provisioning.

## Bring-up

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/watch/ \
  opc@mandragora-vps:/home/opc/watch/
ssh opc@mandragora-vps 'cd /home/opc/watch && docker compose up -d --build'
```
