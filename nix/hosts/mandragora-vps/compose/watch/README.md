# `watch` — perception layer

FastAPI app + background poller that watches external sources (GitHub
users/repos, Reddit users/subs) and emits new items as webhook POSTs.
Served at `https://watch.mvr.ac`, Authelia-gated.

## What it polls

| kind              | endpoint                                                 |
|-------------------|----------------------------------------------------------|
| `github_user`     | `/users/:login/events/public`                            |
| `github_repo`     | `/repos/:owner/:repo/events`                             |
| `reddit_user`     | `/user/:name.json`                                       |
| `reddit_sub`      | `/r/:name/new.json`                                      |
| `youtube_channel` | `https://www.youtube.com/feeds/videos.xml?channel_id=…`  |
| `twitch_stream`   | Helix `/streams?user_login=…` (live transitions only)    |
| `hn_search`       | HN Algolia `search_by_date?query=…&tags=story`           |
| `reddit_search`   | `https://www.reddit.com/search.json?q=…&sort=new`        |
| `rss`             | any RSS 2.0 / Atom feed URL                              |

Twitter intentionally skipped — nitter is unreliable, RSSHub self-host
is the planned route. Add a `twitter_*` kind in `sources.py` when
ready.

## Ack-required notifications

Mark a watcher with `requires_ack=true` (web UI checkbox, or `/addack`
via Telegram, or `PATCH /api/watchers/:id`). Events from such watchers
get re-pushed (Telegram + webhook fanout) every `reminder_interval`
seconds (default 3600) until acknowledged. Three ways to ack:

- click the inline `✓ ack` button on the Telegram message, or send
  `/ack <event_id>` / `/ackall <watcher_id>` in the chat;
- click `ack` on the event in the web UI (or `ack-all` on the watcher);
- open the per-event `ack_url` from the webhook payload (`GET /ack/:id`
  renders a confirmation page).

`requires_ack` and `reminder_interval` can be retoggled at any time
via the web UI, `/ackrequire <id> on|off`, or `/remind <id> <seconds>`.
Reminders piggy-back on the poll loop, so the effective minimum
`reminder_interval` is `WATCH_POLL_INTERVAL` (default 300s).

## AI relevance judge

Setting an `ai_spec` (string describing what counts as a real match)
on a watcher gates every new event through Gemini before any push
happens. Verdicts:

- `GO` — pushed (Telegram badge `🟢 GO`).
- `MAYBE` — pushed with `🟡 MAYBE` and the reason.
- `NO` — stored but never pushed; reminders never fire.
- pending (`ai_verdict IS NULL`) — also not pushed; re-judged next
  poll cycle.

Quota exhaustion (HTTP 429 or "quota"/"rate" in body) raises
`QuotaExceeded`, the judge loop breaks for the cycle, and the
unjudged events stay pending. They are retried next poll — no silent
skip, no push without a verdict. Per-cycle judge cap:
`WATCH_JUDGE_MAX_PER_CYCLE` (default 20).

`.env`:
```
GEMINI_API_KEY=...
WATCH_GEMINI_MODEL=gemini-2.5-flash       # default
WATCH_JUDGE_MAX_PER_CYCLE=20              # default
```

Telegram: `/spec <id> <text>` sets the spec, `/judge <event_id>`
forces re-judge, `/verdicts <id>` tallies. Web UI exposes the same
via the per-watcher `spec` button and the `re-judge` button on each
event row.

## Kindle Paperwhite gen 12 jailbreak watch

Three watchers cover the realistic sources for new Kindle PW12 (fw
≥ 5.9) jailbreaks. All three are good candidates for `requires_ack`
since the signal is rare and high-value:

```
/addack rss      https://www.mobileread.com/forums/external.php?type=RSS2&forumids=150
/addack hn_search     kindle paperwhite jailbreak
/addack reddit_search kindle paperwhite jailbreak 5.9
```

Forum 150 on MobileRead is the Kindle Developer's Corner — historically
where every Kindle JB drops first.

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
