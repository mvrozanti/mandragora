# `watch` — perception layer

FastAPI app + background poller that watches external sources (GitHub
users/repos, Reddit users/subs) and emits new items as webhook POSTs.
Served at `https://watch.mvr.ac`, Authelia-gated.

> **Agent directive — there is no model in this system, and that is the
> design.** Every watcher is a plain HTTP poller and every decision is a
> keyword rule or a structured field. Do **not** add an LLM call to a
> watcher, source, template or feature — not for summarising changelogs,
> classifying events, generating digests or tagging anything. The model was
> removed on 2026-09-12 after measurement, not preference: see *Why there is
> no model* below. If you believe a question genuinely needs one, stop and
> ask the user first, and bring numbers.


## The model: a watch is a standing question

Each watcher is a question you are waiting on, and it is in exactly one state:

| state | meaning |
|---|---|
| **waiting** | nothing has fired yet |
| **triggered** | something fired and you have not accepted it |
| **done** | everything that fired has been accepted, in the web UI or from the Telegram link |

A *trigger* is an event that reached you: a `GO` verdict, or — for a watcher with no
`match_rule` — any event, since everything that source emits passes by definition. The
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
| `anticheat_game`  | areweanticheatyet `games.json`, Linux status per title   |

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
are still polled, stored, matched, and visible in the UI, but the
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

## Why there is no model

This stack ran an LLM relevance judge from May to September 2026. It was removed
after being measured against the database it had been judging.

| measurement | result |
|---|---|
| Events the four security RSS feeds delivered | 212 |
| Refused by the literal keyword `electrum` before any model ran | **212** |
| Times the model was called on those feeds | **0** |
| Real Electrum stories the keyword `electrum` catches | **4** |
| Real Electrum stories the model ever passed | **2** |
| AI-gated watchers that ever delivered anything, lifetime | **0 of 10** |

The keyword did not merely match the model. It beat it: replaying `electrum` over
all 337 events those watchers ever saw returns four genuine stories, including
"Electrum Bitcoin wallets under siege" and a Bitmessage zero-day used to steal
Electrum keys — both of which the model withheld.

The clearest case was the kindle watcher. On 2026-09-12 a post titled *"KPM does
not work after jailbreak with Vera on Paperwhite 12th gen"* — a report of the
exact jailbreak w4 exists to find — was judged `NO`, because the post's firmware
was 5.17.1.0.4 and the spec demanded 5.18+. The judge applied the spec correctly
and thereby destroyed the only signal that mattered. 74 jailbreak posts were
withheld this way. `paperwhite AND jailbreak` delivers them.

The general lesson: an over-precise rule enforced by a literal-minded reader
fails *closed and silently*, and silence is the one failure mode this system
cannot afford. A keyword rule fails open — you get some noise, you dismiss it,
and you keep the signal.

### `anticheat_game` — does it run on Linux yet

"Can I play Battlefield on Linux" is a status field, not an opinion.
[areweanticheatyet](https://areweanticheatyet.com) publishes `games.json` with one
of `Supported`, `Running`, `Denied`, `Broken` or `Planned` per title, and the
blocker for every modern Battlefield is EA anticheat.

The target is a name fragment, so one watcher covers a franchise: `battlefield`
matches fifteen titles. The cursor holds an ETag plus a `slug=status` digest, so a
poll is a **conditional GET** — 457 KB once, then HTTP 304 and zero bytes until the
file actually changes. Each status change emits one event per title:

```
Battlefield 6 is now Supported on Linux (was Denied)
```

Pair it with the rule `"now Supported" OR "now Running"` and it stays quiet for
everything except a title becoming playable. The phrase form matters: it is
direction-sensitive, so a regression — *"Battlefield 4 is now Broken on Linux (was
Supported)"* — does not fire, even though the word `Supported` is present.

## Match rules

`match_rule` on a watcher is a boolean expression evaluated over the event's
title and summary (`app/match.py`, no network, no dependencies):

```
electrum
paperwhite AND jailbreak
electrum AND (vulnerability OR exploit OR phishing)
"browser extension" OR "claude in chrome"
paperwhite AND jailbreak AND NOT ipod
```

- Whitespace means `AND`. `AND`/`OR`/`NOT` are operators only in uppercase, so a
  lowercase `and` is a literal word.
- Terms match on **word boundaries**, so `electrum` no longer matches
  *Electrostatic* or *Electron* — the two things that cost 31 model calls on HN.
- `"quoted phrases"` match as a phrase, tolerating runs of whitespace.
- An empty rule means everything the source emits reaches you.

Set one with `/match <watcher_id> <rule>` or the web UI. An unparseable rule is
rejected at the point you set it; a rule that somehow breaks at poll time lets the
event through rather than swallowing it.

