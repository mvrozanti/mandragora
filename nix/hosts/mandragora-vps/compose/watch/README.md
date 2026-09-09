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
> power — default to dumb feed logic. Before adding an `ai_spec` at all, check
> whether the question has a fact source: `tvmaze_season` replaced three
> spec'd watchers that were 96% of the judge's entire workload.


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

## Give the judge something to read

`fetch_link` on a Google News RSS link returns **HTTP 200 and zero characters**. The
link is not an article; it is a 587 KB Angular shell that resolves the real URL
client-side over an internal RPC. The publisher address appears nowhere in the page —
the only external URLs in it are Google fonts, analytics and logos.

So every event from the `gnews` watcher was judged on a headline. "Does this report a
security vulnerability affecting Electrum?" asked of twelve words like *"CZ Warns
Bitcoin Holders After $70 Million Wallet Exploit"* is not a comprehension task, it is
a guess — which is why the model kept asserting Electrum. Tightening the search query
would not have helped: it changes what arrives, not what can be read.

`lint_spec` did not catch it because `SOURCE_EMITS["rss"]` promises "the article body
reachable only by fetching that link". For Google News that promise is false, so the
lint vouched for a spec its source could not support. Aggregator feeds remain the one
case where the fetch does not reach an article, and the reason publisher feeds are
preferred; the lint cannot tell them apart from the feed URL alone.

The fix is the source. Four publisher feeds replaced it — BleepingComputer, Security
Affairs, The Hacker News, Malwarebytes — whose items link straight to articles that
fetch 6–8 k characters of readable text. Being four separate watchers also makes them
eligible to corroborate each other, which one aggregated feed never could. The old
`gnews` watcher is paused rather than deleted, so its two genuine historical triggers
survive.

**`must_mention` runs before the model, not after.** The link is fetched, the required
literals are checked against title + summary + body, and only then is the LLM called.
General security feeds carry a lot of traffic — the first poll took 95 items, none of
which name Electrum anywhere — and none of those cost a judgement. Because the body
counts, an article that only mentions Electrum halfway down still gets read properly.

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
| `reddit_user`     | `/user/:name.rss`                                        |
| `reddit_sub`      | `/r/:name/new.rss`                                       |
| `youtube_channel` | `https://www.youtube.com/feeds/videos.xml?channel_id=…`  |
| `twitch_stream`   | Helix `/streams?user_login=…` (live transitions only)    |
| `hn_search`       | HN Algolia `search_by_date?query=…&tags=story`           |
| `reddit_search`   | `https://www.reddit.com/search.rss?q=…&sort=new`         |
| `rss`             | any RSS 2.0 / Atom feed URL                              |
| `tvmaze_season`   | TVmaze `/shows/:id?embed=seasons`, one season's status   |

Twitter intentionally skipped — nitter is unreliable, RSSHub self-host
is the planned route. Add a `twitter_*` kind in `sources.py` when
ready.

### Reddit answers `.rss`, not `.json`

Reddit's JSON API returns `403` to this VPS — Oracle Cloud address space is
blocked outright, and no User-Agent changes that. The Atom endpoints on the same
paths answer `200`. Four `reddit_search` watchers sat at zero events from May to
Sep 2026 because the stack asked for `search.json`; the same query against
`search.rss` returns 25 entries. Never move a reddit kind back to `.json`.

Two consequences of the Atom shape. Reddit *HTML* permalinks are `403` here too,
so an entry's link is set to the post's outbound URL — parsed out of the entry's
`content` — and only falls back to the permalink for self-posts, where the body
is already in `content` and is kept whole (`WATCH_REDDIT_SUMMARY_MAX`, 4 k) rather
than clipped to a headline. Search results also include subreddit hits (`t5_`
ids); those are dropped.

The feeds rate-limit at roughly one request per minute from this address —
measured 2026-09-08: four probes 60s apart all returned `200`, four probes 30s
apart returned `200` then three `429`s. Four reddit watchers cannot all poll in
one cycle, and pacing them 60s apart inside the cycle would stall every other
watcher behind them, so `ration_reddit` admits `WATCH_REDDIT_PER_CYCLE` (1) of
them per pass, least-recently-polled first. At the 300s poll interval each reddit
watcher is checked every ~20 minutes, which is ample for "has the season
dropped". `WATCH_REDDIT_MIN_INTERVAL` (60s) stays as a floor for manual
`/poll` calls, and rationing means the poller itself never waits on it.

