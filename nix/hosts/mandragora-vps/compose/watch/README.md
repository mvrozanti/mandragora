# `watch` — perception layer

FastAPI app + background poller that watches external sources (GitHub
users/repos, Reddit users/subs) and emits new items as webhook POSTs.
Served at `https://watch.mvr.ac`, Authelia-gated.

> **Agent directive — no LLM without asking.** Watchers are plain HTTP
> feed pollers (GitHub/Reddit/RSS/Atom/etc). The only LLM path is the
> opt-in `ai_spec` relevance judge, and the release layer deliberately
> never uses it. Do **not** wire any LLM/model call into a watcher,
> source, or feature (auto-summarizing changelogs, classifying events,
> generating digests, AI-tagging…) without asking the user first. When
> a task looks like it needs a model, stop and ask before spending LLM
> power — default to dumb feed logic.

## What it polls

| kind              | endpoint                                                 |
|-------------------|----------------------------------------------------------|
| `github_user`     | `/users/:login/events/public`                            |
| `github_repo`     | `/repos/:owner/:repo/events`                             |
| `github_release`  | `/repos/:owner/:repo/releases` (full changelog body)     |
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

## Release layer (changelog feed)

The `github_release` kind turns the perception layer into a **release
layer**: a low-noise feed of the changelogs for the software the system
actually uses. Unlike `github_repo` (which streams every push/star/fork
event), it hits the Releases API and emits one item per published
release — title `owner/repo TAG`, the full markdown release body inline
(capped `WATCH_RELEASE_BODY_MAX`, default 12000 chars), link, date.
Drafts are skipped; prereleases are tagged `(prerelease)`.

The curated list lives in `app/release-sources.txt` — one `owner/repo`
per line, `#` comments allowed. On startup `bootstrap_release_sources()`
registers a `github_release` watcher (`push=1`) for each line,
idempotently (matched on `(kind, target)`). Edit the file and restart
to add repos; to drop one, remove its line *and* delete the watcher in
the UI (bootstrap only adds, and re-adds a still-listed repo on the next
restart). Only repos that publish GitHub *Releases* work here — tag-only
projects (nixpkgs, home-manager, sops-nix …) have no Releases output, so
track those with an `rss` watcher pointed at
`https://github.com/OWNER/REPO/tags.atom` instead.

Read it in the web UI under the **releases** tab — release bodies render
as markdown in a collapsible `notes` block. The same items also reach
Telegram, on a **stable-only** policy:

- **Web/dashboard shows everything** the watcher fetched — stable and
  prerelease, including the full backlog.
- **Telegram pushes stable releases only.** Prereleases/nightlies
  (`prerelease: true`) are skipped at push time in `_push_pending` —
  they stay on the dashboard but never ping. No LLM is involved; it is
  a flag check.
- **Backlog never dumps.** On a release watcher's *first* poll
  (`cursor IS NULL`) the fetched events are inserted already-marked-seen
  (`last_reminder_at` set), so adding a repo backfills the dashboard
  silently and only releases published *after* tracking starts ping.

### Feed-only (`push`) flag

Every watcher has a `push` flag (default `1`). When `push=0` its events
are still polled, stored, AI-judged, and visible in the UI, but the
poller skips Telegram/webhook fanout for them entirely. Toggle per
watcher with the `mute`/`unmute` button (or `PATCH /api/watchers/:id`
`{"push": false}`); the add-watcher form has a "push" checkbox. Mute a
single noisy release watcher this way without touching the rest.

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
on a watcher gates every new event through the local LLM (qwen3:14b
on the desktop's RTX 5070 Ti, reached via tailnet) before any push
happens. The judge fetches the event's `link` URL, strips HTML/JSON,
and feeds the body to the model alongside the spec — verdicts are
based on actual link content, not just title/summary.

Verdicts:

- `GO` — pushed (Telegram badge `🟢 GO`). Link content positively
  asserts every explicit spec requirement.
- `MAYBE` — stored but **not pushed by default**. Visible in the web
  UI for manual review. Set `WATCH_PUSH_MAYBE=1` to restore push
  behavior (badge `🟡 MAYBE` + reason).
- `NO` — stored but never pushed; reminders never fire.
- pending (`ai_verdict IS NULL`) — also not pushed; re-judged next
  judge cycle.

The judge prompt treats missing required spec fields (e.g. spec says
"PW12 fw 5.18.x" but the link omits generation or firmware) as `NO`,
not `MAYBE`. A notification the user has to hand-verify is a failed
filter. Write specs with concrete constraints — model number, firmware
range, version, platform — so the judge has something to enforce.

The judge runs as its own asyncio loop, decoupled from the poller, so
slow local-LLM calls never block source polling. `WATCH_JUDGE_INTERVAL`
(default 30s) controls cycle cadence; `WATCH_JUDGE_BATCH` (default 3)
caps events per cycle. Unjudged events queue indefinitely — no rush.

If the desktop ollama is unreachable, the judge logs and retries next
cycle. If link fetch fails (timeout, 4xx, binary content type), the
model falls back to title+summary; per the hard rules above, missing
required fields → `NO`, so unverifiable events stay silent.

`.env` (all optional, defaults in `docker-compose.yml`):
```
WATCH_OLLAMA_URL=http://100.115.80.79:11434    # desktop tailnet
WATCH_OLLAMA_MODEL=qwen3:14b
WATCH_OLLAMA_TIMEOUT=180
WATCH_OLLAMA_NUM_CTX=16384
WATCH_JUDGE_INTERVAL=30
WATCH_JUDGE_BATCH=3
WATCH_LINK_MAX_CHARS=8000
WATCH_LINK_TIMEOUT=20
WATCH_PUSH_MAYBE=0
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

Never `rsync --delete` the top-level `watch/` dir — `.env` and
`data/watch.db` live there, are gitignored (absent from source), and
`--delete` would wipe them. Sync `app/` (pure repo code) and the
compose file separately:

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/watch/app/ \
  opc@mandragora-vps:/home/opc/watch/app/
rsync -av \
  nix/hosts/mandragora-vps/compose/watch/docker-compose.yml \
  opc@mandragora-vps:/home/opc/watch/
ssh opc@mandragora-vps 'cd /home/opc/watch && docker compose up -d --build'
```