The old `must_mention` column migrates into `match_rule` automatically on startup.

## A watch watches a condition

A **watch** is the thing you create. It *has* a condition, and it looks in one or
more **places** to decide whether that condition has been met. The watch is what
you name, list and delete; the places are plumbing.

That distinction is load-bearing, and getting it wrong showed up as duplication:
before `watches` existed, the condition was copied onto every source row — 18 rows
holding 10 conditions — and "a new kindle jailbreak is released" was split across
two different `watch_group` values, so nothing in the schema actually identified
the watch. A `watches` table with `watchers.watch_id` pointing at it fixes the
normalisation and makes the surface honest at the same time: `/list` and `/del`
take a watch id, and a stop condition counts deliveries across the whole watch.

You say the condition you are waiting on and nothing else:

```
/watch a battlefield game becomes playable on linux
/watch severance season 3 is released
/watch electrum has a security advisory
```

Where to look, and what counts as the condition being met given a pile of
headlines and descriptions, is decided **once, at registration**, by the model.
After that it is plumbing: `condition` is what the dashboard tile, `/list` and
every notification say, and `kind`, `target` and `match_rule` are columns nobody
should have to think about.

There have been two failed attempts at a vocabulary here and both failed the same
way. Templates (`tv`, `advisory`, `feeds`…) needed a new entry the day
`anticheat_game` landed. Source kinds needed the user to know that a TV season and
a security advisory are different sorts of thing. Both were a second list to keep
in sync, and a second thing to get wrong, on top of the one list that already
exists in the code. Neither is user-facing now, and a test asserts that no source
kind name appears in `HELP`, in the `/watch` prompt, in `/list`, or in the message
confirming a watch was created.

**No model ever reads what is posted online.** That constraint is unchanged and is
what makes registration-time interpretation affordable — the model runs once per
watch you create, and the running system is keyword matching over fetched text.

Internally a condition becomes one or more sources, each with a keyword rule, all
sharing a `watch_group` so a stop condition counts across them. Everything the
model proposes is checked before anything is saved: the kind must exist, the
target must validate, `sources.target_exists` must find it on the real API, and a
live fetch must return. Whatever fails is dropped; if nothing survives, no watch
is created rather than one that cannot fire.

Providers, tried in order and configured by key presence alone:

```
WATCH_LLM_DEEPSEEK_KEY=sk-...       # tried first
WATCH_LLM_ANTHROPIC_KEY=sk-ant-...  # tried if deepseek is absent or fails
```

With neither, `/watch` says so. `/add <kind> <target>` and `/match <id> <rule>`
still work as unadvertised repair tools — they are how you fix a watch whose rule
the model got wrong, and the only way in if no provider is configured.

The prompt carries one hard-won instruction: **never restate what the source
already scopes.** `paperwhite AND jailbreak` on a Kindle jailbreak forum measured
at 20% recall, because announcements name models as `PW6` and never contain the
generic word. Every extra term can only lose signal.

## Match rules

`match_rule` on a watcher is a boolean expression evaluated over the event's
title and summary (`app/match.py`, no network, no dependencies):

```
electrum
paperwhite AND jailbreak
electrum AND (vulnerability OR exploit OR phishing)
"browser extension" OR "claude in chrome"
paperwhite AND jailbreak AND NOT ipod
```

- Whitespace means `AND`. `AND`/`OR`/`NOT` are operators only in uppercase, so a
  lowercase `and` is a literal word.
- Terms match on **word boundaries**, so `electrum` no longer matches
  *Electrostatic* or *Electron* — the two things that cost 31 model calls on HN.
- `"quoted phrases"` match as a phrase, tolerating runs of whitespace.
- An empty rule means everything the source emits reaches you.

Set one with `/match <watcher_id> <rule>` or the web UI. An unparseable rule is
rejected at the point you set it; a rule that somehow breaks at poll time lets the
event through rather than swallowing it.

The old `must_mention` column migrates into `match_rule` automatically on startup.

## Registering a watch by describing it

`/watch tell me when a battlefield game runs on linux` — one sentence, and the
watch exists. A model turns the sentence into sources; nothing else changes.
**No model ever reads what is posted online.** Runtime matching stays keyword-only.
The model runs once per watch you create.

It picks from the **source kinds themselves** — the same list `/add` accepts and
`SOURCE_EMITS` describes. There is deliberately no template or category layer in
between: a taxonomy has to grow every time a source kind is added, and the one
that briefly existed here already needed a seventh entry the day `anticheat_game`
landed. The kinds are the vocabulary; anything else is a second thing to keep in
sync and a second thing to get wrong.