## Ask a fact source before you ask a model

Three `reddit_search` watchers — severance s3, pluribus s2, hazbin s3 — were
1460 of the 1496 events waiting on a verdict on 2026-09-09. Each asked
`qwen3:14b` roughly 1500 questions a day to catch an answer that arrives once a
year, which is why the judge loop kept a 14b model resident in 11 GB of VRAM
around the clock and why it was switched off. Switching it off made every
`ai_spec` watcher silent, including the security ones.

None of those three was a fuzzy question. TVmaze already carries the answer as a
field:

```
Severance  44933  season 3: premiereDate=null   ← the row exists, undated
Pluribus   86175  season 2: premiereDate=null
Hazbin     43094  seasons 1-2 only              ← a season 3 row appearing IS the event
```

`tvmaze_season` (target `<show>:<season>`, e.g. `severance:3`, resolved to
`44933:3` at add time) polls that one endpoint and stores the season's state as
its cursor: `absent`, `listed`, `listed:eps=10`, `dated:<date>`,
`aired:<date>`. Every transition is one event with a headline that says what
changed. The first poll records the baseline silently, exactly like the release
layer's backlog suppression, so adding a watcher today pings you the day the
premiere date appears and again the day it airs — not before.

The general rule this encodes: **when a question has a fact source, poll the
fact source.** A model asked to read fan chatter is guessing at something an API
states outright, and it costs a GPU to guess. GitHub Releases, TVmaze, Steam
appdetails, PyPI and endoflife.date all answer their own questions. The judge is
for the questions with no such source — a CVE mentioning a specific wallet, a
jailbreak for a specific firmware — and those arrive a handful at a time.

## The judge must never be the reason nothing fires

`ai_spec` used to be a hard, fail-closed gate: no verdict meant no push, with no
timeout and no fallback, so a judge that was off was indistinguishable from a
world where nothing had happened. It stayed that way from 2026-09-08 to
2026-09-09 with 1496 events held behind it.

There are now two judges, and only one of them needs a model.

**The deterministic sweep runs whether or not the model loop does.** Every
`WATCH_JUDGE_INTERVAL` it takes events that are past `WATCH_JUDGE_DEADLINE_HOURS`
(24) without a verdict and disposes of them with set logic alone:

- the watcher's `must_mention` literals are checked against title, summary and
  the fetched body — absent means `NO`, written with the usual refusal reason.
  Watchers with a literal gate therefore self-clear forever, with no model.
- anything the literals cannot dismiss — or any event on a watcher with no
  `must_mention` — is **escalated**: `escalated_at` is stamped, `ai_verdict`
  stays `NULL`, and the push gate lets it through badged `⚪ UNJUDGED`.

A false positive costs one Telegram message. A false negative costs the entire
point of the system. The escalation is deliberately the cheap failure.

**The sweep holds while the model loop is working.** If `WATCH_JUDGE_ENABLED` is
on and any verdict has been written in the last `WATCH_JUDGE_STALL_HOURS` (1),
the sweep does nothing at all — a deep queue that is draining is not a stalled
pipeline, and escalating out from under a working model would push events the
model was about to reject. With the loop off, or with no verdict for an hour,
the sweep runs. That rule is also what makes a backlog safe to deploy into.

**Held events are no longer pruned.** `_prune` trimmed to
`WATCH_MAX_EVENTS_PER_WATCHER` by id regardless of verdict, so w6 and w7 sat at
exactly 500/500 all-unjudged: events were being deleted before anything ever
looked at them. Judged events still trim at the cap; unjudged ones survive until
`cap × WATCH_UNJUDGED_KEEP_FACTOR` (4) as a runaway stop.

**Silence is now reported.** When more than `WATCH_ALERT_PENDING` (200) events
are waiting on a verdict, the poller sends one Telegram alert per
`WATCH_ALERT_INTERVAL` (6h) naming the backlog, the escalated count and the last
push. `/healthz` reports `judge_model_loop`, `judge_deadline_hours`,
`judge_fallback` and `escalated_open`; a judge that is off by configuration now
reads `sweep-only` rather than `dead`, and the dashboard banner says what will
still happen rather than "nothing will fire until it is back".

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

