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


## The model: a watch is a standing question

Each watcher is a question you are waiting on, and it is in exactly one state:

| state | meaning |
|---|---|
| **waiting** | nothing has fired yet |
| **triggered** | something fired and you have not accepted it |
| **done** | everything that fired has been accepted, in the web UI or from the Telegram link |

A *trigger* is an event that reached you: a `GO` verdict, or — for a watcher with no
`ai_spec` — any event, since everything that source emits passes by definition. The
SQL predicate is `TRIGGER_PREDICATE` in `main.py`; `/api/watchers` carries
`state`, `trigger_count` and `open_trigger_count`, and
`/api/watchers/{id}/triggers` returns only what fired.

Rejected events are never shown in the UI. They still exist, and the funnel is still
in `/healthz` for diagnosis, but the page is the watches and their properties — not
a log.

**Ack is now nagging, and nagging is opt-in.** `requires_ack` means "re-notify me
hourly until I accept this" and is reserved for urgent security watches — as of the
2026-09-08 rework, watchers 28 and 30 (`electrum-sec`) and nothing else. Acceptance
itself (`acked_at`) is universal and is what moves a watch to *done*. That rework set
`requires_ack = 0` on 28 watchers, accepted 950 outstanding events, and cleared 3
stale verdicts left on a watcher whose spec had been removed.

## The judge may not assert a subject the source never named

A 14b model told us, in its own words, that *"Major bitcoin wallet flaw drains 594
BTC in 25-minute sweep"* was a headline asserting an **Electrum** security flaw. It
was not; Electrum appears nowhere in it. Three of seven lifetime GO verdicts were
this exact failure — a confident reason naming a product the text never mentions,
because the spec had primed the model to look for it.

The system prompt already said "do not infer" and "never invent facts not present in
the provided text". Instructing a small model not to hallucinate is not a control.
So, as with corroboration matching, the check is **deterministic set logic**:

- `judge.ground_verdict` runs after every judgement. Anything that is not already NO
  is checked against the event's title, summary and fetched body.
- If the watcher sets **`must_mention`**, those literals are authoritative: absent
  from the text means NO, whatever the model said. This is the precise dial —
  watchers 28 and 30 carry `electrum`.
- With no `must_mention`, the fallback is the model's own extracted `subject`: every
  distinctive term in it must appear in the text. Generic words
  (`SUBJECT_STOPWORDS`) do not count.
- A refused verdict says exactly why: *"subject is not named in the source: electrum
  absent from the title, summary and fetched text"*.

Re-judging the seven historical GOs under this rule left **two**, both of which name
Electrum in the headline. The gate refused two outright; the model itself withdrew
two more on a second look.

`must_mention` only applies to watchers that have an `ai_spec`, because only those
reach the judge. A watcher with no spec forwards everything its source emits by
design — for those, the source is the filter.

## Backing off

Sources are polled every `WATCH_POLL_INTERVAL` (300s) **only while healthy**. On
failure the watcher gets `fail_count += 1` and a persisted `retry_after`:
`min(300 · 2^(fails-1), 6h)` plus ~10% jitter, and the poller's own query skips it
until then. A `403` or `429` raises `sources.RateLimited`, which carries the server's
`Retry-After` when it sends one, and the backoff takes whichever wait is longer.
Success resets both columns.

This exists because four `reddit_search` watchers were retried every five minutes for
weeks against a `403`, which is less "the source blocked us" than "we asked to be
blocked". The cooldown is shown on the tile ("retrying in 42m") because a silently
skipped source looks exactly like a working one. See the vault note
`decisions/pollers must back off.md`.


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

- `GO` — pushed (Telegram badge `🟢 GO`). Content positively asserts
  every explicit spec requirement and states it as established fact.
- `UNCLEAR` — every spec requirement is evidenced but the assertion
  itself is weak (unverified single report, rumor with no source,
  preview with nothing shipped). Not pushed on its own; held for
  corroboration, below.
- `NO` — stored but never pushed; reminders never fire.
- pending (`ai_verdict IS NULL`) — also not pushed; re-judged next
  judge cycle.

The judge prompt treats missing required spec fields (e.g. spec says
"PW12 fw 5.18.x" but the link omits generation or firmware) as `NO`,
not `UNCLEAR`. A notification the user has to hand-verify is a failed
filter. Write specs with concrete constraints — model number, firmware
range, version, platform — so the judge has something to enforce.

### Corroboration

Every verdict is tagged with a normalized `subject` (the product or
system, e.g. `electrum bitcoin wallet`) and an `incident` drawn from a
fixed list (`vulnerability`, `exploit`, `phishing`, `supply-chain`,
`malware`, `outage`, `release`, `announcement`, `other`), plus a
human-readable `claim` for display.