Its blast radius is a `{kind, target, match}` triple, and every part is checked
before anything is saved: the kind must exist, `sources.validate_target` must
accept the target, `sources.target_exists` must find it on the real API, and a
live fetch must return. Sources that fail are dropped with a reason; if none
survives, nothing is created rather than a watch that cannot fire. That is what
caught an invented `electrum-maintainers/electrum` and a hallucinated NYT feed.

Providers are tried in order, configured by key presence alone:

```
WATCH_LLM_DEEPSEEK_KEY=sk-...       # tried first
WATCH_LLM_ANTHROPIC_KEY=sk-ant-...  # tried if deepseek is absent or fails
```

With neither set, a sentence says so and points at `/add <kind> <target>`, which
needs no model. A **Claude Code subscription is not an API key** — the Anthropic
leg stays inert until a real one exists.

The reply carries the watcher ids, the rule, and a volume estimate measured from
the items just fetched — `~3 msgs/month`, or *"nothing in the recent sample
matches"* for a rule born dead. It gates nothing; the watch exists the moment you
ask. `/match <id> <rule>` changes any rule afterwards.

The prompt carries one hard-won instruction: **never restate what the source
already scopes.** `paperwhite AND jailbreak` on a Kindle jailbreak forum measured
at 20% recall, because announcements name models as `PW6` and never contain the
generic word. Every extra term can only lose signal.

## Match rules

`match_rule` on a watcher is a boolean expression evaluated over the event's
title and summary (`app/match.py`, no network, no dependencies):

```
electrum
paperwhite AND jailbreak
electrum AND (vulnerability OR exploit OR phishing)
"browser extension" OR "claude in chrome"
paperwhite AND jailbreak AND NOT ipod
```

- Whitespace means `AND`. `AND`/`OR`/`NOT` are operators only in uppercase, so a
  lowercase `and` is a literal word.
- Terms match on **word boundaries**, so `electrum` no longer matches
  *Electrostatic* or *Electron* — the two things that cost 31 model calls on HN.
- `"quoted phrases"` match as a phrase, tolerating runs of whitespace.
- An empty rule means everything the source emits reaches you.

Set one with `/match <watcher_id> <rule>` or the web UI. An unparseable rule is
rejected at the point you set it; a rule that somehow breaks at poll time lets the
event through rather than swallowing it.

The old `must_mention` column migrates into `match_rule` automatically on startup.

## Registering a watch by describing it

`/watch tell me when there is a new kindle jailbreak` — one sentence, and the
watch exists. A model turns the sentence into a template plus arguments, and
nothing else about the system changes: **no model ever reads what is posted
online.** Runtime matching stays keyword-only. The model runs once per watch you
create, perhaps ten times in this system's lifetime.

The model may only *fill in* one of the templates below. It cannot invent a
source kind, a template, or a field, so its blast radius is an argument list.
Everything after it is the same validation the template path already used:
`sources.validate_target`, then `sources.target_exists` against the real API,
then a live fetch. Sources that fail are dropped with a reason; if none survives,
no watch is created rather than a watch that cannot fire. This is what caught the
invented `electrum-maintainers/electrum` and a hallucinated NYT feed URL.

Providers are tried in order and configured by key presence alone:

```
WATCH_LLM_DEEPSEEK_KEY=sk-...       # tried first
WATCH_LLM_ANTHROPIC_KEY=sk-ant-...  # tried if deepseek is absent or fails
```

With neither set, a sentence returns "no model provider configured" and the
template form below keeps working untouched. A **Claude Code subscription is not
an API key** — the Anthropic leg stays inert until a real key exists.

The reply carries the watcher ids, the rule, and an estimate measured from the
items just fetched — `~3 msgs/month`, or *"nothing in the recent sample matches"*
for a rule that would be born dead. It does not gate anything; a watch is created
the moment you ask. Change any rule afterwards with `/match <id> <rule>`.

What this deliberately does not do is catch a rule that is *bad but not dead*.
`paperwhite AND jailbreak` matched a few things and missed every announcement, at
20% recall; only replaying history against known-good items exposed that, and no
preview screen would have. The estimate catches the zero case and nothing subtler.

## Templates: registering a watch by hand

The hard part of this system was never the polling — it was registering a watch.
Choosing a source kind, a target, a spec strict enough to decide and loose enough
to match, and a literal gate, where any one being wrong produces silence that
looks exactly like "it has not happened yet". Ten watchers died that way.

So registration is a template plus a live check. `/watch` with no arguments lists
them:

| template | example |
|---|---|
| `tv` | `/watch tv severance 3` |
| `advisory` | `/watch advisory spesmilo/electrum` |
| `release` | `/watch release neovim/neovim 0.12` |
| `feeds` | `/watch feeds electrum https://www.bleepingcomputer.com/feed/` |
| `sub` | `/watch sub kindlejailbreak paperwhite AND jailbreak` |
| `repo` | `/watch repo spesmilo/electrum` |

Nothing saves until the plan is checked against reality: every target is
format-validated, **existence-checked against the real API**
(`sources.target_exists` — it catches invented repos, dead feeds, and the
tag-only-repo trap where a project publishes tags but no Releases), then fetched
live, and the match rule is run over real items with the result shown. All of it
is instant and free.

`stop_after` ends a watch once it has said its piece — 1 for a season releasing,
0 for an ongoing condition — counted across every source in one plan via
`watch_group`, so two sources answering one question stop together.

## Knowing whether it is working

Silence is ambiguous: a healthy pipeline whose filters reject
everything looks identical to a dead one. Two places answer it.

`GET /healthz` always returns 200 (so the container healthcheck keeps
meaning "process serves HTTP") and reports `ok`, a `degraded` list,
per-task liveness for the poller and telegram loops, `model_calls_possible`
(always `false`), `telegram_enabled`, `last_poll_at`, `last_push_at`,
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

## Kindle Paperwhite gen 12 jailbreak watch — answered

**The question this watch existed to answer is answered.** Two jailbreaks cover
the PW12:

| | released | PW12 firmware range | method |
|---|---|---|---|
| **Véra** | 2026-08-10 | 5.17.1 – **5.19.6** | the Kindle's own web browser, no computer |
| **SpiderCat** | 2026-09-01 | 5.16.3 – **5.19.5** | download one book and open it |

Only Véra reaches 5.19.6, so a device already on the newest firmware has exactly
one route. Both live at [kindlemodding.org](https://kindlemodding.org/jailbreaking/),
whose wizard checks a specific device and firmware. A Kindle left online will
happily update itself out of range while you procrastinate.

The watch did not deliver either of them, and the reason is the whole argument in
*Why there is no model*. On 2026-09-12 the reddit watcher saw *"KPM does not work
after jailbreak with Vera on Paperwhite 12th gen"* and the judge returned `NO` —
"firmware 5.17.1.0.4 < 5.18" — because the spec demanded 5.18+ and that post
happened to mention an older firmware. The spec was right about the firmware it
cared about and wrong about the post, and a month of Véra coverage went by unread.

### A rule may not re-scope what the source already scoped

The first keyword rule here was `paperwhite AND jailbreak`, and it was measured
the next day at **20% recall**: it misses four real signals in five, including
*both* jailbreak announcements. Announcement headlines say "Kindles", or name the
model as `PW6` — the literal string "paperwhite" is exactly what an announcement
does not contain.

That rule missed the Véra announcement **which was already in the database**.
Forum 150 carried `Tools [New Jailbreak] Vera - KT5/PW5/KT6/PW6/CS/KS/KS2 up to
5.19.6` on 2026-08-24. The LLM judge had refused it — *"targets PW5/KT5 (not
PW12), firmware 5.19.6 (user needs 5.18.x/5.19.x)"*, with `PW6` sitting in the
title and 5.19.6 being a 5.19.x — and then the keyword rule that replaced the
judge refused it again, three weeks later, for a different reason. The same event,
on the right source, killed twice by two architectures.

The lesson is narrow and reusable: **the source already scopes the topic.** Forum
150 is the Kindle Developer's Corner, `r/kindlejailbreak` is what its name says,
the ebook-reader blog covers e-readers. Re-asserting the topic inside the rule
adds no precision and silently costs recall.

The sources now, with volume and recall measured over 106 days of history:

| source | rule | msgs/month |
|---|---|---|
| mobileread forum 150 | `jailbreak` | 3.1 |
| the-ebook-reader.com feed | `jailbreak` | 0.3 |
| hn_search | `jailbreak` | 0.3 |
| reddit_search | `(jailbreak OR jailbroken) AND (new OR released OR release OR tools OR announcing OR "up to")` | 4.8 |

Reddit is 80% of the raw volume and almost none of the announcements — it is
help-request chatter — so it alone carries the announcement-shaped clause, which
cuts it from 14.4/month to 4.8 without losing a single known announcement. The
other three stay deliberately dumb: they are low-volume enough that a bare
`jailbreak` costs nothing, and a rule that cannot be too clever cannot be wrong.

Total **8.5 messages/month at 100% recall** on every announcement in the history
(Véra, Sanctuary, SpiderCat, AdBreak), each reaching you through more than one
watcher. The prior configuration was 3.4/month at 20%.

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
