# `crypto-fetcher/` — RETIRED 2026-05-16

**Status:** dead. Stack stopped, containers removed on `mandragora-vps`,
live compose file renamed to `docker-compose.yml.retired-2026-05-16`
under `/home/opc/crypto-experiments/crypto-fetcher/`. The nix-repo
`docker-compose.yml` has been deleted; this `RETIRED.md` is the
tombstone.

## Note to future agents

If you are about to resurrect this stack — **don't, without asking
the user first.** The stack was deliberately killed on 2026-05-16,
not lost to neglect. Reasons:

1. **Log noise dominated everything.** `crypto-fetcher-binance_fetcher-1`
   wrote ~700 MB/day to docker's json-file driver. Even after the
   per-stack `logging:` cap (50m × 5 files, set 2026-05-08), it was
   the loudest container on the VPS by an order of magnitude.
2. **It would have eaten the new log aggregator's budget.** On
   2026-05-16 we started building a Loki-based log aggregator at
   `log.mvr.ac` capped at **2 GB or 3 days** (whichever hits first).
   Letting binance_fetcher continue to firehose would have evicted
   every other service's logs within ~3 days, defeating the
   purpose of central logging. Adding Promtail drop-rules to mute
   the noise was the alternative; the user chose to kill the
   producer instead.
3. **No active consumer.** The binance_fetcher wrote tick data to a
   colocated `redis:6.2-alpine` (network_mode: host, no volume) and
   nothing downstream was reading from it. The redis was ephemeral
   in-container, so no data of value was destroyed — just
   in-flight ticks.
4. **It is not the hummingbot/HFT stack.** The HFT stack at
   `/home/opc/high-frequency-trading-experiments/` (intentionally
   untracked, see `../README.md`) is a separate concern and was
   **not** touched. Don't confuse them.

## What was killed

| Component | What |
|---|---|
| Service `binance_fetcher` | Built locally from `/home/opc/crypto-experiments/crypto-fetcher/` (the Dockerfile + source live there, not in this repo). Polled Binance, pushed ticks into redis. |
| Service `redis` (the bare-named one) | `redis:6.2-alpine`, host-network, no volume. Separate from `authelia-redis` and `seafile-redis`, which keep running. |

## If the user asks to bring it back

1. Restore the compose file: `mv /home/opc/.../docker-compose.yml.retired-2026-05-16 .../docker-compose.yml`
2. Restore this repo copy from git: `git show <pre-retirement-commit>:nix/hosts/mandragora-vps/compose/crypto-fetcher/docker-compose.yml`
3. **Before bringing it up**, plumb its stdout into a Promtail drop-rule
   (or send it to `/dev/null` via `logging.driver=none`) so it
   doesn't recapture the log-budget problem that killed it in the
   first place.
4. Update `../README.md` to move it back from "deliberately not
   tracked" into "Stacks tracked".

## Cross-references

- Decision note: `mandragora-desktop-obsidian-vault/decisions/Retire crypto-fetcher.md`
- Memory: `feedback_no_crypto_fetcher.md` in the Claude auto-memory index
- Per-stack logging context: `../../../compose/README.md` "Per-stack logging blocks" rationale + vault `decisions/Per-stack docker logging.md`