Each cycle, an `UNCLEAR` event is matched against events from *other*
watchers inside `WATCH_CORROBORATE_WINDOW` hours (default 72) carrying
a matching `subject` and an incident from the same family — `security`
(vulnerability, exploit, phishing, supply-chain, malware),
`availability`, `shipping`, or `other`. Families exist because one
incident is legitimately labelled differently by different outlets: the
same Electrum attack came back as `exploit` from one source and
`phishing` from another. A match promotes both to
`GO` with reason `corroborated by event <id>` and the normal push gate
delivers them. One source saying something shaky stays quiet; two
independent sources agreeing is the confirmation.

Matching is **deterministic string work, not a second LLM opinion** —
subjects match on exact equality or token subset (`electrum wallet`
corroborates `electrum bitcoin wallet`; `wallet` alone is too generic
to match). An earlier design asked the model whether two free-text
claims described the same event; qwen3:14b reliably answered "no" over
wording differences alone ("flaw" vs "attack" about one incident), which
would have made `UNCLEAR` just as much a dead end as `MAYBE` was.
Extraction is what the model is good at; equivalence judgement is not.

### Spec decidability

A spec that demands facts its source never carries produces an endless
`NO` streak that reads exactly like a broken pipeline — this is what
kept the stack silent through Aug 2026. Each spec is audited once
against what its source kind actually emits (`hn_search` yields titles,
`github_release` yields release notes, and so on). Undecidable specs
are flagged with the problems found and a suggested rewrite, visible in
`GET /api/watchers`, the web UI, `/list` and `/status`. Editing a spec
requeues the check. The flag is advisory — nothing is ever blocked.

The judge runs as its own asyncio loop, decoupled from the poller, so
slow local-LLM calls never block source polling. `WATCH_JUDGE_INTERVAL`
(default 30s) controls cycle cadence; `WATCH_JUDGE_BATCH` (default 3)
caps events per cycle. Unjudged events queue indefinitely — no rush.

If the desktop ollama is unreachable, the judge logs and retries next
cycle. If link fetch fails (timeout, 4xx, binary content type), the
model falls back to title+summary; per the hard rules above, missing
required fields → `NO`, so unverifiable events stay silent.

`.env` (all optional, defaults live in the code):
```
WATCH_OLLAMA_URL=http://100.115.80.79:11434    # desktop tailnet
WATCH_OLLAMA_MODEL=qwen3:14b
WATCH_OLLAMA_TIMEOUT=180
WATCH_OLLAMA_NUM_CTX=16384
WATCH_JUDGE_INTERVAL=30
WATCH_JUDGE_BATCH=3
WATCH_LINK_MAX_CHARS=8000
WATCH_LINK_TIMEOUT=20
WATCH_CORROBORATE=1
WATCH_CORROBORATE_WINDOW=72
WATCH_CORROBORATE_CANDIDATES=12
WATCH_SPEC_LINT_BATCH=2
```

Telegram: `/spec <id> <text>` sets the spec, `/judge <event_id>`
forces re-judge, `/verdicts <id>` tallies. Web UI exposes the same
via the per-watcher `spec` button and the `re-judge` button on each
event row.

## Knowing whether it is working

Silence is ambiguous: a healthy pipeline whose filters reject
everything looks identical to a dead one. Two places answer it.

`GET /healthz` always returns 200 (so the container healthcheck keeps
meaning "process serves HTTP") and reports `ok`, a `degraded` list,
per-task liveness for the poller/judge/telegram loops,
`telegram_enabled`, `last_poll_at`, `last_push_at`, `pending_unjudged`,
watcher tallies, and verdict funnels over 24h and lifetime.

Telegram `/status` renders the same funnel from the phone, plus any
undecidable-spec warnings. `last push: never` with a healthy funnel
means the filters are rejecting everything; `telegram: DISABLED` or a
dead task means the pipeline itself is broken.

## Delivery

A push is only recorded once every configured channel confirms it.
Telegram 429s are retried once honoring `retry_after`; transient
failures (network, 5xx, exhausted retry) leave `last_reminder_at`
unset so the next poll cycle tries again. Permanent 4xx rejections are
logged at ERROR and not retried forever. When no channel is configured
at all, events are marked delivered so the dashboard stays usable, and
the missing configuration is logged at ERROR on every startup.

## Tests

```
nix develop /etc/nixos/mandragora#watch -c \
  pytest nix/hosts/mandragora-vps/compose/watch/app
```

The image builds through a `test` stage that runs the same suite, so
`docker compose up -d --build` fails on a red test and the deployed
image never carries pytest.

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

The container reads this file via compose `env_file`, which resolves
relative to the compose file rather than the invoking shell's cwd. A
missing `.env` now fails the compose command outright instead of
silently starting with empty credentials.

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