**Off by default.** The background judge loop is gated behind
`WATCH_JUDGE_ENABLED`, which defaults to `0`. Watchers do not reach for
the local model on their own any more: at `WATCH_JUDGE_INTERVAL=30` and
`WATCH_JUDGE_BATCH=3` the loop sustained ~180 judgements/hour, which
matched the event intake rate, so the queue never drained and
`qwen3:14b` stayed pinned in 11 GB of the desktop's VRAM around the
clock. Across the whole history that bought 2 `GO` verdicts against
1676 `NO`.

With the loop off, `ai_spec` watchers stay at `ai_verdict IS NULL` and
so never push (see the pending row below). `POST /api/events/{eid}/judge`
and spec lint still reach the model, because those are started by hand.
Set `WATCH_JUDGE_ENABLED=1` in the compose `environment:` to restore the
loop.

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
  judge cycle, or left pending indefinitely while the loop is off.

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
against the material the judge will actually hold. Undecidable specs
are flagged with the problems found and a suggested rewrite, visible in
`GET /api/watchers`, the web UI, `/list` and `/status`. Editing a spec
requeues the check. The flag is advisory — nothing is ever blocked.

The audit is only as good as its description of the source, and through Sep 2026
that description was wrong in the strict direction. `SOURCE_EMITS` listed the
pre-fetch row (`hn_search` = "title, url and points, **without** the linked
article body") while `judge_event` has always fetched the linked page first and
handed it to the model. The prompt then named that exact case — "asking a
title-only search to confirm details that only appear in an article body" — as
its first example of undecidable. Every spec that relied on the body was
therefore condemned: 8 of 13 spec'd watchers wore "spec unanswerable", including
`pluribus s2 release`, and the only specs that passed were the ones carrying an
explicit "judge from the headline alone" clause. `SOURCE_EMITS` now describes
what the judge holds, the prompt forbids the body-is-missing verdict outright,
and rarity is stated not to imply undecidability.

Two guards came out of it. A `suggestion` that merely echoes the spec back is
dropped rather than shown — the model returned the spec verbatim for w7 and w26.
And each result carries `SPEC_LINT_VERSION`; `lint_pending_specs` re-lints any
watcher whose stored version is behind, so changing the prompt no longer leaves a
DB full of verdicts from the prompt that produced them. Bump the version whenever
the prompt or `SOURCE_EMITS` changes.

**The model no longer stays resident.** Every ollama call carries
`keep_alive` (`WATCH_OLLAMA_KEEP_ALIVE`, default `60s`), so the model unloads a
minute after the queue goes quiet instead of holding 11 GB indefinitely. With
the show watchers moved to `tvmaze_season` the queue is quiet almost always, so
the GPU sees a few seconds of work a day rather than a permanent tenant.

**There is a slot for a remote model, and it is deliberately empty.** Setting
`WATCH_JUDGE_FALLBACK_URL` + `_KEY` + `_MODEL` makes a connection failure to
ollama retry against any OpenAI-compatible endpoint. Unset — the default, and
the current state — the call simply fails and the event stays pending until the
deadline sweep reaches it. The chain is local model → deterministic escalation,
with a cloud model as an optional middle link.

It stays empty because the fallback only fires when the desktop is unreachable,
and the desktop does not go down: five weeks of uptime as of 2026-09-09. The
measured load behind the slot is ~16 model calls a day (41 events arrive; the
`must_mention` gates refuse 153 of every 284 for free, including every one of
the four security feeds), so a paid endpoint would buy insurance against a
scenario that has not occurred, and a free tier would too. If the slot is ever
filled, the free Gemini tier the retired desktop bridge used is the obvious
candidate — but only as a backend *inside* this judge. A second judging loop
with its own prompt is what commit `d9fb5d0d` removed, because two judges
claiming the same events made a verdict depend on which loop won the race.

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
WATCH_OLLAMA_KEEP_ALIVE=60s
WATCH_JUDGE_DEADLINE_HOURS=24
WATCH_JUDGE_STALL_HOURS=1
WATCH_JUDGE_SWEEP_BATCH=20
WATCH_JUDGE_FALLBACK_URL=                      # empty by design, see above
WATCH_JUDGE_FALLBACK_MODEL=
WATCH_JUDGE_FALLBACK_KEY=
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
WATCH_REDDIT_MIN_INTERVAL=60
WATCH_REDDIT_PER_CYCLE=1
WATCH_REDDIT_SUMMARY_MAX=4000
WATCH_UNJUDGED_KEEP_FACTOR=4
WATCH_ALERT_PENDING=200
WATCH_ALERT_INTERVAL=21600
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
